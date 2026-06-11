# Find the correct agent and proto paths (LRO)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

## Quick discovery (before any edit)

1. **Which neuron?** — `ViewProduct(lz, product)` when MCP is available; otherwise locate `infra/` with `local.neuron`, capture `<neuron-path>/` and neuron root per **`alis-workspace.md`**. The same `<neuron-path>/` must be used in build and define repos.

2. **`tools.proto` (define repo)** — under `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/`. LRO RPCs usually live on the same `ToolsService` as sync tools. Read the `package` line for **run a define on the package**.

3. **Go module (build repo)** — nearest `go.mod` under the neuron root for the service you are editing. LRO code: `internal/tools`, `internal/lroresume`, entrypoint `MustInitLRO` + `weblro` launcher.

4. **Infra neuron id** — `local.neuron` (or `variables.neuron`) in `infra/` at the neuron root → must match `lroServiceID` in Go and `weblro.WithServiceID`.

5. **Agent app name** — `llmagent.Config.Name` in the entrypoint → must match `lroresume.DefaultAppName` in `run_api.go`.

## LRO-specific checks

| Check | Where |
| ----- | ----- |
| `serviceID` / `lroServiceID` | Go const in entrypoint + `InitLRO` argument |
| Cloud Tasks queue name | `${neuron}-operations` in infra module |
| Spanner Operations table | `alis.lro.v2` module, neuron-derived name |
| Agent Engine LRO envs | `google_vertex_ai_reasoning_engine` → `spec.deployment_spec` (`infra-lro.md`) |
| Resume path strings | Unique per LRO tool; registered in `InitLRO` |

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep define, build, and infra edits on the **same** neuron id and neuron root | Edit another neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute paths from another agent |
| Derive define/build paths per **`alis-workspace.md`** | Guess repo layout, assume `agent/`, or equate neuron id to one folder name |

User corrections override everything.
