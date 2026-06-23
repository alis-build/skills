# Find the correct agent and proto paths (Tools)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

## Quick discovery (before any edit)

Follow **`alis-workspace.md`** discovery tier order:

1. **`<alis-runtime-context>`** — use `focus_neuron_id` and `workstations` from the injected runtime context.
2. **MCP** — `ViewProduct` when platform lists or environments are needed.
3. **Neuron anchors** — `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos`.
4. **Ask user** — smallest missing piece only.

| Need | Source |
| ---- | ------ |
| Neuron id | `focus_neuron_id` from runtime context |
| Neuron build root | `workstations.build_repos` |
| Go module | Nearest `go.mod` under build root |
| `tools.proto` | Under `workstations.define_repos` — read `package` line for define |

## Hard rules

| Do | Do not |
| ---- | ------ |
| Use `<alis-runtime-context>` first | Read `local.neuron` from infra Terraform for discovery |
| Keep proto and Go code edits on the **same** neuron id and neuron root | Edit protos or code for a different neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute package or import paths from another agent |
| Derive paths from runtime context | Guess repo layout or assume `agent/` |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
