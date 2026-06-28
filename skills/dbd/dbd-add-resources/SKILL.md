---
name: dbd-add-resources
description: >
  Use this skill when the user wants to scaffold a complete, AIP-compliant "Resources" backend
  into a neuron from a resource tree — for example "add a resources block", "scaffold CRUD for
  Books and Authors", "generate the resources server for these resources", or "implement AIP
  resources with Spanner". Go + Spanner only. It writes the `.proto` contract into the define tree
  and `server.go`, per-service service files, `go.mod`, `Dockerfile`,
  `internal/{database,db,namers,regex,roles}`, and `infra/*.tf` into the build tree, deriving every
  value from the resource tree, and interviews the user to build the tree when one is not supplied.
  Not for: non-Go languages or non-Spanner databases, or editing the business logic of an
  already-scaffolded service. Pairs with review-define (review the generated protos before Define)
  and dbd-add-grpc-go-server (generic, non-AIP Go server).
metadata:
  alis.context.version: "1"
  # Context field paths this skill needs from the injected runtime context.
  alis.context.requires: >-
    focus_package_id workstations session.working_directory
---

# Add a Resources backend

Scaffold a complete, AIP-compliant **Resources** backend for a neuron from a resource tree. The
output is **Go + Spanner only**. It writes the `.proto` API contract into the **Define** tree and
the full implementation (`server.go`, per-service service files, `go.mod`, `Dockerfile`,
`internal/{database,db,namers,regex,roles}`) plus `infra/*.tf` into the **Build** tree.

You produce each file by rendering the bundled Go `text/template` files under
`references/templates/` against values you derive from the resource tree. The generated boilerplate
is deterministic — a generated resource proto is just `name`/`etag`/timestamps with a
`// TODO: Add more fields` — so faithful rendering, not invention, is the goal.

## When to use

- The user wants to scaffold AIP resource CRUD (Create/Get/Update/List/Delete/Undelete + Batch +
  Stream, optional revisions, IAM) into a neuron from a set of resources.
- The user has a structured resource definition (or a description of the resources) and wants the
  Proto/Build/Infra files written into their define + build repos.

## When not to use

| Need | Use instead |
| --- | --- |
| A generic (non-AIP) Go server from existing protos | **dbd-add-grpc-go-server** |
| Author / review the proto contract only | **dbd-add-protos** / **review-define** |
| Full Define→Build→Deploy onboarding | **getting-started** |
| Non-Go language or non-Spanner database | (unsupported — stop) |

## How this skill works

The generation knowledge lives in `references/` (progressive disclosure — read them as you go):

- **`references/templates/`** — the **Go `text/template` files** for every generated file, bundled
  as `.example`. **Interpret the `{{ }}` and render them** — these are templates, *not*
  `REPLACE_WITH_*` copy-paste files.
- **`references/derivation-rules.md`** — how to compute every template variable from the resource
  tree (naming, hierarchy/ancestors, service mapping, import path). **The load-bearing doc.**
- **`references/file-manifest.md`** — every output file, its path, and which template renders it.
- **`references/worked-example.md`** — a real config fully resolved + the four hardest files
  rendered, so you can calibrate before generating.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below to decide which fields to include; the block carries **only** those fields.
**When the block is present, its values are authoritative**: use the exact paths and the package
verbatim, and do **not** scan folders or ask the user to confirm a value that was already provided.

**Confirm what was provided.** Open by echoing the resolved values back in a table (✅ for values
that came from the block) so the user sees what does *not* need deriving:

| Value | Source | Resolved as |
| --- | --- | --- |
| Package | ✅ runtime context | `<focus_package_id>` |
| Define tree (proto dest) | ✅ runtime context | `<workstations.define_repos value>` |
| Build dir (impl + infra dest) | ✅ runtime context | `<session.working_directory>` |

List only fields actually present; for anything absent, use the "If absent" rule below and mark its
real source (e.g. "derived by convention" / "asked user") instead of ✅. **Never invent a value.**

### Context fields (`alis.context.requires`)

