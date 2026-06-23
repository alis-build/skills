# Find the correct agent and proto paths (LRO)

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
| Go module | Nearest `go.mod` under `workstations.build_repos` |
| `tools.proto` | Under `workstations.define_repos` |
| Infra directory | Derive from the runtime context build root as `<workstations.build_repos entry>/infra` |
| Agent app name | `llmagent.Config.Name` → must match `lroresume.DefaultAppName` |

`lroServiceID` in Go must match `focus_neuron_id` from the runtime context (same value for `InitLRO` and `weblro.WithServiceID`).

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
| Use `<alis-runtime-context>` first; use `focus_neuron_id` | Read `local.neuron` from infra Terraform for discovery |
| Keep define, build, and infra edits on the **same** neuron id and neuron root | Edit another neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute paths from another agent |
| Derive define/build paths from runtime context | Guess repo layout or assume `agent/` |

User corrections override everything.
