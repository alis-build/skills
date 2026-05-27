# Bootstrap: LRO on a proto-backed agent

One-time setup after **add-tool** bootstrap (or equivalent: `internal/tools`, `tools.proto` with `json_schema.generate`). Adds infra, LRO client, conversation resume, and launcher wiring — no LRO tools registered yet.

Read **`workspace.md`**, **`alis-workspace.md`**, and **`define-stubs.md`** (same directory) first.

## Prerequisites

- **add-tool** bootstrap complete, or equivalent tools package.
- User runs code generation — see **`define-stubs.md`**.
- Agent does **not** run define or `terraform apply` unless the user asks.

## Steps

| # | Action | Template / doc |
|---|--------|----------------|
| 0 | Confirm `internal/tools`, `tools.proto`, entrypoint wired with `tools.MyTools()` | `../add-tool/references/bootstrap.md` |
| 1 | Provision LRO infra + reasoning-engine `deployment_spec` LRO envs | `references/infra-lro.md`, `templates/infra/` |
| 2 | Add `import "google/longrunning/operations.proto"` to `tools.proto` if absent | — |
| 3 | Ask user: **run a define on the package** `<package from tools.proto>` or **on the neuron** | `define-stubs.md` |
| 4 | **Stop** — no `go.mod`, no Go yet | define-stubs |
| 5 | Ask user: **install required dependencies** (see below) | define-stubs |
| 6 | Merge `NewLROTool` + `googleLongrunningOperation` into `internal/tools/tools.go` | `templates/tools.go.lro-snippet.example` |
| 7 | Add `internal/tools/grpc.go` with `InitLRO` / `RegisterGRPC` | `templates/grpc.go.example` |
| 8 | Copy `internal/lroresume/` package | `templates/lroresume/` |
| 9 | Set `DefaultAppName` and `DefaultNeuron` in `lroresume/run_api.go` | workspace.md |
| 10 | Wire entrypoint: `lroServiceID`, `MustInitLRO`, `weblro.NewLauncher` | `templates/main-lro-wiring.go.example` |
| 11 | `go build ./...` | — |

## Dependencies (ask user to install after define)

- `go.alis.build/lro/v2`
- `go.alis.build/adk/launchers` (weblro)
- `cloud.google.com/go/longrunning`
- `github.com/google/uuid` (if handlers generate operation names)
- Generated protobuf module for `<package from tools.proto>`

## Replace placeholders

| Placeholder | Replace with |
|-------------|--------------|
| `REPLACE_WITH_YOUR_MODULE` | Agent Go module from `go.mod` |
| `REPLACE_WITH_YOUR_PROTOBUF_GO_IMPORT` | Generated Go import for `tools.proto` |
| `REPLACE_WITH_LRO_SERVICE_ID` | Infra neuron id (`local.neuron`) |
| `REPLACE_WITH_AGENT_APP_NAME` | `llmagent.Config.Name` |

## Verify bootstrap

- [ ] Infra module added; neuron id documented for user deploy
- [ ] `google_vertex_ai_reasoning_engine` `deployment_spec` has LRO env vars (`infra-lro.md`)
- [ ] `tools.MustInitLRO(ctx, lroServiceID)` before launcher execute
- [ ] `weblro.NewLauncher(WithServiceID, WithLROClient(tools.LRO))` in launcher stack
- [ ] `lroresume` defaults match app name and service id
- [ ] `go build ./...` passes
- [ ] `MyTools()` may still have only sync tools — valid for bootstrap-only

## Next

Add individual LRO tools using **`references/lro-tool-checklist.md`**.
