---
name: adk-add-scheduler
description: >
  Use this skill when the user wants scheduled or recurring agent runs, A2A scheduler extension,
  cron jobs, webscheduler launcher, or Cloud Tasks delivery for the agent — even if they do not
  say scheduler extension. Wires internal/scheduler, Spanner tables, gRPC interceptor, and
  webscheduler.NewLauncher. Not for sync tools (add-tool), LRO (add-lro), AG-UI (add-agui), or
  embedded runtime skills (add-agent-skills).
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations.build_repos workstations.define_repos
---

# Add A2A scheduler launcher

Registers the **A2A scheduler extension** on the existing ADK `web.NewLauncher` stack. The scheduler uses Spanner for state and Cloud Tasks for delivery. Wiring requires an `internal/scheduler` package, a gRPC server with the scheduler interceptor, and the `webscheduler` sublauncher.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos` when proto work is needed.
5. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | Scheduler queue name, Spanner table prefix, and `webscheduler.NewLauncher` scope |
| Neuron build root | `workstations.build_repos` | Go module with `internal/scheduler` and entrypoint |
| Neuron define tree | `workstations.define_repos` | Define package for optional `scheduler.proto` Spanner imports |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/workspace-scheduler.md`** for path rules and tier 3+ discovery, including scheduler-specific path checks.

## When to use

See the skill **description** (primary trigger). Internal scheduler package + gRPC interceptor + sublauncher inside `web.NewLauncher`; proto imports + define for Spanner tables.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO tools, protos | **add-tool**, **add-lro** |
| AG-UI SSE endpoint | **add-agui** |
| Embedded runtime skills | **add-agent-skills** |

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

Read and follow **`references/workspace-scheduler.md`** for path discovery.

| # | Action | Template |
|---|--------|----------|
| 1 | Create `internal/scheduler/scheduler.go` with `InitScheduler`, `MustInitScheduler`, and package-level `Service` | `references/templates/scheduler.go.example` |
| 2 | Set `serviceID` const to `focus_neuron_id` from the resolve script (or runtime context) | `references/workspace-scheduler.md` |
| 3 | Wire entrypoint: import scheduler package, call `MustInitScheduler`, create gRPC server with interceptor, register with mux, add `webscheduler` sublauncher | `references/templates/main-scheduler-wiring.go.example` |
| 4 | Add proto imports for Spanner tables if not already present (see **Proto imports for Spanner tables** below); ask user to run define |
| 5 | Ensure infra has Spanner table + Cloud Tasks queue + env vars on deployment | `references/infra-scheduler.md` |
| 6 | Add `scheduler` and `-app_name=<adkAppName>` to the launcher CLI args in Dockerfile and Cloud Run / deployment config | See **Deployment: launcher CLI args** below |
| 7 | Ask user to install/upgrade dependencies if needed (`go.alis.build/a2a/extension/scheduler`, `go.alis.build/adk/launchers`, `go.alis.build/mux`, `go.alis.build/utils`, `go.alis.build/alog`) |
| 8 | `go build ./...` and run the agent locally to verify scheduler routes are served |

Replace all `REPLACE_WITH_*` placeholders with your module and project values.

## Service id and identifiers

The `serviceID` const in `internal/scheduler/scheduler.go` is the core identifier that drives several derived values:

| Derived value | Pattern | Example |
|---------------|---------|---------|
| Cloud Tasks queue | `{serviceID}-a2a-scheduler` | `my-agent-v1-a2a-scheduler` |
| Spanner table prefix | `{project}_{serviceID}` (hyphens → underscores) | `my_project_my_agent_v1` |
| Service account | `alis-build@{project}.iam.gserviceaccount.com` | — |
| Target URL | `AGENT_SERVICE_URL + schedulerext.HandlerPath` | — |

**Finding the service id:** Use `focus_neuron_id` from `bash scripts/resolve-alis-workspace.sh --json`. If LRO or AG-UI is already wired, reuse the same id only when it matches `focus_neuron_id`. Read **`references/workspace-scheduler.md`** for the full discovery tier order.

## Proto imports for Spanner tables

The scheduler stores cron state in Spanner tables provisioned through define. Add the following imports to **any one** proto in the agent's define package (typically `tools.proto`), even if nothing in the file references them:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Add **both** imports whenever scheduler Spanner tables are required — even if the agent does not use AG-UI threads/history yet. The imports are for table provisioning, not for RPC definitions in your service.

Ask the user to **run define** on the package (or neuron) after editing the proto. Add **both** imports whenever either scheduler or thread/history Spanner tables are needed — the same rule applies for **add-agui**.

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
- [ ] `serviceID` matches `focus_neuron_id` from resolve script (or runtime context)
- [ ] `scheduler.MustInitScheduler(ctx)` called in entrypoint before launcher
- [ ] gRPC server created with `schedulerservice.UnaryServerInterceptor()`
- [ ] gRPC server registered with `mux.HandleGRPC(grpcServer)`
- [ ] `webscheduler.NewLauncher` inside `web.NewLauncher(...)` with `WithGRPCRegistrar(grpcServer)`
- [ ] Cloud Tasks queue `{serviceID}-a2a-scheduler` exists in the agent's region
- [ ] Proto imports for scheduler (and history) Spanner tables present; user ran define
- [ ] Scheduler env vars set on deployment target
- [ ] Dockerfile CMD includes `scheduler` and `-app_name=<adkAppName>`
- [ ] Cloud Run / deployment args include `scheduler` and `-app_name=<adkAppName>`
- [ ] `go build ./...` passes
- [ ] Agent starts without scheduler initialization errors

## Pitfalls

- Wrong `serviceID` — use `focus_neuron_id` from the resolve script, not infra Terraform locals or templates from other agents.
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
- Skipping proto imports for Spanner tables — scheduler storage will not be provisioned; add both `scheduler.proto` and `history.proto` imports and run define.

## Templates index

| File | Purpose |
|------|---------|
| `references/workspace-scheduler.md` | Path discovery + service id alignment |
| `references/infra-scheduler.md` | Spanner + Cloud Tasks + deployment infra |
| `references/templates/scheduler.go.example` | `internal/scheduler/scheduler.go` |
| `references/templates/main-scheduler-wiring.go.example` | Entrypoint scheduler + webscheduler wiring |
| `references/templates/infra/scheduler-module.tf.example` | Full Terraform module (Spanner table + Cloud Tasks queue + IAM) |
| `references/templates/infra/main.tf.snippet.example` | Module block for `infra/main.tf` |
| `references/templates/infra/cloudrun-args.tf.snippet.example` | Cloud Run container args with `scheduler` + `-app_name` |
