# Find the correct agent and proto paths (LRO)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

If the product workspace provides **`.alis/agents/AGENTS.md`**, read it first — then use the steps below.

## Quick discovery (before any edit)

1. **Which neuron/version?** — From workspace folders or the user. Same `{neuron}/{version}/` for define and build.

2. **`tools.proto` (define repo)** — LRO RPCs usually live on the same `ToolsService` as sync tools. Read the `package` line for **run a define on the package**.

3. **Agent module (build repo)** — `go.mod` + entrypoint under `agent/`. LRO code: `internal/tools`, `internal/lroresume`, entrypoint `MustInitLRO` + `weblro` launcher.

4. **Infra neuron id** — `local.neuron` (or `variables.neuron`) in `infra/` → must match `lroServiceID` in Go and `weblro.WithServiceID`.

5. **Agent app name** — `llmagent.Config.Name` in the entrypoint → must match `lroresume.DefaultAppName` in `run_api.go`.

## LRO-specific checks

| Check | Where |
|-------|--------|
| `serviceID` / `lroServiceID` | Go const in entrypoint + `InitLRO` argument |
| Cloud Tasks queue name | `${neuron}-operations` in infra module |
| Spanner Operations table | `alis.lro.v2` module, neuron-derived name |
| Agent Engine LRO envs | `google_vertex_ai_reasoning_engine` → `spec.deployment_spec` (`infra-lro.md`) |
| Resume path strings | Unique per LRO tool; registered in `InitLRO` |

## Hard rules

| Do | Do not |
|----|--------|
| Keep define, build, and infra edits on the **same** neuron/version | Edit another neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute paths from another agent |
| Ask the user if pairing is unclear | Guess repo layout |

User corrections override everything.
