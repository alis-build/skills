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
| 4 | Add LRO application env vars to **both** `agent.tf` (`deployment_spec`) and `cloudrun.tf` (agent container); add Cloud Run-only `GOOGLE_CLOUD_*` vars | `references/templates/infra/agent.tf.deployment_spec-lro-envs.example`, `references/templates/infra/cloudrun-args.tf.snippet.example` |
| 5 | Confirm `neuron = local.neuron` in the module block matches Go `lroServiceID` | `references/workspace-lro.md` |

## Dual runtime: same agent image

The agent binary runs as **the same Docker image** on:

- `google_cloud_run_v2_service` (agent service) — sublaunchers via `command` / `args`
- `google_vertex_ai_reasoning_engine` → `spec.deployment_spec` — ADK via `agent_framework`; no sublauncher CLI args

**Contract:** every **application** env var the running process needs must appear in **both** places whenever you add or change env config. Keep names and values identical.

**Platform-injected on Reasoning Engine only (do not add to `deployment_spec`):**

- `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`, `GOOGLE_CLOUD_AGENT_ENGINE_ID` — Vertex AI / Agent Engine injects these automatically. These are the **only** auto-injected env vars.

**Cloud Run only (set in `cloudrun.tf`, not mirrored to `deployment_spec`):**

- The same three `GOOGLE_CLOUD_*` vars — Cloud Run does not auto-inject; set `GOOGLE_CLOUD_PROJECT = var.ALIS_PROJECT_NR`, `GOOGLE_CLOUD_LOCATION = var.ALIS_REGION`, `GOOGLE_CLOUD_AGENT_ENGINE_ID = google_vertex_ai_reasoning_engine.reasoning_engine.id`
- CLI `args` / Dockerfile CMD — Agent Engine does not use sublauncher args

**Both runtimes (mirror in the same change):**

- All application env vars including `ALIS_PROJECT_NR`, Spanner vars, service URLs, and any capability-specific vars from this skill

When this skill adds env vars, add matching `env` blocks to **both** `cloudrun.tf` (agent container) and `agent.tf` (`deployment_spec`) in the same change — except the three `GOOGLE_CLOUD_*` vars, which belong only in `cloudrun.tf`.

## Application env vars (both runtimes)

`go.alis.build/lro/v2` reads project, region, Spanner, and agent callback URL from the process environment. Add these under `spec.deployment_spec` in `agent.tf` (inside the existing `deployment_spec` block — keep any telemetry / `ALIS_OS_VERSION` env blocks already present) **and** mirror them on `google_cloud_run_v2_service` (agent container).

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

Templates:

- Agent Engine `deployment_spec`: **`references/templates/infra/agent.tf.deployment_spec-lro-envs.example`**
- Cloud Run: **`references/templates/infra/cloudrun-args.tf.snippet.example`**

## Module resources (summary)

- **Cloud Run invoker** — alis-build SA can invoke the agent service (operation task delivery).
- **Cloud Tasks queue** — `${neuron}-operations`.
- **Spanner table** — stores `google.longrunning.Operation` + resume state; 90-day TTL on `UpdateTime`.

## Deploy

The agent does **not** run `terraform apply` unless the user asks. After editing infra, ask the user to deploy via their Alis Build / DBD workflow.

## Verify after deploy

- Queue exists: `{neuron}-operations` in the agent region.
- Go `lro.NewFromEnv(ctx, serviceID)` uses the same `serviceID` as `local.neuron`.
- LRO application env vars (`ALIS_OS_PROJECT` through `AGENT_SERVICE_URL`) present in **both** `agent.tf` (`deployment_spec`) and `cloudrun.tf` (agent container).
- `GOOGLE_CLOUD_*` vars set on Cloud Run only — not in `deployment_spec` (Reasoning Engine injects them).
- Local dev may use emulators or env vars documented by `go.alis.build/lro/v2` — follow project conventions.
