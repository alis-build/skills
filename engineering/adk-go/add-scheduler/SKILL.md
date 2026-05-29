---
name: add-scheduler
description: >
  Wires the A2A scheduler extension (go.alis.build/a2a/extension/scheduler, webscheduler.NewLauncher)
  into an ADK agent entrypoint with Spanner-backed scheduling, Cloud Tasks delivery, and gRPC
  interceptor. Use when bootstrapping internal/scheduler, adding the scheduler sublauncher, wiring
  the gRPC interceptor, or when the user mentions A2A scheduler, cron scheduling, scheduled tasks,
  Cloud Tasks queue for scheduling, scheduler extension, webscheduler, or recurring agent
  invocations—even if they do not say a2a or scheduler extension. Do not use for sync tools
  (add-tool), long-running operations (add-lro), AG-UI (add-agui), or embedded runtime skills
  (add-agent-skills). No proto or define step; service id must match infra config.
disable-model-invocation: true
---

# Add A2A scheduler launcher

Registers the **A2A scheduler extension** on the existing ADK `web.NewLauncher` stack. The scheduler uses Spanner for state and Cloud Tasks for delivery. Wiring requires an `internal/scheduler` package, a gRPC server with the scheduler interceptor, and the `webscheduler` sublauncher.

Read **`references/workspace.md`** for path discovery before making changes.

## When to use

See the skill **description** (primary trigger). Internal scheduler package + gRPC interceptor + sublauncher inside `web.NewLauncher`; no define.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO tools, protos | `../add-tool/SKILL.md`, `../add-lro/SKILL.md` |
| AG-UI SSE endpoint | `../add-agui/SKILL.md` |
| Embedded runtime skills | `../add-agent-skills/SKILL.md` |
| **define** / `tools.proto` | Not required for scheduler |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(web.NewLauncher(...))` already in place.
- A GCP project with Spanner and Cloud Tasks enabled.
- Cloud Tasks queue `{service-id}-a2a-scheduler` created in the agent's region.
- Environment variables set on the deployment (see **Environment variables** below).
- User can **install required dependencies** if `go.alis.build/a2a/extension/scheduler` and `go.alis.build/adk/launchers` are not already in `go.mod`.

## Architecture

```
internal/scheduler/scheduler.go
    InitScheduler(ctx) → schedulerservice.NewSchedulerService (Spanner + Cloud Tasks)
    MustInitScheduler(ctx)
    package-level Service variable
        ↓
main.go
    scheduler.MustInitScheduler(ctx)
    grpc.NewServer(grpc.UnaryInterceptor(schedulerservice.UnaryServerInterceptor()))
    mux.HandleGRPC(grpcServer)
        ↓
    web.NewLauncher(
        ...,
        webscheduler.NewLauncher(adkAppName, scheduler.Service, webscheduler.WithGRPCRegistrar(grpcServer)),
    )
```

The `serviceID` in `internal/scheduler/scheduler.go` must match the infra service identifier. The Cloud Tasks queue name is `{serviceID}-a2a-scheduler`. The `TargetUrl` is `AGENT_SERVICE_URL + schedulerext.HandlerPath`.

## Phase A — Bootstrap scheduler (one-time)

Read and follow **`references/workspace.md`** for path discovery.

| # | Action | Template |
|---|--------|----------|
| 1 | Create `internal/scheduler/scheduler.go` with `InitScheduler`, `MustInitScheduler`, and package-level `Service` | `references/templates/scheduler.go.example` |
| 2 | Set `serviceID` const to match infra service identifier | `references/workspace.md` |
| 3 | Wire entrypoint: import scheduler package, call `MustInitScheduler`, create gRPC server with interceptor, register with mux, add `webscheduler` sublauncher | `references/templates/main-scheduler-wiring.go.example` |
| 4 | Ensure infra has Spanner table + Cloud Tasks queue + env vars on deployment | `references/infra-scheduler.md` |
| 5 | Add `scheduler` and `-app_name=<adkAppName>` to the launcher CLI args in Dockerfile and Cloud Run / deployment config | See **Deployment: launcher CLI args** below |
| 6 | Ask user to install/upgrade dependencies if needed (`go.alis.build/a2a/extension/scheduler`, `go.alis.build/adk/launchers`, `go.alis.build/mux`, `go.alis.build/utils`, `go.alis.build/alog`) |
| 7 | `go build ./...` and run the agent locally to verify scheduler routes are served |

Replace all `REPLACE_WITH_*` placeholders with your module and project values.

## Service id and identifiers

The `serviceID` const in `internal/scheduler/scheduler.go` is the core identifier that drives several derived values:

| Derived value | Pattern | Example |
|---------------|---------|---------|
| Cloud Tasks queue | `{serviceID}-a2a-scheduler` | `my-agent-v1-a2a-scheduler` |
| Spanner table prefix | `{project}_{serviceID}` (hyphens → underscores) | `my_project_my_agent_v1` |
| Service account | `alis-build@{project}.iam.gserviceaccount.com` | — |
| Target URL | `AGENT_SERVICE_URL + schedulerext.HandlerPath` | — |

**Finding the service id:** Look in the project's infrastructure config — typically a Terraform `locals` block or variables file. If LRO is already wired, reuse the same value as `lroServiceID`.

### Alis Build projects

In Alis Build neuron layout, the service id is `local.neuron` (or `variables.neuron`) in `infra/`. Read **`.alis/agents/AGENTS.md`** if it exists for product repo roots.

## Environment variables

The scheduler reads configuration from the process environment. These must be set on the deployment target (Agent Engine `deployment_spec`, Cloud Run env, or local `.env`):

| Variable | Purpose |
|----------|---------|
| `ALIS_MANAGED_SPANNER_PROJECT` | Spanner host project |
| `ALIS_MANAGED_SPANNER_INSTANCE` | Spanner instance name |
| `ALIS_MANAGED_SPANNER_DB` | Spanner database name |
| `ALIS_OS_PROJECT` | GCP project for Cloud Tasks + service account |
| `ALIS_REGION` | Region for Cloud Tasks delivery |
| `AGENT_SERVICE_URL` | Base URL for Cloud Tasks callback delivery |

The template uses `env.MustGet` from `go.alis.build/utils/env` which panics on missing values. For projects that prefer a different env-reading approach, adapt `InitScheduler` accordingly — the important thing is that all six values are available at startup.

See **`references/infra-scheduler.md`** for deployment configuration details.

## Deployment: launcher CLI args

The ADK `universal.NewLauncher` / `web.NewLauncher` binary uses **positional CLI args** to activate each sublauncher at runtime. Registering `webscheduler.NewLauncher` in Go is not enough — you must also pass `scheduler` and `-app_name=<adkAppName>` in the command args when running the binary.

The `scheduler` arg activates the scheduler sublauncher. The `-app_name` flag tells the scheduler which ADK app name to use (must match `llmagent.Config.Name` / the first arg to `webscheduler.NewLauncher`).

Only include sublauncher args for sublaunchers the agent actually uses. The scheduler sublauncher is independent — it has no dependencies on other sublaunchers (`webui`, `api`, `lro`, `agui`, etc.).

### Dockerfile

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME"]
```

