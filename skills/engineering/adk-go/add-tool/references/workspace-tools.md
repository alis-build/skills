# Find the correct agent and proto paths (Tools)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

## Quick discovery (before any edit)

1. **Resolve neuron** — Follow **`alis-workspace.md`** tier order (MCP → `~/alis.build` path parse → neuron anchors). Full repo resolution: **`alis-workspace.md`**.

2. **Agent module (build repo)** — `go.mod` under `~/alis.build/<lz>/build/<product>/<neuron>/agent/`. The module path tells you where `internal/tools` and the entrypoint live.

3. **`tools.proto` (define repo)** — `~/alis.build/<lz>/define/<product>/<neuron>/tools.proto`. Read the `package` line — use it when asking the user to run code generation.

4. **Service id** — `local.neuron` (or `var.neuron`) in `infra/`. Used for LRO, AG-UI, or scheduler wiring if present alongside tools.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep proto and Go code edits on the **same** neuron | Edit protos or code for a different neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute package or import paths from another agent |
| Derive define/build paths per **`alis-workspace.md`** | Guess repo layout |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
