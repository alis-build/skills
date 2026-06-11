# Find the correct agent and infra paths (Scheduler)

Identify the agent module and infrastructure config before editing. The scheduler has no proto or define step for Go wiring — only infra and optional proto imports for Spanner tables.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron folder shape

Version is in the neuron id (e.g. `agent-v1`), not a nested `v1/` folder:

```text
<neuron-id>/
  agent/              # go.mod, ADK entrypoint, internal/*
  infra/              # Terraform; local.neuron = service id
```

## Canonical paths

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Define repo root | `~/alis.build/<landing-zone>/define/` |
| Neuron build tree | `~/alis.build/<lz>/build/<product>/<neuron>/` |
| Neuron protos | `~/alis.build/<lz>/define/<product>/<neuron>/` (e.g. `tools.proto`) |

Define paths include a `<product>/` segment; build paths do not repeat product inside the neuron folder.

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids, versions, environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
2. **Parse path** — If cwd or an open file is under `~/alis.build/...`, extract `<lz>`, `<product>`, `<neuron>` from path segments.
3. **Neuron anchors** — `agent/go.mod`, `infra/` → `local.neuron` / `var.neuron`.
4. **Ask user** — Smallest missing piece only (landing zone, product, or neuron).

## Deriving the paired repo

When only one repo is checked out:

- From build `~/alis.build/<lz>/build/<product>/<neuron>/` → define at `~/alis.build/<lz>/define/<product>/<neuron>/`
- From define `~/alis.build/<lz>/define/<product>/<neuron>/` → build at `~/alis.build/<lz>/build/<product>/<neuron>/`
- If not under `~/alis.build` → MCP `CloneProduct` / `PullDefine`, or ask for landing zone + product

## Quick discovery (before any edit)

1. **Agent module** — `go.mod` under `~/alis.build/<lz>/build/<product>/<neuron>/agent/`. The module path tells you where `internal/scheduler` and the entrypoint live.

2. **Service id** — `local.neuron` (or `var.neuron`) in `infra/`. Drives Cloud Tasks queue name (`{id}-a2a-scheduler`) and Spanner table prefix. Confirm via `ViewProduct` when using MCP.

3. **Agent app name** — `llmagent.Config.Name` in the entrypoint — passed as the first argument to `webscheduler.NewLauncher`.

4. **Infra directory** — `~/alis.build/<lz>/build/<product>/<neuron>/infra/`. Terraform config for Cloud Tasks queue, Spanner, and deployment env vars.

## Finding the service id

The service id must match the `serviceID` const in `internal/scheduler/scheduler.go`.

| Source | Where to look |
| ------ | ------------- |
| Alis Build (default) | `local.neuron` or `var.neuron` in `infra/` |
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
| Read `go.mod` and infra config from the agent you're editing | Substitute ids from another agent or templates |
| Confirm `serviceID` matches `infra/local.neuron` before wiring | Guess the service id from folder names |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Ask the user if pairing is unclear | Assume repo layout |

User corrections override everything.
