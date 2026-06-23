---
name: dbd-add-protos
description: >
  Use this skill when the user wants to author new protocol buffer definitions for a service in
  the Define repo — for example "add protos", "define a new service", "scaffold a .proto", or
  "create the API contract for X". This is the Define stage only: it asks what the service is
  about (to name it and write clear comments) and what initial custom methods are needed, then
  generates an AIP-compliant `.proto` with a service, RPCs, and messages. It does not run Define,
  and does not write any Go/build code. Pairs with review-define (review) and
  dbd-add-grpc-go-server (build).
metadata:
  alis.context.version: "1"
  # Context field paths this skill needs from the injected runtime context.
  alis.context.requires: >-
    focus_package_id workstations.define_repos
---

# Add protos

Author a new protocol buffer **contract** for a service in the **Define** repo. This is the
**Define** stage of Define-Build-Deploy (DBD): you produce reviewable `.proto` files that, once
committed and locked by Define, generate the consumable packages the Build stage implements
against. This skill **only touches the define repo** — it does not run Define and writes no Go or
infra code.

The contract is interview-driven: the quality of the names and comments depends on understanding
what the service is for, so **ask the user** rather than inventing intent.

## When to use

- Starting a new service/neuron and need the first `.proto` (service + messages) in the define repo.
- Adding a new `.proto` file (or a new service) to an existing neuron's define tree.

## When not to use

| Need                                                          | Use instead                |
| ------------------------------------------------------------- | -------------------------- |
| Review / lint existing protos for AIP-compliance & comments    | **review-define**          |
| Implement the Go gRPC server against an existing contract      | **dbd-add-grpc-go-server** |
| Onboarding / running the full Define→Build→Deploy loop         | **getting-started**        |

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads
`alis.context.requires` below to decide which context fields to include; the block carries
**only** those fields.
**When the block is present, its values are authoritative**: use the exact paths verbatim, and do
**not** scan folders or ask the user to confirm a value that was already provided.

### Context fields used by this skill

| Value                  | Context field               | If absent, how to obtain it                                                                                                          |
| ---------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Proto package**      | `focus_package_id`          | The proto package for the focused package, e.g. `aibake.ge.hello.v1`. This is the authoritative value for the `package` declaration — do not derive it from the path. If absent, derive from the define tree (segments after `define/`) or ask the user. |
| **Neuron define tree** | `workstations.define_repos` | Default root `~/alis.build`, then `<root>/<landing-zone>/define/<org>/<product>/<service>/<version>`; confirm the folder with the user. |

Use `focus_package_id` for the proto **`package`** declaration. The **file path** still comes from
the define tree: `focus_package_id`'s dotted segments map to folders under `define/` (e.g.
`aibake.ge.hello.v1` → `.../define/aibake/ge/hello/v1/<file>.proto`). Never invent either — use the
context values or ask.

---

## Workflow

### 1. Interview the user (this drives names and comments)

Before writing anything, ask — batched into one message — the questions whose answers you cannot
derive. Keep it short; offer sensible defaults.

1. **What is this service about?** Its purpose and the domain it serves. This sets the **service
   name** (`<Noun>Service`, e.g. `HelloService`, `LedgerService`) and the service-level comment.
2. **What does it manage / what are the key nouns?** Resources or core data objects, if any. This
   shapes the message types and whether standard methods (Get/List/Create/Update/Delete) apply.
3. **Any initial custom methods required?** For each: a short name (verb + noun, e.g.
   `CalculateRandomNumber`), what it does, and roughly what goes in and comes out. These become the
   RPCs and their request/response messages.
4. **Service/area name and version** if not already determined by the define tree (defaults: derive
   the area from the purpose, version `v1`).

If the user is vague on a method's behaviour, ask one focused follow-up rather than guessing — the
comments are the SDK documentation downstream.

### 2. Resolve the target file

Determine the package and path:

- Package = `focus_package_id` verbatim (e.g. `aibake.ge.<area>.v1`) — this is the value for the
  `package` declaration.
- File path = `<define-root>/<focus_package_id segments as folders>/<file>.proto`, e.g.
  `.../define/aibake/ge/<area>/v1/<area>.proto`, anchored on `workstations.define_repos`. Name the
  file after the area/resource (`hello.proto`, `ledger.proto`). Confirm the folder/filename with the
  user if ambiguous.

