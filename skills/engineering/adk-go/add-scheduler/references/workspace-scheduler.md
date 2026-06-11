# Find the correct agent and infra paths (Scheduler)

Identify the agent module and infrastructure config before editing. The scheduler has no proto or define step for Go wiring — only infra and optional proto imports for Spanner tables.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — platform identifier from `ViewProduct` or `local.neuron` / `var.neuron` in `infra/`. Hyphen-separated; may encode several segments and a version (`…-v1`, `…-v2`, etc.). A product can host many neuron ids — pick the target explicitly.

**Neuron repo path** — multi-segment directory under the product (often ending in `v1/`, `v2/`, …), usually **not** a single folder named like the neuron id. The same `<neuron-path>/` appears under build and define when proto work is needed.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go services may live in subfolders or at the neuron root — follow the neuron you are editing. If multiple `go.mod` files exist, ask which service receives the scheduler wiring.

## Canonical paths

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Define repo root | `~/alis.build/<landing-zone>/define/` |
| Neuron build root | `~/alis.build/<lz>/build/<product>/<neuron-path>/` (parent of `infra/`) |
| Neuron define tree | `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/` |

- `<define-product-path>` may be nested when the product id contains dots — confirm from MCP or the define repo.

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids, versions, environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
2. **Parse path** — Locate `infra/` with `local.neuron` under `~/alis.build/...`. Its parent is the neuron root; capture `<neuron-path>` up to the product folder.
3. **Neuron anchors** — `infra/` → `local.neuron` / `var.neuron`; nearest `go.mod` under the neuron root for the service you are editing.
4. **Ask user** — Smallest missing piece only (landing zone, product, neuron id, or which neuron when several exist).

## Deriving the paired repo

1. Record `<neuron-path>/` to the neuron root (parent of `infra/`).
2. **Build → define** — `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/`
3. **Define → build** — `~/alis.build/<lz>/build/<product>/<neuron-path>/`
4. If not under `~/alis.build` → MCP `CloneProduct` / `PullDefine`, or ask for landing zone + product.

## Quick discovery (before any edit)

1. **Neuron root** — parent of `infra/` under `~/alis.build/<lz>/build/<product>/<neuron-path>/`.

2. **Go module** — nearest `go.mod` under that root. The module path tells you where `internal/scheduler` and the entrypoint live.

3. **Service id** — `local.neuron` (or `var.neuron`) in `infra/`. Drives Cloud Tasks queue name (`{id}-a2a-scheduler`) and Spanner table prefix. Confirm via `ViewProduct` when using MCP.

4. **Agent app name** — `llmagent.Config.Name` in the entrypoint — passed as the first argument to `webscheduler.NewLauncher`.

5. **Infra directory** — `…/<neuron-path>/infra/`. Terraform config for Cloud Tasks queue, Spanner, and deployment env vars.

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
| Anchor on `infra/` + `local.neuron`, then find the correct `go.mod` | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` and infra config from the service you're editing | Substitute ids from another agent or templates |
| Confirm `serviceID` matches `infra/local.neuron` before wiring | Guess the service id from folder names |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Ask the user if pairing is unclear | Guess repo layout or equate neuron id to a single folder name |

User corrections override everything.
