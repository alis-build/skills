# Find the correct agent and proto paths (Tools)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

## Quick discovery (before any edit)

1. **Agent module** — Find `go.mod` in the agent directory. The module path tells you where `internal/tools` and the entrypoint live.

2. **`tools.proto`** — The proto file defining your `ToolsService` RPCs. May be in the same repo or a separate definitions repo. Read the `package` line — use it when asking the user to run code generation.

3. **Service id** — From the infrastructure config (Terraform `locals`, variables). Used for LRO, AG-UI, or scheduler wiring if present alongside tools.

### Alis Build projects

- Same `{neuron}/{version}/` path in both **build** and **define** repositories.
- `locals.neuron` (or equivalent) in `infra/` → use for **run a define on the neuron**.
- If **`.alis/agents/AGENTS.md`** exists, read it for this product's repo roots.

## Hard rules

| Do | Do not |
|----|--------|
| Keep proto and Go code edits on the **same** agent/version | Edit protos or code for a different agent from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute package or import paths from another agent |
| Ask the user if paths are unclear | Guess repo layout |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
