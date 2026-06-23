# Find the correct agent and infra paths (Scheduler)

Identify the agent module and infrastructure config before editing.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Central identity

`AppName` and `NeuronId` must live in **one editable place**. The exact package does not matter as long as there is exactly one source and all consumers import from it. The scheduler uses central `NeuronId` for queue name and Spanner prefix — do not declare a local `serviceID` const.

| Constant | Form | Example |
|----------|------|---------|
| `NeuronId` | hyphenated (`focus_neuron_id`) | `my-neuron-v1` |
| `AppName` | same id, `-` → `.` | `my.neuron.v1` |

**Before wiring scheduler:** search the module for existing identity. If found in one place, use it. If scattered, consolidate (with user permission). If absent, create from `references/templates/central-identity.go.example` (greenfield default: `internal/info/info.go`).

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`. Stored as `info.NeuronId`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`). The same trail appears under build and define when proto work is needed.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go services may live in subfolders or at the neuron root — follow the neuron you are editing. If multiple `go.mod` files exist, ask which service receives the scheduler wiring.

## Canonical paths

| Artifact | Context field |
| -------- | ---------- |
| Alis Build root | `workstations.root_directory` |
| Neuron build root | `workstations.build_repos[]` |
| Neuron define tree | `workstations.define_repos[]` |
| Infra directory | `workstations.infra` |
| Playground | `workstations.playground` |

## Discovery tier order

1. **`<alis-runtime-context>`** — Use injected values when present.
2. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct`.
3. **Neuron anchors** — nearest `go.mod` under the neuron build root.
4. **Ask user** — Smallest missing piece only.

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the runtime context.
2. **Go module** — nearest `go.mod` under that root.
3. **Identity** — search for existing central identity; if absent, `focus_neuron_id` → `NeuronId`, derive `AppName`.
4. **Infra directory** — `workstations.infra` for Cloud Tasks queue and Spanner Terraform.

## Scheduler-specific checks

| Check | Where |
| ----- | ----- |
| `NeuronId` | Central identity package (not a local const in scheduler code) |
| Cloud Tasks queue name | `{NeuronId}-a2a-scheduler` |
| Spanner table prefix | `{project}_{NeuronId}` (hyphens to underscores) |
| `AppName` | First arg to `webscheduler.NewLauncher`; `-app_name` CLI flag |
| gRPC interceptor | `iam.UnaryInterceptor` + `iam.StreamInterceptor` (`go.alis.build/iam/v3`) on `grpc.NewServer` |
| `WithGRPCRegistrar` | **required** on `webscheduler.NewLauncher` |
| Shared gRPC host | Same `grpcServer` as **add-agui** when both wired |

## Hard rules

| Do | Do not |
| ---- | ------ |
| Use `<alis-runtime-context>` first | Declare `serviceID` inline in scheduler code |
| Consolidate identity to one central package before wiring | Scatter `AppName` / neuron id across packages |
| Use central `NeuronId` for queue and table prefix | Pass hyphenated id to `NewLauncher` (use `AppName`) |
| Match `local.neuron` in infra to central `NeuronId` | Guess ids from folder names |

User corrections override everything.
