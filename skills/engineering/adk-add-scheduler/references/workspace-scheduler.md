# Find the correct agent and infra paths (Scheduler)

Identify the agent module and infrastructure config before editing. The scheduler has no proto or define step for Go wiring — only infra and optional proto imports for Spanner tables.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`). The same trail appears under build and define when proto work is needed.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go services may live in subfolders or at the neuron root — follow the neuron you are editing. If multiple `go.mod` files exist, ask which service receives the scheduler wiring.

## Canonical paths

| Artifact | Script key |
| -------- | ---------- |
| Alis Build root | `workstations.root_directory` |
| Neuron build root | `workstations.build_repos[]` |
| Neuron define tree | `workstations.define_repos[]` |
| Infra directory | `workstations.infra` |
| Playground | `workstations.playground` |

## Discovery tier order

1. **Resolve script** — Run the bundled resolver. It derives organisation, product, neuron id, and all workstation paths purely from the `~/alis.build/` directory structure. Pass `--cwd` when the user's working directory differs from the target neuron:

   ```bash
   bash scripts/resolve-alis-workspace.sh --json
   bash scripts/resolve-alis-workspace.sh --json --cwd <path>
   ```

   The JSON output provides `organisation_id`, `product_id`, `focus_neuron_id`, and `workstations` (build_repos, define_repos, infra, playground). Use these values directly — do not re-derive them.

2. **`<alis-runtime-context>`** — When LoadSkill injected the block, use its values for any field not already set by the resolve script. Do not re-derive or re-ask for values present in the block.

3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under the neuron build root for the service you are editing.
5. **Ask user** — Smallest missing piece only (which neuron when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the resolve script.

2. **Go module** — nearest `go.mod` under that root. The module path tells you where `internal/scheduler` and the entrypoint live.

3. **Service id** — `focus_neuron_id` from the resolve script. Drives Cloud Tasks queue name (`{id}-a2a-scheduler`) and Spanner table prefix.

4. **Agent app name** — `llmagent.Config.Name` in the entrypoint — passed as the first argument to `webscheduler.NewLauncher`.

5. **Infra directory** — `workstations.infra` from the resolve script. Terraform config for Cloud Tasks queue, Spanner, and deployment env vars.

## Finding the service id

The service id must match the `serviceID` const in `internal/scheduler/scheduler.go`.

| Source | Where to look |
| ------ | ------------- |
| Resolve script (default) | `focus_neuron_id` from `bash scripts/resolve-alis-workspace.sh --json` |
| Existing LRO | Reuse `lroServiceID` from the entrypoint |
| Existing AG-UI | Reuse the service id from `webagui.NewLauncher` |
| Unclear | Ask the user — do not guess from folder names |

## Scheduler-specific checks

| Check | Where |
| ----- | ----- |
| `serviceID` | Go const in `internal/scheduler/scheduler.go` |
| Cloud Tasks queue name | `{serviceID}-a2a-scheduler` in scheduler config |
| Spanner table prefix | `{project}_{serviceID}` (hyphens to underscores) |
| Scheduler env vars | Deployment config (Agent Engine `deployment_spec`, Cloud Run env) |
| gRPC interceptor | `schedulerservice.UnaryServerInterceptor()` on `grpc.NewServer` |
| Host mux registration | `mux.HandleGRPC(grpcServer)` in entrypoint |

## Hard rules

| Do | Do not |
| ---- | ------ |
| Run `bash scripts/resolve-alis-workspace.sh --json` first | Manually parse `~/alis.build` paths or read infra terraform files |
| Use the resolve script output for build/define/infra paths | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` from the service you're editing | Substitute ids from another agent or templates |
| Confirm `serviceID` matches `focus_neuron_id` before wiring | Guess the service id from folder names |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of the script, runtime context, or MCP |
| Ask the user if pairing is unclear | Guess repo layout or equate neuron id to a single folder name |

User corrections override everything.
