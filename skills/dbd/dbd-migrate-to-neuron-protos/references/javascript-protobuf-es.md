# JavaScript Protobuf-ES migration

Follow [`SKILL.md`](../SKILL.md) for when to use this skill, migration root rules, the
mapping rule, and the public-stubs invariant. This document is the **JavaScript procedure**
and **Protobuf-ES API guide**.

Legacy frontends use product-level npm packages (`@internal.<product>.<domain>/protobuf`),
`google-protobuf` message classes, and `grpc-web` `*PromiseClient` stubs. The target stack
uses:

- **Per-neuron product packages:** `@alis.build/*` from `define-ecmascript` (private Artifact
  Registry)
- **Shared common stubs:** individual `@alis-build/*` packages on **public npm** (protoc-gen-es
  - Connect)
- **Runtime:** [Protobuf-ES](https://protobufes.com/) (`@bufbuild/protobuf`) and
  `@connectrpc/connect-web`

This migration covers **two coupled changes**:

1. **Product package plumbing** — `@internal.*.protobuf` monolith → `@alis.build/<package-id-dashed>`.
2. **Common stub + runtime** — legacy monoliths (`@alis-build/google-common-protos`,
   `@alis-build/common`, `@alis-build/common-es`) → individual `@alis-build/<proto-package-dashed>`
   packages; `google-protobuf` + `grpc-web` → Protobuf-ES + Connect.

The Go BFF grpc-web proxy is unchanged — Connect's `createGrpcWebTransport` speaks the same
wire protocol.

---

## Part A — Procedure

### Two npm scopes

| Scope                    | Registry                                        | Role                                                         |
| ------------------------ | ----------------------------------------------- | ------------------------------------------------------------ |
| `@alis.build/*` (dot)    | Product `define-ecmascript` (Artifact Registry) | Per-neuron generated stubs for the product's own protos      |
| `@alis-build/*` (hyphen) | Public [npm](https://www.npmjs.com)             | Shared common stubs (google, `alis.open.*`, domain packages) |

Do not conflate them. Per-neuron migration uses `@alis.build/*`; common-stub migration uses
`@alis-build/*`.

### Per-neuron package naming

Target package: `@alis.build/<org>-<product>-<neuron-dashed>` (version segment kept, e.g.
`@alis.build/alis-os-mcp-v1`), served from the product's `define-ecmascript` Artifact Registry
repository.

**Package id dashed** = `focus_package_id` with dots replaced by hyphens (e.g.
`alis.os.evals.v1` → `@alis.build/alis-os-evals-v1`).

Import subpath after the package name mirrors the proto file path:

```
@alis.build/<package-id-dashed>/<org>/<product>/<neuron-path>/<file>_pb
```

Legacy imports ending in `_grpc_web_pb` become `_pb` — service descriptors live in the same
module as messages (`ExampleService`, not `ExampleServicePromiseClient`).

### Common stub package naming

Legacy common stubs came in **three generations**, all obsolete as migration targets:

| Generation           | Package                            | Generator                                                                    |
| -------------------- | ---------------------------------- | ---------------------------------------------------------------------------- |
| grpc-web             | `@alis-build/google-common-protos` | `*_grpc_web_pb`, `google-protobuf`                                           |
| grpc-web             | `@alis-build/common`               | Broader grpc-web monolith                                                    |
| protobuf-es monolith | `@alis-build/common-es`            | protoc-gen-es bundle — **overlaps split packages; do not migrate into this** |

**Target:** one npm package per proto `package`:

```
@alis-build/<proto-package-dashed>/<proto-file-path>_pb
```

**Naming rule:** `@alis-build/` + proto `package` with dots replaced by hyphens.

| Proto package             | npm package                           |
| ------------------------- | ------------------------------------- |
| `google.api`              | `@alis-build/google-api`              |
| `google.rpc`              | `@alis-build/google-rpc`              |
| `google.type`             | `@alis-build/google-type`             |
| `google.iam.v1`           | `@alis-build/google-iam-v1`           |
| `google.iam.v2`           | `@alis-build/google-iam-v2`           |
| `google.longrunning`      | `@alis-build/google-longrunning`      |
| `alis.open.iam.v1`        | `@alis-build/alis-open-iam-v1`        |
| `alis.open.validation.v1` | `@alis-build/alis-open-validation-v1` |
| `alis.open.agent.v1`      | `@alis-build/alis-open-agent-v1`      |
| `alis.agui.history.v1`    | `@alis-build/alis-agui-history-v1`    |
| `alis.evals.v1`           | `@alis-build/alis-evals-v1`           |

The import subpath after the package name stays the same as the proto file layout. Examples:

| Legacy import                                                  | Split target                                                 |
| -------------------------------------------------------------- | ------------------------------------------------------------ |
| `@alis-build/google-common-protos/google/api/annotations_pb`   | `@alis-build/google-api/google/api/annotations_pb`           |
| `@alis-build/google-common-protos/google/iam/v1/iam_policy_pb` | `@alis-build/google-iam-v1/google/iam/v1/iam_policy_pb`      |
| `@alis-build/common-es/alis/open/iam/v1/user_pb`               | `@alis-build/alis-open-iam-v1/alis/open/iam/v1/user_pb`      |
| `@alis-build/common-es/alis/open/agent/v1/agent_pb`            | `@alis-build/alis-open-agent-v1/alis/open/agent/v1/agent_pb` |

Split packages depend on each other (e.g. `@alis-build/alis-open-iam-v1` imports
`@alis-build/alis-open-validation-v1` and `@alis-build/google-iam-v1`). After re-defining
stale `@alis.build/*` packages, read their generated `.js` imports to see which
`@alis-build/*` packages the graph expects.

### Step 1 — Inventory

Under the frontend migration root:

```bash
pwd
rg -n '@internal\.[a-z0-9]+\.[a-z.]+/protobuf|_grpc_web_pb|google-protobuf|grpc-web|@alis-build/google-common-protos|@alis-build/common-es|@alis-build/common[^-]' \
  -g '*.ts' -g '*.tsx' -g '*.vue' -g 'package.json' -g '.npmrc' -g 'pnpm-lock.yaml' .
```

Collect distinct legacy packages and proto paths. Note any cross-product
`@internal.<otherproduct>.<domain>/protobuf` imports — each maps to its own `@alis.build/*`
package.

### Step 2 — Add runtime dependencies

In `package.json`:

```json
{
  "dependencies": {
    "@bufbuild/protobuf": "^2.12.0",
    "@connectrpc/connect": "^2.1.0",
    "@connectrpc/connect-web": "^2.1.0"
  }
}
```

Ensure `"type": "module"` when the bundler expects ESM (Vite, modern Node).

### Step 3 — Rewrite `.npmrc`

Remove per-product `@internal.*` `protobuf-javascript-internal` scope lines.

Registry routing in `.npmrc` is **scope-level only**. Both pnpm and npm **silently ignore
per-package registry lines** (`@alis.build/<pkg>:registry=...`) — the request falls through to
the default registry (npmjs) and fails with:

```
ERR_PNPM_FETCH_404  GET https://registry.npmjs.org/@alis.build%2F<package>: Not Found - 404
```

That npmjs URL in the error is the tell: the scope was not routed. Do not add per-package
lines — they verifiably do nothing. Beware the failure can stay hidden: packages already
pinned in the lockfile keep resolving from the store, so an ignored line only surfaces when a
new dependency forces a fresh resolution.

Point the scope at the app's own product registry:

```ini
@alis.build:registry=https://<region>-npm.pkg.dev/<project>/define-ecmascript
```

**Cross-product imports** — `@alis.build/*` packages owned by a *different* product — resolve
from the app's **own** product registry too: the platform distributes every package of a
product's *accessible products* (plus their `@alis.build/*` dependency closure) into that
product's `define-ecmascript` repo, both when access is granted and on every new define of the
source package. The single scope line above therefore covers cross-product packages as well —
no tarball URLs, no mirroring, no extra registry lines.

If a cross-product package still returns 404 from the own product registry:

1. Confirm the owning product is listed under the app's product **accessible products**
   (console → product → Manage Accessible Products, or `AddAccessibleProduct`). Adding it
   triggers the distribution automatically.
2. If access was already granted, the package may predate distribution — re-run Define for
   that package (its next version distributes automatically), or flag it on a support ticket.

Keep `@open.alis.services` (or other scopes) pointed at `openprotos-javascript` until those
packages publish protobuf-es builds — do not force-migrate open imports without a published
`@alis.build` or `@alis-build` replacement.

`@alis-build/*` common stubs resolve from **public npm** — no Artifact Registry registry line
needed for those packages.

Remove obsolete `@internal.*` scope lines once all legacy deps are dropped.

### Step 4 — Install per-neuron packages

From the migration root (or frontend app directory):

```bash
alis packages install --json
```

The CLI resolves the neuron from the current directory, installs required `@alis.build/*`
modules, and refreshes registry credentials. Cross-product dependencies resolve from the app's
own product registry (see Step 3) — never add per-package `.npmrc` lines, which npm and pnpm
ignore.

Fallback when the CLI is unavailable:

```bash
npx google-artifactregistry-auth --repo-config=/app/.npmrc
pnpm add @alis.build/<package-id-dashed>@latest
```

Repeat for each distinct per-neuron package in the inventory.

### Step 5 — Rewrite imports and call sites

Apply the npm mapping rule from [`SKILL.md`](../SKILL.md). Path swaps alone are not enough —
update every call site using **Part B** below (messages, clients, streaming, errors).

### Step 6 — Rebuild the client hub

Replace centralized `*PromiseClient` factories with Connect transport + `createClient`.
See **Client wiring** in Part B.

Port grpc-web interceptors (error tracking, LRO metadata headers) to Connect `interceptors`
on `createGrpcWebTransport`.

### Step 7 — Drop legacy dependencies

Remove from `package.json` once unused:

- `@internal.*.protobuf` (all products)
- `google-protobuf`
- `grpc-web`
- `@types/google-protobuf`
- `@alis-build/google-common-protos`
- `@alis-build/common`
- `@alis-build/common-es`
  (after migrating each import to the matching split `@alis-build/<proto-package-dashed>` package)

Run `pnpm install` to refresh the lockfile.

### Step 8 — Dockerfile

Ensure the Node build stage authenticates before install:

```dockerfile
RUN npx google-artifactregistry-auth --repo-config=/app/.npmrc
RUN pnpm install --frozen-lockfile
RUN pnpm run build
```

### Public stubs migration (JavaScript)

The public-stubs **invariant**, legacy generations, and naming rule live in
[`SKILL.md`](../SKILL.md). **Do not bulk-replace into `@alis-build/common-es`** — many types
now live in individual split packages, and linking both `common-es` and a split package for
the same proto causes registration panics.

**Procedure (order matters):**

1. **Re-define stale `@alis.build/*` packages first** — generated neuron packages embed
   whichever stub path was current when last defined. Run `alis define <package-id>` (no proto
   edits) for each stale package. Iterate until generated JS no longer imports
   `@alis-build/google-common-protos`, `@alis-build/common`, `@alis-build/common-es`, or old
   `@internal.*` paths.

2. **Upgrade before hand-editing.** Run `alis packages upgrade --all` and
   `alis packages install` before rewriting `package.json` by hand — the CLI may revert manual
   edits.

3. **Rewrite imports import-by-import** — for each legacy common-stub import, resolve the
   target split package:
   - Read the `@generated from file ... (package ...)` header in the generated `_pb` file, or
   - Derive from the proto file path: `@alis-build/<proto-package-dashed>/<same-subpath>_pb`

   ```bash
   rg -n '@alis-build/google-common-protos/|@alis-build/common-es/|@alis-build/common/' \
     -g '*.ts' -g '*.tsx' -g '*.vue' .
   ```

   Update each import to the split package. Add new `@alis-build/*` dependencies to
   `package.json` as needed (`pnpm add @alis-build/google-api @alis-build/alis-open-iam-v1 …`).

   **Shortcut:** after re-define, inspect imports inside installed `@alis.build/*` packages in
   `node_modules` — mirror the same `@alis-build/*` packages in the app.

4. **Drop monolith deps** — remove `@alis-build/google-common-protos`, `@alis-build/common`,
   and `@alis-build/common-es` once no imports reference them. Do not keep `common-es` alongside
   split packages that duplicate its contents.

5. **Bump stale `@alis.build/*` pins** to versions regenerated after the define run.

6. **Verify the whole graph:**

   ```bash
   pnpm why @alis-build/google-common-protos   # must fail / not found
   pnpm why @alis-build/common-es              # must fail / not found
   pnpm why google-protobuf                    # must fail / not found
   pnpm why grpc-web                           # must fail / not found
   pnpm run type-check
   pnpm run build
   ```

### Verify

1. Legacy scan returns no matches:

   ```bash
   rg -n '@internal\.[a-z0-9]+\.[a-z.]+/protobuf|_grpc_web_pb|google-protobuf|grpc-web|protobuf-javascript-internal|@alis-build/google-common-protos|@alis-build/common-es|@alis-build/common[^-]' \
     -g '*.ts' -g '*.tsx' -g '*.vue' -g 'package.json' -g '.npmrc' -g 'Dockerfile*' .
   ```

2. `pnpm run type-check` (or `vue-tsc --build`) passes — **mandatory**, not optional: enum
   member renaming (see Part B) is invisible to `vite build`.
3. `pnpm run build` passes.
4. `pnpm why google-protobuf`, `pnpm why grpc-web`, `pnpm why @alis-build/google-common-protos`,
   and `pnpm why @alis-build/common-es` report no dependency chain.
5. From the migration root, `alis packages upgrade --json` upgrades only scoped
   `@alis.build/...` packages without printing the legacy-package migration hint.

---

## Part B — Protobuf-ES API cookbook

Canonical external reference: [Protobuf-ES](https://protobufes.com/).

### Generated code shape

Header in each generated file:

```text
// @generated by protoc-gen-es v2.x with parameter "target=js+dts"
// @generated from file alis/org/product/v1/service.proto
```

Per message, three exports:

| Export      | Role                                                 |
| ----------- | ---------------------------------------------------- |
| `Foo`       | TypeScript type (`Message<"package.Foo"> & { ... }`) |
| `FooSchema` | `GenMessage<Foo>` descriptor for `create()`          |
| `file_*`    | `GenFile` with embedded descriptor                   |

Per service:

```typescript
export declare const FooService: GenService<{
  someMethod: {
    methodKind: "unary";
    input: typeof SomeRequestSchema;
    output: typeof SomeResponseSchema;
  };
  streamEvents: {
    methodKind: "server_streaming";
    input: typeof StreamRequestSchema;
    output: typeof StreamEventSchema;
  };
}>;
```

No separate `_grpc_web_pb` or `_connect.ts` files — service descriptors live in `_pb`.

### Dependency swap

| Remove                             | Add                                                              |
| ---------------------------------- | ---------------------------------------------------------------- |
| `google-protobuf`                  | `@bufbuild/protobuf`                                             |
| `grpc-web`                         | `@connectrpc/connect-web`                                        |
| —                                  | `@connectrpc/connect`                                            |
| `@types/google-protobuf`           | types from generated `.d.ts`                                     |
| `@alis-build/google-common-protos` | Individual split packages (see **Common stub package naming**)   |
| `@alis-build/common`               | Individual split packages (map by proto file path)               |
| `@alis-build/common-es`            | Individual split packages — do not replace with another monolith |

### Import rewrite

| Before                                               | After                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------ |
| `@alis-build/google-common-protos/google/api/...`    | `@alis-build/google-api/google/api/...`                            |
| `@alis-build/google-common-protos/google/iam/v1/...` | `@alis-build/google-iam-v1/google/iam/v1/...`                      |
| `@alis-build/common-es/alis/open/iam/v1/...`         | `@alis-build/alis-open-iam-v1/alis/open/iam/v1/...`                |
| `.../foo_grpc_web_pb` → `FooServicePromiseClient`    | `.../foo_pb` → `FooService`                                        |
| `.../foo_pb` → class `Foo`                           | `.../foo_pb` → `Foo`, `FooSchema`                                  |
| `google-protobuf/.../field_mask_pb`                  | field `{ paths: [...] }` in `create()` or `@bufbuild/protobuf/wkt` |
| `google-protobuf/.../timestamp_pb`                   | `@bufbuild/protobuf/wkt` `Timestamp`                               |

### Enum member renaming — silent migration hazard

protoc-gen-es **strips the redundant enum-name prefix** from member names. A mechanical path
swap leaves the old member names compiling in appearance but broken:

| Legacy (jspb)                       | Protobuf-ES                |
| ----------------------------------- | -------------------------- |
| `Release.Product.PRODUCT_IDEATE`    | `Release_Product.IDEATE`   |
| `Release.Category.CATEGORY_FEATURE` | `Release_Category.FEATURE` |
| `ReleaseView.RELEASE_VIEW_FULL`     | `ReleaseView.FULL`         |

Rules: nested enums flatten to `Parent_Enum` names, and any member prefix matching the enum
name (UPPER_SNAKE of `ReleaseView` → `RELEASE_VIEW_`) is removed.

**This is invisible to `vite build`** (which skips type checking) — it only surfaces under
`vue-tsc` / `tsc`. A migration validated with build-only commands can ship broken enum
references. Always run the type-check step in **Verify**; never sign off on `pnpm run build`
alone.

### Client wiring

**Before** — grpc-web `PromiseClient`:

```typescript
import * as Example from "@internal.os.alis.services/protobuf/alis/os/example/v1/service_grpc_web_pb";
import * as grpcWeb from "grpc-web";

type ClientOptions = {
  unaryInterceptors: grpcWeb.UnaryInterceptor<any, any>[];
  streamInterceptors: grpcWeb.StreamInterceptor<any, any>[];
};

function newClient<T>(
  Ctor: new (host: string, creds: null, options: ClientOptions) => T,
  ...unary: grpcWeb.UnaryInterceptor<any, any>[]
): T {
  return new Ctor("", null, {
    unaryInterceptors: [...unary, trackingUnary],
    streamInterceptors: [trackingStream],
  });
}

export const exampleClient = newClient(Example.ExampleServicePromiseClient);
```

**After** — Connect + gRPC-Web transport:

```typescript
import { ExampleService } from "@alis.build/alis-os-example-v1/alis/os/example/v1/service_pb";
import { createClient } from "@connectrpc/connect";
import { createGrpcWebTransport } from "@connectrpc/connect-web";

const transport = createGrpcWebTransport({
  baseUrl: "/",
  interceptors: [trackingInterceptor],
});

export const exampleClient = createClient(ExampleService, transport);
```

- Empty / `'/'` `baseUrl` → same-origin gRPC-web proxy (Go BFF serves SPA + proxies RPCs).
- RPC methods are **camelCase** async functions: `await client.retrieveItems(req)`.

### Unary RPC calls

**Before:**

```typescript
const req = new ListItemsRequest();
req.setPageSize(50);
req.setPageToken(token);
const res = await client.listItems(req);
const items = res.getItemsList();
```

**After:**

```typescript
import { create } from "@bufbuild/protobuf";
import { ListItemsRequestSchema } from "@alis.build/alis-os-example-v1/alis/os/example/v1/service_pb";

const res = await client.listItems(
  create(ListItemsRequestSchema, {
    pageSize: 50,
    pageToken: token,
  }),
);
const items = res.items;
```

| Pattern               | grpc-web / jspb                           | Protobuf-ES + Connect                            |
| --------------------- | ----------------------------------------- | ------------------------------------------------ |
| Build request         | `new Req(); req.setX(y)`                  | `create(ReqSchema, { x: y })`                    |
| Response fields       | `res.getItemsList()`, `res.getOverview()` | `res.items`, `res.overview`                      |
| Optional sub-messages | `msg.hasField()`, `msg.getField()`        | `msg.field` / optional chaining                  |
| Repeated              | `.setItemsList([...])`, `.addItems(x)`    | `items: [...]` in `create()` init                |
| Maps                  | `.getProjectsMap()`, `.setProjectsMap(m)` | `projects: { key: value }` object literal        |
| UI display            | `.toObject()`                             | responses are plain typed objects — use directly |

### Server streaming

**Before:**

```typescript
const stream = client.streamEvents(req);
stream.on("data", (msg) => {
  /* handle */
});
stream.on("end", () => {
  loading.value = false;
});
stream.on("error", (err) => {
  stream.cancel();
});
```

**After:**

```typescript
import { create } from "@bufbuild/protobuf";
import { StreamEventsRequestSchema } from "@alis.build/alis-os-example-v1/alis/os/example/v1/service_pb";

const abort = new AbortController();

try {
  for await (const msg of client.streamEvents(
    create(StreamEventsRequestSchema, { session: sessionName }),
    { signal: abort.signal },
  )) {
    // msg is a plain typed object
  }
} catch (err) {
  // handle error
} finally {
  loading.value = false;
}

// To cancel:
abort.abort();
```

### Interceptors

**grpc-web:** `UnaryInterceptor` / `StreamInterceptor` classes passed to client constructor
options.

**Connect:** `interceptors: [...]` on `createGrpcWebTransport`. Unified `Interceptor` API for
unary and streaming.

LRO metadata example (Connect):

```typescript
import type { Interceptor } from "@connectrpc/connect";

const lroInterceptor: Interceptor = (next) => async (req) => {
  req.header.set("x-alis-lro-id", packageId);
  return next(req);
};
```

**Note:** for server-streaming calls, interceptors may receive `req.message` as an
`AsyncIterable` — iterate once if logging the outgoing request body.

### Well-known types

| Concern      | grpc-web / jspb                                  | Protobuf-ES                                            |
| ------------ | ------------------------------------------------ | ------------------------------------------------------ |
| FieldMask    | `new FieldMask().setPathsList(['a','b'])`        | `{ paths: ['a', 'b'] }` in `create()`                  |
| Timestamp    | `ts.fromDate(d)` / `ts.toDate()`                 | `{ seconds: bigint, nanos: number }`; convert manually |
| Struct       | `Struct.fromJavaScript(obj)`                     | `toJson` / `fromJson` or `create(StructSchema, ...)`   |
| Any / binary | `.deserializeBinary(bytes)` / `.getValue_asU8()` | `fromBinary(Schema, bytes)` / `toBinary(Schema, msg)`  |
| Enums        | `Foo.Bar.BAZ` (numeric)                          | import `Foo_Bar`; use `Foo_Bar[val]` for labels        |

Timestamp conversion example:

```typescript
import type { Timestamp } from "@bufbuild/protobuf/wkt";

function formatTimestamp(ts: Timestamp | undefined): string {
  if (!ts) return "";
  const ms = Number(ts.seconds) * 1000 + Math.floor(ts.nanos / 1_000_000);
  return new Date(ms).toLocaleString();
}
```

### oneof

**Before:**

```typescript
if (event.getPayloadCase() === Event.PayloadCase.USER_EVENT) {
  return event.getUserEvent();
}
req.setPublic(new SetAccessRequest.Public());
```

**After:**

```typescript
// Reading
if (event.payload.case === "userEvent") {
  return event.payload.value;
}

// Writing
create(SetAccessRequestSchema, {
  criteria: { case: "public", value: {} },
});
// or
create(SetAccessRequestSchema, {
  criteria: {
    case: "domains",
    value: create(DomainsSchema, { domains: ["example.com"] }),
  },
});
```

Narrow with `switch (msg.case)` on discriminated unions.

### Error handling

**Before:**

```typescript
import { StatusCode } from "grpc-web";
if ((err as { code?: number }).code === StatusCode.NOT_FOUND) {
  /* ... */
}
```

**After:**

```typescript
import { ConnectError, Code } from "@connectrpc/connect";
if (err instanceof ConnectError && err.code === Code.NotFound) {
  /* ... */
}
```

### IAM / policy-manager components

Components that pass a grpc-web client instance as `policy-manager` (IAM helper props) must
receive the Connect client instead — same service, different type surface.

### Generated package expectations

- One `_pb.js` + `_pb.d.ts` per proto file (no `_grpc_web_pb`), plus root `index.js` /
  `index.d.ts` entrypoints re-exporting every module.
- Cross-package imports in generated JS are **bare package specifiers** (`@alis-build/*` for
  common stubs, `@alis.build/*` for other neurons), each declared in `dependencies`.
- The runtime libraries (`@bufbuild/protobuf`, `@connectrpc/connect`,
  `@connectrpc/connect-web`) are declared as **`peerDependencies`**, so the app resolves a
  single shared copy of the protobuf runtime. pnpm ≥ 8 and npm ≥ 7 auto-install peers; keep
  the app-level versions from Step 2 compatible (`^2.x`).

**Stale published versions:** packages generated before the import-validation fix
(≈ 2026-08) can ship broken *relative* cross-package imports that only fail when the bundler
reaches the module, e.g.:

```
Could not resolve "../../type/expr_pb" from node_modules/.../@alis-build/google-iam-v1/...
```

The fix is to **upgrade the package to its latest version** (e.g. `@alis-build/google-iam-v1`
≥ 1.2.0) — republished versions have bare specifiers and correct dependencies. Do not
`pnpm patch` `node_modules`; if no fixed version exists, request a re-define of that package.

### Migration order for large apps

1. Migrate the **client hub** + one low-traffic service end-to-end.
2. Extract shared helpers (FieldMask builder, error handler, streaming composable).
3. Batch remaining imports by `@alis.build` npm package (product) and `@alis-build` split package (common).
4. Drop monolith deps (`@internal.*.protobuf`, `@alis-build/google-common-protos`,
   `@alis-build/common`, `@alis-build/common-es`) only when the inventory scan is clean.

### Prerequisite

If `pnpm add @alis.build/<package-id-dashed>@latest` fails because the package is unknown,
the neuron has not been defined under protos.v2 yet — stop and tell the user; do not invent a
module path.