### Cloud Run (Terraform)

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME"]
}
```

### Minimal vs full example

The above shows only what the scheduler requires. A typical agent with multiple sublaunchers might look like:

```
args = ["web", "-port", "8080", "webui", "-api_server_address=/api", "api", "lro", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME"]
```

Add other sublaunchers (`webui`, `api`, `lro`, `agui`, etc.) only if the agent uses them — they are not scheduler prerequisites. If other sublaunchers are already present, append `scheduler` and `-app_name=...` to the existing args list.

### Local development

```bash
go run . web -port 8080 scheduler -app_name=REPLACE_WITH_ADK_APP_NAME
```

## Verification

- [ ] `internal/scheduler/scheduler.go` exists with `InitScheduler`, `MustInitScheduler`, `Service`
- [ ] `serviceID` matches infra service identifier
- [ ] `scheduler.MustInitScheduler(ctx)` called in entrypoint before launcher
- [ ] gRPC server created with `schedulerservice.UnaryServerInterceptor()`
- [ ] gRPC server registered with `mux.HandleGRPC(grpcServer)`
- [ ] `webscheduler.NewLauncher` inside `web.NewLauncher(...)` with `WithGRPCRegistrar(grpcServer)`
- [ ] Cloud Tasks queue `{serviceID}-a2a-scheduler` exists in the agent's region
- [ ] Scheduler env vars set on deployment target
- [ ] Dockerfile CMD includes `scheduler` and `-app_name=<adkAppName>`
- [ ] Cloud Run / deployment args include `scheduler` and `-app_name=<adkAppName>`
- [ ] `go build ./...` passes
- [ ] Agent starts without scheduler initialization errors

## Pitfalls

- Wrong `serviceID` — read the infra config for the agent you are editing, not templates or other agents.
- Adding `webscheduler` outside `web.NewLauncher` — it must be a **sibling** sublauncher with `webui`, `webapi`, `weblro`, etc.
- Forgetting `mux.HandleGRPC(grpcServer)` — the gRPC server won't receive traffic without host mux registration.
- Missing `schedulerservice.UnaryServerInterceptor()` on the gRPC server — scheduler RPCs won't be intercepted.
- Cloud Tasks queue name mismatch — must be exactly `{serviceID}-a2a-scheduler`.
- `Service == nil` at runtime — `MustInitScheduler` not called or env vars missing.
- Missing scheduler env vars on deployment — `env.MustGet` panics at runtime.
- Running `go get` before confirming whether dependencies are already required — ask user to install dependencies when unsure.
- Forgetting to pass `webscheduler.WithGRPCRegistrar(grpcServer)` — scheduler gRPC service won't be registered.
- Missing `scheduler` in Dockerfile CMD or Cloud Run args — the sublauncher is registered in Go but won't activate without the CLI arg.
- Missing `-app_name` flag in deployment args — the scheduler needs the ADK app name to function.

## Templates index

| File | Purpose |
|------|---------|
| `references/workspace.md` | Path discovery + service id alignment |
| `references/infra-scheduler.md` | Spanner + Cloud Tasks + deployment infra |
| `references/templates/scheduler.go.example` | `internal/scheduler/scheduler.go` |
| `references/templates/main-scheduler-wiring.go.example` | Entrypoint scheduler + webscheduler wiring |
| `references/templates/infra/scheduler-module.tf.example` | Full Terraform module (Spanner table + Cloud Tasks queue + IAM) |
| `references/templates/infra/main.tf.snippet.example` | Module block for `infra/main.tf` |
| `references/templates/infra/cloudrun-args.tf.snippet.example` | Cloud Run container args with `scheduler` + `-app_name` |
