---
name: adk-add-scheduler
description: >
  Use this skill when the user wants scheduled or recurring agent runs, A2A scheduler extension,
  cron jobs, webscheduler launcher, or Cloud Tasks delivery for the agent — even if they do not
  say scheduler extension. Wires scheduler service, Spanner tables, IAM gRPC interceptors, and
  webscheduler.NewLauncher with WithGRPCRegistrar. Not for sync tools (add-tool), LRO (add-lro),
  AG-UI (add-agui), or embedded runtime skills (add-agent-skills).
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations.build_repos workstations.define_repos workstations.infra
---

# Add A2A scheduler launcher

Registers the **A2A scheduler extension** on the existing ADK `web.NewLauncher` stack. The scheduler uses Spanner for state and Cloud Tasks for delivery.

Before creating any new package, search the build module for existing capabilities using the discovery signals documented below. Extend existing packages rather than creating parallel ones. Do not refactor the user's layout to match templates. Templates provide greenfield defaults for new projects only.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads
`alis.context.requires` below to decide which context fields to include; the block carries
**only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **`<alis-runtime-context>`** — use injected context fields verbatim. Do not re-derive or ask the user to confirm values already provided.
2. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
3. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos` when proto work is needed.
4. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after runtime context) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | Used to derive `NeuronId` |
| Neuron build root | `workstations.build_repos` | Go module with scheduler and entrypoint |
| Neuron define tree | `workstations.define_repos` | Define package for Spanner proto imports |


Then read **`references/workspace-scheduler.md`** for path rules and central identity.

## When to use

See the skill **description** (primary trigger). Standard install wires: central identity, scheduler service bootstrap, IAM gRPC interceptors, `webscheduler.WithGRPCRegistrar`, proto imports, Terraform module, deployment args.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO tools, protos | **add-tool**, **add-lro** |
| AG-UI SSE endpoint | **add-agui** |
| Embedded runtime skills | **add-agent-skills** |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(web.NewLauncher(...))` already in place.
- A GCP project with Spanner and Cloud Tasks enabled.
- Cloud Tasks queue `{NeuronId}-a2a-scheduler` created in the agent's region.
- Environment variables set on the deployment (see **Environment variables** below).

## Capabilities

This skill introduces three capabilities. For each: discover existing → extend or create → wire → verify contract.

### Capability: Central identity

| | |
|-|-|
| **Contract** | Exactly one exported source for `AppName` (periods) and `NeuronId` (hyphens). All other packages import from this source. |
| **Discovery signals** | `AppName`, `NeuronId`, `llmagent.Config.Name`, existing constants package |
| **Wire points** | Imported by scheduler bootstrap, `main.go` launcher calls, `-app_name` CLI flag |
| **Greenfield default** | `internal/info/info.go` — see `references/templates/central-identity.go.example` |

**Derivation:** `focus_neuron_id` (hyphenated) = `NeuronId`. Replace `-` with `.` = `AppName`.

### Capability: Scheduler service bootstrap

| | |
|-|-|
| **Contract** | Package exports `var Service *schedulerservice.SchedulerService` and `func MustInitScheduler(ctx)`. Uses central `NeuronId` for Cloud Tasks queue (`{NeuronId}-a2a-scheduler`) and Spanner table prefix. Reads `ALIS_MANAGED_SPANNER_*`, `ALIS_OS_PROJECT`, `ALIS_REGION`, `AGENT_SERVICE_URL` from env. |
| **Discovery signals** | `NewSchedulerService`, `schedulerservice`, `MustInitScheduler`, `a2a/extension/scheduler`, existing scheduler bootstrap |
| **Wire points** | Called in `main.go` before launcher; `Service` passed to `webscheduler.NewLauncher` |
| **Greenfield default** | `internal/scheduler/scheduler.go` — see `references/templates/scheduler-service-bootstrap.go.example` |

### Capability: Alis web launcher stack

| | |
|-|-|
| **Contract** | When wiring any `go.alis.build/adk/launchers/*` sublauncher, the web host must import `go.alis.build/adk/launchers/web` — not `google.golang.org/adk/cmd/launcher/web`. Alis sublaunchers (lro, agui, scheduler, console) use `go.alis.build/adk/launchers/*`. Stock ADK sublaunchers without Alis equivalents (api, webui, a2a, agentengine) keep `google.golang.org/adk/cmd/launcher/*` imports as children inside the Alis web host. Do not use a google web host with Alis sublaunchers. `google.golang.org/adk/cmd/launcher/universal` stays unchanged. |
| **Discovery signals** | `google.golang.org/adk/cmd/launcher/web`, `google.golang.org/adk/cmd/launcher/webui`, `webapi`, `weba2a`, `webagentengine` |
| **Wire points** | Entrypoint import block and `universal.NewLauncher(web.NewLauncher(...))` call |
| **Greenfield default** | See `references/templates/scheduler-launcher-wiring.go.example` |

