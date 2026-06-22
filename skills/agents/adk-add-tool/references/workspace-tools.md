# Find the correct agent and proto paths (Tools)

Read **`alis-workspace.md`** and **`define-stubs.md`** (same directory) for project layout and code generation workflow.

## Quick discovery (before any edit)

Follow **`alis-workspace.md`** discovery tier order:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when needed). Use `focus_neuron_id` and `workstations` from JSON.
2. **Runtime context** — fill any remaining read-mask fields from `<alis-runtime-context>`.
3. **MCP** — `ViewProduct` when platform lists or environments are needed.
4. **Neuron anchors** — `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos`.
5. **Ask user** — smallest missing piece only.

| Need | Source |
| ---- | ------ |
| Neuron id | `focus_neuron_id` from resolve script |
| Neuron build root | `workstations.build_repos` |
| Go module | Nearest `go.mod` under build root |
| `tools.proto` | Under `workstations.define_repos` — read `package` line for define |

## Hard rules

| Do | Do not |
| ---- | ------ |
| Run resolve script first | Read `local.neuron` from infra Terraform for discovery |
| Keep proto and Go code edits on the **same** neuron id and neuron root | Edit protos or code for a different neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute package or import paths from another agent |
| Derive paths from resolve script output | Guess repo layout or assume `agent/` |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