| Value | Context field | If absent, how to obtain it |
| --- | --- | --- |
| **Package** | `focus_package_id` | The proto `package` + `go.mod` module + seed for neuron/import derivation (e.g. `marvel.sm.resources.v1`). Strip any `packages/` prefix. If absent, ask the user or read a sibling neuron's `go.mod`. |
| **Define tree** (proto destination) | `workstations` | The focused workstation's `define_repos` entry — `<root>/<landing-zone>/define/<org>/<product>/<service>/<version>`. The `.proto` files are written here. |
| **Build dir** (impl + `infra/` destination) | `session.working_directory` | Where `server.go`, `internal/*`, and `infra/*.tf` are written (≈ the `workstations.build_repos` entry). Default to cwd; confirm if it does not look like a `<neuron>/<version>` build folder. |

---

## Workflow

### 1. Resolve targets

Resolve **Package** (`focus_package_id`), the **Define tree** (`workstations.define_repos`), and the
**Build dir** (`session.working_directory`); infra goes to `<build>/infra/`. Confirm them in the ✅
table above. `build_folder` defaults to `"."`; confirm with the user if it is a non-root subfolder
(it changes Cloud Run / image naming — see derivation §10). Derive `NeuronId`, `NeuronAlias`,
`NeuronRelativeFilePath`, and the proto package from the package string per derivation §3.

### 2. Discover registry conventions from a sibling neuron (do not hardcode)

A few values are product-specific and not derivable from the package string. Recover them from an
**existing neuron in the same build repo** (as `dbd-add-grpc-go-server` does):

- **Import path + `PackagesDomain`** — from a sibling's `go.mod`/imports
  (`internal.<productId>.<PackagesDomain>/protobuf/...`); reuse `<productId>.<PackagesDomain>` with
  this neuron's `NeuronRelativeFilePath`.
- **`Dockerfile` `GOPROXY` / `GONOSUMDB` / `add-locations` region** — copy verbatim from the
  sibling's `Dockerfile`.

Fallbacks: MCP `ViewProduct` / `GetLandingZone`; else the proto `option go_package`; else ask.
**Never invent `PackagesDomain`.** (`cloudrun.tf` / `spanner.tf` need no sibling values — they use
`var.ALIS_*` + `NeuronId`.)

### 3. Obtain or interview the resource tree (BlockConfig)

If the user supplied a `BlockConfig` (or a config the agent can read), use it. Otherwise **interview**
to build the tree — for each resource ask:

- `singular_name` / `plural_name` (e.g. `Book` / `Books`)
- `resource_id` (snake, e.g. `book`) and `collection_id` (lower camel plural, e.g. `books`)
- `resource_id_regex` (default `[a-z0-9-]{2,50}`)
- `has_policies` (IAM), `user_provided_resource_id` (client sets the id vs server UUID),
  `has_revisions` (AIP-162 history), `enable_allow_missing_on_update` (upsert)
- parent/child nesting (which resources are children of which)

Validate: `language` must be Go and `database` must be Spanner — **refuse anything else**. Validate
`resource_id` / `collection_id` shapes. **Echo the resolved tree back to the user and get
confirmation before generating.**

### 4. Compute the derived variables per resource

Using **`references/derivation-rules.md`**, compute for every resource (and each synthetic revision
resource): the naming scalars (§5), the service map (§4), the namer hierarchy
(`Ancestors`/`MinParts`/`AncestorIdIndex`/`RootResourceId`, §6), `ParentsCollectionIds` (§7), and
the regex/roles lists (§8–9). `references/worked-example.md` shows the resolved shape.

### 5. Render & write the proto files (→ Define tree)

For **each root resource**, render `protos/service.proto.tmpl.example` and write
`<root resource_id>.proto` into the define tree (the proto file is named with the **singular root
id**, e.g. `author.proto`). Then offer the user a `review-define` pass (or at least `buf lint`).

### 6. Render & write the build files (→ Build dir)

