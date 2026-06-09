# Infra: alis.lro.v2 module

LRO tools require Spanner operation storage and a Cloud Tasks queue. Provision via the `alis.lro.v2` Terraform module in the neuron’s **infra** directory.

## Prerequisites

- Agent Cloud Run service already defined (`google_cloud_run_v2_service.agent` or equivalent) — the LRO module references `agent_service_name`.
- Standard infra variables: `ALIS_OS_PROJECT`, `ALIS_REGION`, `ALIS_PROJECT_NR`, managed Spanner project/instance/database.
- `google_vertex_ai_reasoning_engine` (Agent Engine) with `spec.deployment_spec` — LRO runtime env vars must be set there (see below).
- `local.agent_service_url` in `variables.tf` / `locals.tf` (or equivalent) — used by `AGENT_SERVICE_URL` for Cloud Tasks callbacks.
- `google_project_service.environment` (or equivalent) if your stack uses `depends_on` for API enablement.

## Steps

| # | Action | Template |
|---|--------|----------|
| 1 | Copy `references/templates/infra/modules/alis.lro.v2/` → `infra/modules/alis.lro.v2/` | Full module |
| 2 | Add `module "alis_lro_v2"` block to `infra/main.tf` | `references/templates/infra/main.tf.snippet.example` |
| 3 | Add Spanner DB admin IAM for alis-build if missing | `references/templates/infra/spanner_role.tf.example` |
| 4 | Add LRO env vars to `google_vertex_ai_reasoning_engine` → `spec.deployment_spec` | `references/templates/infra/agent.tf.deployment_spec-lro-envs.example` |
| 5 | Confirm `neuron = local.neuron` in the module block matches Go `lroServiceID` | `references/workspace-lro.md` |

## Reasoning engine: LRO deployment env vars

`go.alis.build/lro/v2` reads project, region, Spanner, and agent callback URL from the process environment. When LRO tools run on **Vertex AI Agent Engine** (`google_vertex_ai_reasoning_engine`), those values must be injected under `spec.deployment_spec` (inside the existing `deployment_spec` block in `agent.tf` or equivalent — keep any telemetry / `ALIS_OS_VERSION` env blocks already present).

Add these `env` blocks (after existing env entries is fine):

```hcl
      env {
        name  = "ALIS_OS_PROJECT"
        value = var.ALIS_OS_PROJECT
      }
      env {
        name  = "ALIS_REGION"
        value = var.ALIS_REGION
      }
      env {
        name  = "ALIS_PROJECT_NR"
        value = var.ALIS_PROJECT_NR
      }
      env {
        name  = "ALIS_MANAGED_SPANNER_PROJECT"
        value = var.ALIS_MANAGED_SPANNER_PROJECT
      }
      env {
        name  = "ALIS_MANAGED_SPANNER_INSTANCE"
        value = var.ALIS_MANAGED_SPANNER_INSTANCE
      }
      env {
        name  = "ALIS_MANAGED_SPANNER_DB"
        value = var.ALIS_MANAGED_SPANNER_DB
      }
      env {
        name  = "AGENT_SERVICE_URL"
        value = local.agent_service_url
      }
```

**`AGENT_SERVICE_URL`** — Cloud Tasks delivers LRO resume HTTP to the agent Cloud Run service. Define `local.agent_service_url` (typically from `var.AGENT_SERVICE_URL` with a default Run URL pattern) in the same file or `variables.tf` locals used by Cloud Run.

**Cloud Run** — Mirror the same env vars on `google_cloud_run_v2_service` if the agent also runs LRO handlers there (common pattern: reasoning engine for ADK sessions, Cloud Run for gRPC/tools and task delivery).

## Module resources (summary)

- **Cloud Run invoker** — alis-build SA can invoke the agent service (operation task delivery).
- **Cloud Tasks queue** — `${neuron}-operations`.
- **Spanner table** — stores `google.longrunning.Operation` + resume state; 90-day TTL on `UpdateTime`.

## Deploy

The agent does **not** run `terraform apply` unless the user asks. After editing infra, ask the user to deploy via their Alis Build / DBD workflow.

## Verify after deploy

- Queue exists: `{neuron}-operations` in the agent region.
- Go `lro.NewFromEnv(ctx, serviceID)` uses the same `serviceID` as `local.neuron`.
- Reasoning engine `deployment_spec` includes all LRO env vars (`ALIS_OS_PROJECT` through `AGENT_SERVICE_URL`).
- Local dev may use emulators or env vars documented by `go.alis.build/lro/v2` — follow project conventions.
