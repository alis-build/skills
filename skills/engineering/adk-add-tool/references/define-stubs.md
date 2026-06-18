# Stub generation (user runs code generation)

Proto-backed ADK tools require generated Go stubs before you can write handler code. The generation step varies by project — it may be `protoc`, `buf generate`, a custom CI/CD pipeline, or a platform-specific toolchain.

**You cannot run code generation yourself** unless the user explicitly asks. Wait for the user to confirm it's done before proceeding.

## Mandatory order after proto changes

Do these steps **in order**. Do not skip ahead.

| Step | Who | Action |
|------|-----|--------|
| 1 | Agent | Edit proto in this agent's package (see **`alis-workspace.md`**) |
| 2 | Agent | Ask user to run code generation (see below) |
| 3 | Agent | **Stop** — no Go files, no `go.mod` / `go get` / `go mod edit` yet |
| 4 | User | Runs code generation; confirms done |
| 5 | Agent | Ask user to **install required dependencies** (see below) |
| 6 | User | Installs/upgrades packages; confirms done |
| 7 | Agent | Implement handlers, wiring, infra as needed |

### Do not run before step 6

- `go mod edit -require …`
- `go get` on generated protobuf modules
- Any Go code importing `pb.*`, `JsonSchema()`, or `*_FullMethodDescription`

Generated stubs **do not exist** until code generation and dependency install complete.

## What to ask the user — code generation

Ask the user to generate stubs from the proto changes. Adapt the phrasing to the project's toolchain:

**Generic:**

> Please **run code generation** for the proto package `<package from tools.proto>`.

**If using `buf`:**

> Please run `buf generate` for the updated protos.

### Alis Build projects

Use one of these (lowercase **define**):

**Package** (usual when only `tools.proto` changed):

> Please **run a define on the package** `<package from tools.proto>`.

**Neuron** (bootstrap or many protos changed):

> Please **run a define on the neuron** `<neuron name>`.

## What to ask the user — install dependencies

**Immediately after** the user confirms code generation finished, ask:

> Please **install the required dependencies** (upgrade Go and other packages produced by code generation).

Wait for confirmation before writing Go that imports generated stubs.

## After code generation + install

Generated code should include:

- `ToolsService` server types and request/response messages (when using tools.proto)
- `JsonSchema()` on tool messages when `json_schema.generate` is enabled — see **`json-schema.md`**
- `ToolsService_<Rpc>_FullMethodDescription` from RPC comments

## If code generation has not run

Do not invent generated names. Limit work to proto files, or ask the user to run code generation.

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| `JsonSchema undefined` | Code generation not run after proto change |
| Unknown `*_FullMethodDescription` | Code generation not run after RPC added |
| `go mod` / import errors right after proto | Go work started before code generation + install |
| Wrong types | Code generation targeted wrong package (see **`alis-workspace.md`**) |