**Action:** If the entrypoint uses `google.golang.org/adk/cmd/launcher/web` as the web host, replace it with `go.alis.build/adk/launchers/web` before adding `webscheduler`. Migrate any existing Alis sublaunchers to `go.alis.build/adk/launchers/*`. Stock ADK sublaunchers (webui, api, a2a, agentengine) without Alis equivalents may keep their google imports inside the Alis web host. API surface is similar; Alis web adds mux/auth and other platform behavior. Keep existing sublauncher call order.

### Capability: Scheduler launcher wiring

| | |
|-|-|
| **Contract** | `scheduler.MustInitScheduler(ctx)` called before launcher. `grpc.NewServer(grpc.UnaryInterceptor(iam.UnaryInterceptor), grpc.StreamInterceptor(iam.StreamInterceptor))` + `mux.HandleGRPC(grpcServer)`. `webscheduler.NewLauncher(appName, scheduler.Service, webscheduler.WithGRPCRegistrar(grpcServer))` registered inside `web.NewLauncher(...)`. |
| **Discovery signals** | `webscheduler.NewLauncher`, `WithGRPCRegistrar`, `iam.UnaryInterceptor`, `iam.StreamInterceptor`, existing scheduler sublauncher |
| **Wire points** | Agent entrypoint, inside the `web.NewLauncher(...)` call |
| **Greenfield default** | See `references/templates/scheduler-launcher-wiring.go.example` |

## Steps

| # | Action |
|---|--------|
| 0 | **Discover** — search the build module for existing central identity, scheduler service, and scheduler wiring using discovery signals above |
| 1 | **Central identity** — ensure one source for `AppName` + `NeuronId` exists (extend existing or create from template) |
| 2 | **Scheduler service** — ensure capability exists (extend existing or create from template); must use central `NeuronId` |
| 3 | **Web launcher stack** — if entrypoint imports `google.golang.org/adk/cmd/launcher/web`, migrate web host to `go.alis.build/adk/launchers/web` before adding `webscheduler` |
| 4 | **Host gRPC** — ensure `grpc.Server` with `iam.UnaryInterceptor` + `iam.StreamInterceptor` (`go.alis.build/iam/v3`) + `mux.HandleGRPC(grpcServer)` exists (shared with add-agui when both apply) |
| 5 | **Scheduler launcher** — wire `webscheduler.NewLauncher(appName, service, WithGRPCRegistrar(...))` inside `web.NewLauncher(...)` |
| 6 | **Proto imports** — add orphan imports to define proto (common protobundle); ask user to **run define** |
| 7 | **Infra** — ensure `alis.a2a.extension.scheduler.v1` Terraform module + Cloud Tasks queue exist — see **`references/infra-scheduler.md`** |
| 8 | **Deployment** — add env vars and `scheduler` + `-app_name=<AppName>` to CLI args — Dockerfile CMD **must match** Cloud Run args |
| 9 | **Dependencies** — ask user to install/upgrade if needed |
| 10 | **Verify** — `go build ./...` |

## Central identity

See the **Central identity** capability above. Scheduler uses `info.NeuronId` for Cloud Tasks queue and Spanner prefix; `info.AppName` for `webscheduler.NewLauncher` and `-app_name` CLI flag.

| Derived value | Pattern | Example |
|---------------|---------|---------|
| Cloud Tasks queue | `{NeuronId}-a2a-scheduler` | `my-neuron-v1-a2a-scheduler` |
| Spanner table prefix | `{project}_{NeuronId}` (hyphens → underscores) | `my_project_my_neuron_v1` |
| Launcher + CLI | `AppName` | `my.neuron.v1` |

`local.neuron` in infra must match central `NeuronId`.

## Proto imports for Spanner tables

Protos ship in the **common protobundle** — import only in `tools.proto`:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Add **both** imports even when only scheduler is needed. Ask the user to **run define**. Also wire Terraform per **`references/infra-scheduler.md`**.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `ALIS_MANAGED_SPANNER_PROJECT` | Spanner host project |
| `ALIS_MANAGED_SPANNER_INSTANCE` | Spanner instance |
| `ALIS_MANAGED_SPANNER_DB` | Spanner database |
| `ALIS_OS_PROJECT` | GCP project for Cloud Tasks + service account |
| `ALIS_REGION` | Region for Cloud Tasks delivery |
| `AGENT_SERVICE_URL` | Base URL for Cloud Tasks callback delivery |

