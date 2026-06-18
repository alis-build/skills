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

## Deployment environment variables

The scheduler reads configuration from the process environment at startup. Set these on whatever runs the agent:

### Agent Engine (Vertex AI)

Add `env` blocks to `google_vertex_ai_reasoning_engine` → `spec.deployment_spec`:

```hcl
      env {
        name  = "ALIS_OS_PROJECT"
        value = var.project
      }
      env {
        name  = "ALIS_REGION"
        value = var.region
      }
      env {
        name  = "ALIS_MANAGED_SPANNER_PROJECT"
        value = var.spanner_project
      }
      env {
        name  = "ALIS_MANAGED_SPANNER_INSTANCE"
        value = var.spanner_instance
      }
      env {
        name  = "ALIS_MANAGED_SPANNER_DB"
        value = var.spanner_database
      }
      env {
        name  = "AGENT_SERVICE_URL"
        value = local.agent_service_url
      }
```

### Cloud Run

Mirror the same env vars on `google_cloud_run_v2_service` if the agent also runs scheduler handlers there.

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
- Deployment target includes all six scheduler env vars.
- Dockerfile CMD and Cloud Run args include `scheduler` and `-app_name=<info.AppName>` and match each other.
- Agent starts without `env.MustGet` panics for scheduler variables.
