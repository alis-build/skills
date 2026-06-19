# Infra: A2A scheduler (Spanner + Cloud Tasks)

The A2A scheduler extension requires Spanner for schedule state storage and a Cloud Tasks queue for delivery. These resources must be provisioned before the scheduler can start.

## Proto imports (define)

Before infra apply, add both imports below to **any one** proto in the define package (typically `tools.proto`), even if unused — define provisions the Spanner tables from these imports:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Ask the user to run define on the package or neuron after editing the proto. See **Proto imports for Spanner tables** in `SKILL.md`.

## Prerequisites

- A GCP project with Cloud Tasks and Spanner APIs enabled.
- A Spanner instance and database (can be shared with other services).
- Agent deployment target (Cloud Run, Agent Engine, or local) with environment variables configured.

## Resources

### Cloud Tasks queue

The scheduler delivers scheduled invocations via Cloud Tasks. The queue name must follow the pattern `{NeuronId}-a2a-scheduler` (from `info.NeuronId`):

```hcl
resource "google_cloud_tasks_queue" "a2a_scheduler" {
  name     = "${local.neuron}-a2a-scheduler"
  location = var.region
  project  = var.project
}
```

If not using Terraform, create the queue manually or via `gcloud`:

```bash
gcloud tasks queues create {NeuronId}-a2a-scheduler \
  --location={region} \
  --project={project}
```

### Spanner table

The scheduler stores cron state in a Spanner table. The table name follows the pattern `{project}_{NeuronId}_Crons` (hyphens replaced with underscores). A full Terraform module with the table schema is at **`templates/infra/scheduler-module.tf.example`**.

The table uses `PROTO` typed columns for cron and policy storage. The Spanner database must exist and the service account must have appropriate permissions.

### Service account permissions

The service account running the agent needs:
- **Cloud Tasks enqueuer** — to create scheduled task deliveries.
- **Spanner database user** — to read/write schedule state.
- **Cloud Run invoker** (or equivalent) — so Cloud Tasks can deliver scheduled invocations to the agent service.

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

The scheduler reads configuration from the process environment at startup:

| Variable | Purpose |
|----------|---------|
| `ALIS_OS_PROJECT` | GCP project |
| `ALIS_REGION` | GCP region |
| `ALIS_PROJECT_NR` | GCP project number |
| `ALIS_MANAGED_SPANNER_PROJECT` | Spanner host project |
| `ALIS_MANAGED_SPANNER_INSTANCE` | Spanner instance |
| `ALIS_MANAGED_SPANNER_DB` | Spanner database |
| `AGENT_SERVICE_URL` | Cloud Run agent URL — Cloud Tasks delivers scheduled invocations here |

Templates:

- Cloud Run: **`templates/infra/cloudrun-args.tf.snippet.example`**
- Agent Engine `deployment_spec`: **`templates/infra/agent.tf.deployment_spec-envs.example`**

**`AGENT_SERVICE_URL`** — must point at the **Cloud Run** agent service URL. The scheduler Terraform module passes `AGENT_SERVICE_NAME = google_cloud_run_v2_service.agent.name` so Cloud Tasks invokes the Cloud Run service, not Agent Engine.

### Local development

Set the variables in your shell or `.env` file. Point `AGENT_SERVICE_URL` to your local server (e.g. `http://localhost:8080`).

## Alis Build projects

In Alis Build infrastructure, the standard variable names are:
- `var.ALIS_OS_PROJECT`, `var.ALIS_REGION`, `var.ALIS_PROJECT_NR`
- `var.ALIS_MANAGED_SPANNER_PROJECT`, `var.ALIS_MANAGED_SPANNER_INSTANCE`, `var.ALIS_MANAGED_SPANNER_DB`
- `local.agent_service_url` (derived from Cloud Run service URL)

`local.neuron` in `variables.tf` must match `info.NeuronId` in Go (hyphenated `focus_neuron_id`). The Cloud Tasks queue is `{NeuronId}-a2a-scheduler`. The service account pattern is `alis-build@{project}.iam.gserviceaccount.com`.

## Launcher CLI args (Dockerfile + Cloud Run)

The ADK binary uses positional CLI args to activate each sublauncher. Add `scheduler` and `-app_name=<adkAppName>` to the args in both the **Dockerfile** and the **Cloud Run** Terraform config.

Template: **`templates/infra/cloudrun-args.tf.snippet.example`**

```
args = ["web", "-port", "8080", "webui", "-api_server_address=/api", "api", "lro", "scheduler", "-app_name=my.neuron.v1"]
```

The `-app_name` flag must match `info.AppName` / `llmagent.Config.Name`. Without `scheduler` in the args, the sublauncher won't activate even though it's registered in Go code.

## Terraform module setup

| Step | Template |
|------|----------|
| Copy scheduler module to `infra/modules/alis.a2a.extension.scheduler.v1/` | `templates/infra/scheduler-module.tf.example` |
| Add `module` block to `infra/main.tf` | `templates/infra/main.tf.snippet.example` |
| Confirm `neuron` variable matches `info.NeuronId` in Go | — |

## Deploy

The agent does **not** run `terraform apply` or deploy commands. After editing infra, ask the user to deploy via their workflow (Alis Build DBD, `terraform apply`, or CI/CD).

## Verify after deploy

- Queue exists: `{NeuronId}-a2a-scheduler` in the agent region.
- Spanner table `{project}_{NeuronId}_Crons` exists.
- `info.NeuronId` in Go matches `local.neuron` in infra.
- Application env vars (`ALIS_OS_PROJECT`, `ALIS_REGION`, `ALIS_PROJECT_NR`, Spanner, `AGENT_SERVICE_URL`) present in **both** `cloudrun.tf` (agent container) and `agent.tf` (`deployment_spec`).
- `GOOGLE_CLOUD_*` vars set on Cloud Run only — not in `deployment_spec` (Reasoning Engine injects them).
- Dockerfile CMD and Cloud Run args include `scheduler` and `-app_name=<info.AppName>` and match each other.
- Agent starts without `env.MustGet` panics for scheduler variables.
