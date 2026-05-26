# Bootstrap: proto-backed tools package

One-time setup before adding individual tools. Complete every step unless your project already has an equivalent.

Read **`references/workspace.md`**, **`../../../references/alis-workspace.md`**, and **`../../../references/define-stubs.md`** first (and **`.alis/agents/AGENTS.md`** when present).

## Prerequisites

- Agent module with `go.mod` and an ADK agent entrypoint (`main.go` or equivalent).
- User runs **define** via Alis Build’s DBD toolchain to generate stubs. See **`../../../references/define-stubs.md`**.
- JSON Schema proto options: **`references/json-schema.md`**.
- LRO RPCs may share `ToolsService` in `tools.proto` (default); use the **add-lro** skill for those. A separate proto file is optional if your team splits contracts.

## Steps

| # | Action | Template |
|---|--------|----------|
| 1 | Add `tools.proto` with `import "alis/open/options/v1/options.proto"` and file option `json_schema.generate = true`. Start from the example. | `references/templates/tools.proto.example` |
| 2 | Ask user to **run a define on the neuron** (bootstrap) or **on the package** **`<package from tools.proto>`**. Wait. Do not touch `go.mod` yet. | `../../../references/define-stubs.md` |
| 3 | Ask user to **install required dependencies**. Wait. | `../../../references/define-stubs.md` |
| 4 | Create `internal/tools/tools.go` (ADK bridge: `NewTool`, `NewToolForEmpty`, `NewToolSet`). Fix the `auth` import path. | `references/templates/tools.go.example` |
| 5 | Create `internal/tools/service.go` with `myToolsService`, empty or example `MyTools()`. Fix the `pb` import. | `references/templates/service.go.example` |
| 6 | If the project has no auth helper: copy `internal/auth/auth.go` from the auth template and wire `ForwardAuth`. | `references/templates/auth.go.example` |
| 7 | Wire the agent entrypoint `Tools` slice to include `tools.MyTools()` alongside existing tools (e.g. `loadmemorytool`). | `references/templates/agent-wiring.go.example` |
| 8 | (Optional) When a gRPC server exists, register `ToolsService` via `RegisterGRPC`. | `references/templates/grpc.go.example` |

## Replace placeholders

Search and replace in copied files:

| Placeholder | Replace with |
|-------------|--------------|
| `REPLACE_WITH_YOUR_MODULE` | Your agent Go module path from `go.mod` |
| `REPLACE_WITH_YOUR_PROTOBUF_GO_IMPORT` | Generated package for your `tools.proto` |
| `REPLACE_WITH_YOUR_PROTO_PACKAGE` | Proto `package` identifier |

## Verify bootstrap

```bash
go build ./...
```

Run the agent locally (ADK web launcher). Confirm:

- Build succeeds with no missing `JsonSchema` symbols.
- `MyTools()` can return an empty slice initially — that is valid for bootstrap-only work.
- No duplicate tool names in the `Tools` slice.

## Next

Add synchronous tools using `references/sync-tool-checklist.md`.