See **`references/infra-scheduler.md`** for deployment configuration.

## Deployment: launcher CLI args

Pass `scheduler` and `-app_name=<AppName>` in **both** Dockerfile CMD and Cloud Run args. **They must match.**

`-app_name` must match central `AppName` / `llmagent.Config.Name` / first arg to `webscheduler.NewLauncher`.

### Dockerfile

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "scheduler", "-app_name=my.neuron.v1"]
```

### Cloud Run (Terraform)

Template: **`references/templates/infra/cloudrun-args.tf.snippet.example`**

```hcl
args = ["web", "-port", "8080", "scheduler", "-app_name=my.neuron.v1"]
```

When **add-agui** is also wired:

```
args = ["web", "-port", "8080", "agui", "scheduler", "-app_name=my.neuron.v1"]
```

## Verification

- [ ] One source for `AppName` + `NeuronId` — no duplicates in scheduler or entrypoint
- [ ] Scheduler service exists; uses central `NeuronId` for queue and table prefix; exports `Service` + `MustInitScheduler`
- [ ] `scheduler.MustInitScheduler(ctx)` called before launcher
- [ ] gRPC server with `iam.UnaryInterceptor` + `iam.StreamInterceptor` + `mux.HandleGRPC`
- [ ] `webscheduler.NewLauncher(appName, ..., WithGRPCRegistrar(grpcServer))` inside `web.NewLauncher(...)` from `go.alis.build/adk/launchers/web` — **WithGRPCRegistrar required**
- [ ] No `google.golang.org/adk/cmd/launcher/web` import when `webscheduler` is wired
- [ ] Cloud Tasks queue `{NeuronId}-a2a-scheduler` exists
- [ ] Proto imports present; user ran define
- [ ] Application env vars (`ALIS_OS_PROJECT`, `ALIS_REGION`, `ALIS_PROJECT_NR`, Spanner, `AGENT_SERVICE_URL`) in **both** `cloudrun.tf` and `agent.tf` `deployment_spec`
- [ ] `GOOGLE_CLOUD_*` vars on Cloud Run only — not in `deployment_spec`
- [ ] Dockerfile CMD and Cloud Run args include `scheduler` + `-app_name=<AppName>` and **match**
- [ ] `go build ./...` passes

## Pitfalls

- Mixing `google.golang.org/adk/cmd/launcher/web` with Alis `webscheduler` or other `go.alis.build/adk/launchers/*` sublaunchers — migrate web host first
- Creating new packages without discovering existing ones — always search first
- Refactoring the user's layout to match skill templates without being asked
- Declaring `serviceID` in scheduler code instead of importing from central identity
- Passing hyphenated `focus_neuron_id` to `NewLauncher` — use `AppName`
- Forgetting `WithGRPCRegistrar` — scheduler gRPC won't register
- Using `schedulerservice.UnaryServerInterceptor()` on host `grpc.Server` — use `iam.UnaryInterceptor` + `iam.StreamInterceptor` from `go.alis.build/iam/v3`
- Dockerfile CMD differs from Cloud Run args
- Cloud Tasks queue name mismatch — must be `{NeuronId}-a2a-scheduler`
- `local.neuron` in infra does not match central `NeuronId`
- Missing `-app_name` in deployment args
- Skipping proto imports or Terraform module
- Application env vars added to only one of `cloudrun.tf` or `agent.tf` — same image, both runtimes need them
- `GOOGLE_CLOUD_*` vars added to `deployment_spec` — Reasoning Engine injects these automatically

## References & templates

| File | Purpose |
|------|---------|
| `references/templates/central-identity.go.example` | Central `AppName` + `NeuronId` |
| `references/templates/scheduler-service-bootstrap.go.example` | Scheduler service with central `NeuronId` |
| `references/templates/scheduler-launcher-wiring.go.example` | Entrypoint + shared gRPC |
| `references/templates/infra/scheduler-module.tf.example` | Terraform module |
| `references/templates/infra/cloudrun-args.tf.snippet.example` | Cloud Run args + env vars |
| `references/templates/infra/agent.tf.deployment_spec-envs.example` | Agent Engine `deployment_spec` env vars |
| `references/workspace-scheduler.md` | Path discovery + workspace rules |
| `references/infra-scheduler.md` | Spanner + Cloud Tasks + deployment infra |
