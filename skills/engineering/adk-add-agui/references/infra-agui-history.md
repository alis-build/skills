# Infra: AG-UI thread history (Spanner)

AG-UI thread **metadata** (list, pin, unread, display names) is stored in Spanner. **Conversation message content** remains in ADK `SessionService` (Agent Engine in production) — `GET /agui/threads/{id}/messages` reads from sessions, not the history tables.

Provisioning requires **both** define (proto imports) **and** Terraform (history module). Skipping either leaves tables missing or misaligned.

## Proto imports (define)

The history and scheduler proto files ship in the **common protobundle** (`go.alis.build/common`) — authors **import**, not author, them locally.

Add both orphan imports to **any one** proto in the define package (typically `tools.proto`), even if nothing in the file references them:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Add **both** imports even when only AG-UI history is needed — the same rule applies for **add-scheduler**. The imports trigger define to provision Spanner tables; they are not RPC definitions in your service.

Ask the user to **run define** on the package (or neuron) after editing the proto.

## Prerequisites

- A GCP project with Spanner APIs enabled.
- A Spanner instance and database (can be shared with scheduler and other services).
- Agent deployment target (Cloud Run, Agent Engine, or local) with environment variables configured.
- `internal/info` (or equivalent central identity) with `NeuronId` matching `local.neuron` / `NEURON` in Terraform.

## Spanner tables

The history module provisions two tables. Names must match the runtime `SpannerStoreConfig` in the thread history service bootstrap:

| Table | Name pattern | Proto column |
|-------|--------------|--------------|
| Threads | `{ALIS_OS_PROJECT}_{NEURON}_Threads` | `alis.agui.history.v1.Thread` |
| UserThreadStates | `{ALIS_OS_PROJECT}_{NEURON}_UserThreadStates` | `alis.agui.history.v1.UserThreadState` |

Hyphens in `ALIS_OS_PROJECT` and `NEURON` become underscores. Example: project `my-os-project`, neuron `my-neuron-v1` → `my_os_project_my_neuron_v1_Threads`.

Go table prefix (in `history.go.example`):

```
tablePrefix = replace(ALIS_OS_PROJECT, "-", "_") + "_" + replace(NeuronId, "-", "_")
ThreadsTable          = tablePrefix + "_Threads"
UserThreadStatesTable = tablePrefix + "_UserThreadStates"
```

`NeuronId` in Go must equal `NEURON` passed to the Terraform module (typically `local.neuron` in `variables.tf`).

## Terraform module setup

| Step | Template |
|------|----------|
| Copy history module to `infra/modules/alis.agui.history.v1/` | `templates/infra/history-module.tf.example` |
| Add `module "alis_agui_history_v1"` block to `infra/main.tf` | `templates/infra/main.tf.snippet.example` |
| Confirm `local.neuron` matches `info.NeuronId` in Go | — |

The history module has no Cloud Run dependency — it only provisions Spanner tables. It typically `depends_on = [google_project_service.environment]` like other infra modules.

## Deployment environment variables

Set these on the agent Cloud Run service (or equivalent deployment target):

| Variable | Purpose |
|----------|---------|
| `ALIS_OS_PROJECT` | GCP project; used in Spanner table prefix |
| `ALIS_MANAGED_SPANNER_PROJECT` | Spanner host project |
| `ALIS_MANAGED_SPANNER_INSTANCE` | Spanner instance |
| `ALIS_MANAGED_SPANNER_DB` | Spanner database |
| `IDENTITY_SERVICE_URL` | IAM Users service — mux auth on `/agui/*` routes |
| `AGENT_SERVICE_URL` | Agent service URL (required on agent deployment) |

Template: **`templates/infra/cloudrun-args.tf.snippet.example`**

When **add-scheduler** is also wired, add scheduler env vars (`ALIS_REGION`, etc.) per **`add-scheduler`** → `references/infra-scheduler.md`.

### Local development

Set the variables in your shell or `.env` file. Point `IDENTITY_SERVICE_URL` and `AGENT_SERVICE_URL` at local or playground endpoints as appropriate.

## Launcher CLI args (Dockerfile + Cloud Run)

The ADK binary uses positional CLI args to activate sublaunchers. Add `agui` to args in **both** the Dockerfile CMD and Cloud Run Terraform config.

**Dockerfile CMD and Cloud Run `args` must match** — same sublauncher list in the same order. Only include sublaunchers the agent actually activates at runtime.

Template: **`templates/infra/cloudrun-args.tf.snippet.example`**

```
args = ["web", "-port", "8080", "agui"]
```

When scheduler is also wired, append `scheduler` and `-app_name=<AppName>` (must match `info.AppName` / `llmagent.Config.Name`). See **add-scheduler** for scheduler CLI requirements.

## Browser UI (add-console)

This skill wires the **agent-side** AG-UI endpoint. For a browser chat UI, BFF reverse-proxy, gRPC-Web `ThreadService` clients, or load balancer setup, use **add-console** after AG-UI wiring is in place. A console BFF proxies `/agui/*` to the agent — `WithCORS` on the agent is usually unnecessary when traffic is same-origin via the BFF.

## Deploy

The agent does **not** run `terraform apply` or deploy commands. After editing infra, ask the user to deploy via their workflow (Alis Build DBD, `terraform apply`, or CI/CD).

## Verify after deploy

- Spanner tables `{prefix}_Threads` and `{prefix}_UserThreadStates` exist.
- `info.NeuronId` in Go matches `local.neuron` / module `NEURON`.
- Table names in Go match Terraform naming convention.
- Deployment includes Spanner, `IDENTITY_SERVICE_URL`, and `AGENT_SERVICE_URL` env vars.
- Dockerfile CMD and Cloud Run args both include `agui` and match each other.
- Proto imports present in define; user ran define.
- `WithThreadService` + `WithGRPCRegistrar` wired; agent starts without history initialization errors.
