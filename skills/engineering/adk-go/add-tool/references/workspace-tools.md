# Find the correct agent and proto paths (Tools)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

## Quick discovery (before any edit)

1. **Resolve neuron** — Follow **`alis-workspace.md`** tier order (MCP → path parse → neuron anchors). Confirm **neuron id** (`local.neuron` in `infra/`), **neuron root** (parent of `infra/`), and **neuron repo path** (`<neuron-path>/`).

2. **Go module (build repo)** — nearest `go.mod` under the neuron root for the service you are editing (may be in a subfolder or at the root — not always `agent/`). The module path tells you where `internal/tools` and the entrypoint live.

3. **`tools.proto` (define repo)** — under `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/`. Read the `package` line — use it when asking the user to run code generation.

4. **Service id** — `local.neuron` (or `var.neuron`) in `infra/` at the neuron root.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep proto and Go code edits on the **same** neuron id and neuron root | Edit protos or code for a different neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute package or import paths from another agent |
| Derive define/build paths per **`alis-workspace.md`** | Guess repo layout, assume `agent/`, or equate neuron id to one folder name |

User corrections override everything — re-read `package`, `go.mod`, and `local.neuron` at the path they give you.