Per **`references/file-manifest.md`**, write into `session.working_directory`: `go.mod` (the three
hardcoded lines), `server.go`, `Dockerfile` (sibling values from step 2), per-service
`<lower(plural)>.go` + `<lower(plural)>_test.go`, `iam.go`, `internal/database/*` (copy verbatim —
no variables), `internal/db/{db,spanner}.go` and one `internal/db/<lower(singular)>.go` per resource
(+ `_revision.go` when `has_revisions`), `internal/namers/<resource_id>_namer.go` per resource
(+ the `_revision_namer.go`), `internal/regex/regex.go`, and `internal/roles/roles.go`.

### 7. Render & write the infra files (→ `<build>/infra/`)

`main.tf` and `variables.tf` are copied verbatim (no variables). Render `cloudrun.tf` (Cloud Run
naming, derivation §10) and `spanner.tf` (per-resource tables + foreign keys + revision tables,
using `ParentsCollectionIds`).

### 8. Format, verify, hand off

Format and verify (see Verification), then tell the user the next DBD steps: review the protos
(`review-define`), commit, run **Define**, then **Build** and **Deploy**.
**This skill only scaffolds — it does not run Define, Build, or Deploy.**

---

## Placeholders reference

| Placeholder | Meaning | Worked-example value |
| --- | --- | --- |
| `<focus_package_id>` | The package (proto package + go.mod module) | `marvel.sm.resources.v1` |
| `<NeuronId>` | Neuron id (neuron parts joined by `-`) | `resources-v1` |
| `<import-path>` | Published protobuf import path (alias `pb`) | `internal.sm.marvel.build/protobuf/marvel/sm/resources/v1` |
| `<ResourceName>` / `<ResourceNamePlural>` | Singular / plural (PascalCase) | `Book` / `Books` |
| `<ResourceId>` / `<CollectionId>` | snake id / lower-camel plural | `book` / `books` |
| `<Service>` | `<root PluralName>Service` | `AuthorsService` |
| `<RootResourceId>` | namer struct prefix = `SnakeToCamel(this resource's id)` | `book` → `bookNamer` |
| `<MinParts>` / `<AncestorIdIndex>` | `2*(depth+1)` / ancestor id index (`= MinParts−1`) | Chapter: 6 / Book-ancestor 3 |
| `<ParentsCollectionIds>` | ordered ancestor collection ids (spanner) | Chapter: `["authors","books"]` |

## Verification

Run from `session.working_directory`:

```sh
gofmt -w .            # keep generated Go canonically formatted
go mod tidy
go build ./...        # the compiler is the real check on your template rendering
```

Resolve compile errors against the sibling neuron (usually the import path or a dependency version).
For protos, if a `buf.yaml` exists at the define-repo root, run `buf lint` and `buf build`; otherwise
rely on Define. Optionally exercise the service via the neuron `.playground/main_test.go` after Deploy.

### Checklist

- [ ] Package taken from `focus_package_id`; define/build/infra paths confirmed in the ✅ table; nothing re-derived that the runtime context already provided.
- [ ] Import path + `Dockerfile` `GOPROXY`/`GONOSUMDB` copied from a sibling neuron (or MCP) — `PackagesDomain` not invented.
- [ ] `BlockConfig` supplied or built by interview and **echoed back** before generating; Go + Spanner enforced (refuse otherwise).
- [ ] One `<root resource_id>.proto` per **root**; one `<lower-plural>.go` + `_test.go` per service; descendants folded into the root's service.
- [ ] Correct per-resource filenames: `internal/db/<lower-singular>.go` (+ `_revision.go`), `internal/namers/<resource_id>_namer.go` (+ `_revision_namer.go`); `internal/database/*`, `infra/main.tf`, `infra/variables.tf` copied verbatim.
- [ ] Derived values correct: `MinParts = 2*(depth+1)`, ordered `Ancestors`, `AncestorIdIndex`, `ParentsCollectionIds`, and proto field numbers (`name=1`, `etag=97`, `create_time=98`, `update_time=99`, `delete_time=100`).
- [ ] `gofmt -w .` applied; `go build ./...` passes; protos `buf lint` cleanly (if buf present).
- [ ] No Define/Build/Deploy run by the skill; user handed off to `review-define` and the DBD loop.