Check the define repo's `buf.yaml` (lint config) at the repo root so generated protos respect the
project's lint rules.

### 3. Generate the `.proto`

Write a single AIP-compliant proto file (https://google.aip.dev/general). Use this scaffold,
filling in the interview answers:

```protobuf
syntax = "proto3";

package <focus_package_id>;

import "alis/open/options/v1/options.proto";
// Add imports only as needed, e.g.:
// import "google/protobuf/timestamp.proto";
// import "google/api/field_behavior.proto";
// import "google/api/resource.proto";

option (alis.open.options.v1.file).json_schema.generate = true;

// <ServiceName> <one-line purpose from the interview>.
//
// <A short paragraph: what the service is responsible for and when callers use it.>
service <ServiceName> {
  // <Verb-first, third-person comment: what this method does, its success/error
  // behaviour, idempotency, and any units/formats that matter.>
  rpc <Rpc>(<Rpc>Request) returns (<Rpc>Response) {}

  // ...one rpc per requested custom method...
}

// Request message for the <Rpc> method.
message <Rpc>Request {
  // <Comment for each field: meaning, units, valid ranges, whether required.>
  <type> <field> = 1;
}

// Response message for the <Rpc> method.
message <Rpc>Response {
  // <Comment for each field.>
  <type> <field> = 1;
}
```

Conventions to honour (cite AIPs when explaining choices to the user):

- **Comments on everything** — every service, method, message, and field carries a clear,
  third-person comment ([AIP-192](https://google.aip.dev/192)). Comments are American English,
  CommonMark, with backticks around field/method names and literals.
- **Naming** — `package` is `focus_package_id` and ends in a version (`…v1`,
  [AIP-215](https://google.aip.dev/215)); service is `<Noun>Service`; request message is
  `<Rpc>Request`.
- **Custom methods** — verb+noun, justified when a standard method would not fit
  ([AIP-136](https://google.aip.dev/136)).
- **Resources & standard methods** — if the user is managing a resource, annotate it with
  `google.api.resource`, give it a `string name` field, and prefer the standard
  Get/List/Create/Update/Delete shapes ([AIP-121](https://google.aip.dev/121)–[135](https://google.aip.dev/135));
  `List` paginates with `page_size`/`page_token`/`next_page_token`
  ([AIP-158](https://google.aip.dev/158)).
- **Enums** — first value `*_UNSPECIFIED = 0`, values `UPPER_SNAKE_CASE`
  ([AIP-126](https://google.aip.dev/126)).
- **Field behaviour** — express required/output-only/immutable via `google.api.field_behavior`
  ([AIP-203](https://google.aip.dev/203)).

Add only the imports the file actually uses.

### 4. Hand off

After writing the file:

1. Tell the user which file was created and summarise the service and methods.
2. Suggest running **review-define** to lint the contract and tighten comments before it is locked.
3. Remind the user the next DBD step is to **commit and run Define** against the pushed commit,
   which generates the consumable packages. Once Define is done, **dbd-add-grpc-go-server** scaffolds
   the Go server against the generated package.

**This skill only authors the proto contract — it does not run Define, Build, or Deploy.**

---

## Placeholders reference

| Placeholder          | Meaning                                                | Example                 |
| -------------------- | ------------------------------------------------------ | ----------------------- |
| `<focus_package_id>` | Proto package from the `focus_package_id` context field | `aibake.ge.hello.v1`    |
| `<ServiceName>`      | `<Noun>Service`, from the service purpose               | `HelloService`          |
| `<area>`             | Service/folder/file area name                          | `hello`                 |
| `<Rpc>`              | Custom method name (verb + noun)                       | `CalculateRandomNumber` |

## Verification

- [ ] The `package` was taken from `focus_package_id` (not guessed), and the file path was anchored
      on `workstations.define_repos` and confirmed with the user.
- [ ] The user was asked what the service is about and what initial custom methods are needed;
      names and comments reflect those answers (nothing about behaviour was invented).
- [ ] The generated `.proto` has a versioned package, a `<Noun>Service`, request/response messages
      per RPC, and a comment on every service/method/message/field (AIP-192).
- [ ] Only imports that the file actually uses were added; the file respects the repo `buf.yaml`.
- [ ] No Go/build/infra files were written, and Define/Build/Deploy were not run.
