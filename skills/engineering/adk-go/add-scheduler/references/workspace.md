# Find the correct agent and infra paths (Scheduler)

Identify the agent module and infrastructure config before editing. The scheduler has no proto or define step — only Go wiring and infra.

## Quick discovery (before any edit)

1. **Agent module** — Find `go.mod` in the agent directory. The module path (e.g. `my.project.agent/v1/agent`) tells you where `internal/scheduler` and the entrypoint live.

2. **Service id** — A short identifier for this agent service (e.g. `my-agent-v1`). It drives the Cloud Tasks queue name (`{id}-a2a-scheduler`) and Spanner table prefix. Find it in the infra config — see below.

3. **Agent app name** — `llmagent.Config.Name` in the entrypoint — passed as the first argument to `webscheduler.NewLauncher`.

4. **Infra directory** — Typically `infra/` alongside `agent/`. Contains Terraform (or equivalent) config for the Cloud Tasks queue, Spanner, and deployment env vars.

## Finding the service id

The service id appears in infrastructure config and must match the `serviceID` const in `internal/scheduler/scheduler.go`.

| Project type | Where to look |
|--------------|---------------|
| Terraform | `locals { neuron = "..." }` or `variable "neuron"` in `infra/` |
| Existing LRO | Reuse `lroServiceID` from the entrypoint |
| Existing AG-UI | Reuse the service id from `webagui.NewLauncher` |
| Other | Ask the user for the service identifier |

### Alis Build projects

In Alis Build neuron layout: `local.neuron` (or `variables.neuron`) in `infra/`. If **`.alis/agents/AGENTS.md`** exists, read it for product repo roots and neuron paths.

```text
{neuron}/{version}/
  agent/              # go.mod, ADK entrypoint, internal/*
  infra/              # Terraform; locals.neuron = service id
```

## Scheduler-specific checks

| Check | Where |
|-------|--------|
| `serviceID` | Go const in `internal/scheduler/scheduler.go` |
| Cloud Tasks queue name | `{serviceID}-a2a-scheduler` in scheduler config |
| Spanner table prefix | `{project}_{serviceID}` (hyphens to underscores) |
| Scheduler env vars | Deployment config (Agent Engine `deployment_spec`, Cloud Run env) |
| gRPC interceptor | `schedulerservice.UnaryServerInterceptor()` on `grpc.NewServer` |
| Host mux registration | `mux.HandleGRPC(grpcServer)` in entrypoint |

## Hard rules

| Do | Do not |
|----|--------|
| Read `go.mod` and infra config from the agent you're editing | Substitute ids from another agent or templates |
| Confirm `serviceID` matches infra before wiring | Guess the service id from folder names |
| Ask the user if paths are unclear | Assume repo layout |

User corrections override everything.
