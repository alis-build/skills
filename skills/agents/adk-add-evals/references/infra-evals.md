# Evals infrastructure (GCS + deployment)

Terraform and deployment for ADK evals GCS storage. No define/proto step.

Host pattern affects **activation only** — see **`references/wiring-patterns.md`**. GCS bucket and env vars apply to both patterns.

## GCS bucket

Create a bucket per neuron for eval sets and results when using GCS storage mode.

**Naming:** `{NeuronId}-agent-evals` where `NeuronId` is the hyphenated neuron id (matches `focus_neuron_id` / `local.neuron` in infra).

Template: `references/templates/infra/storage-bucket.tf.example`

```hcl
resource "google_storage_bucket" "agent-evals" {
  project       = var.ALIS_OS_PROJECT
  name          = "${local.neuron}-agent-evals"
  location      = var.ALIS_REGION
  force_destroy = true

  uniform_bucket_level_access = true
}
```

Wire the bucket in `infra/` (standalone file or existing storage module). Ensure the Cloud Run service account can read/write objects (typically `roles/storage.objectAdmin` on the bucket for `alis-build@${ALIS_OS_PROJECT}.iam.gserviceaccount.com` or your agent's service account).

## Environment variable

Set on the agent Cloud Run container (and mirror on Agent Engine `deployment_spec` when the same image runs there):

| Variable | Value | Purpose |
|----------|-------|---------|
| `AGENT_EVALS_BUCKET` | `google_storage_bucket.agent-evals.name` | Bucket name only — Go builds `gs://` URI |

In Go, read at startup:

```go
bucket := os.Getenv("AGENT_EVALS_BUCKET")
if bucket != "" {
    webevals.WithEvalStorageURI("gs://" + bucket)
}
```

Do not set `AGENT_EVALS_BUCKET` in `deployment_spec` without also setting it on Cloud Run when both runtimes use the same image.

## Vertex / Gemini env vars (judge client)

The metric registry judge uses the same Vertex project/region as the agent. These are usually already present when Agent Engine or Vertex session services are wired:

| Variable | Purpose |
|----------|---------|
| `GOOGLE_CLOUD_PROJECT` or `ALIS_OS_PROJECT` | Vertex project for judge |
| `GOOGLE_CLOUD_LOCATION` or `ALIS_REGION` | Vertex region for judge |

On Cloud Run, `GOOGLE_CLOUD_*` vars are set explicitly. On Agent Engine, Reasoning Engine injects `GOOGLE_CLOUD_*` automatically — do not duplicate them in `deployment_spec`.

## Cloud Run args (Pattern A — launcher stack only)

Append `evals` to the existing sublauncher CLI list. **Dockerfile CMD and Cloud Run args must match.**

**Pattern B (direct `SetupHostRoutes`):** do **not** add `evals` to CLI args — routes register at startup.

Template (Pattern A): `references/templates/infra/cloudrun-args.tf.snippet.example`

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "webui", "-api_server_address=/api", "api", "agui", "evals"]

  env {
    name  = "AGENT_EVALS_BUCKET"
    value = google_storage_bucket.agent-evals.name
  }
  # ... other application env vars ...
}
```

When other sublaunchers are wired (lro, scheduler, etc.), preserve their keywords and flags — only append `evals`.

### Local / on-disk storage (opt-in only)

Use **`WithAgentsDir`** (Pattern B) or CLI **`-agents_dir`** (Pattern A) **only when the user explicitly asks** for local on-disk eval storage.

**Default for local dev:** set `AGENT_EVALS_BUCKET` in `.env` / launch config and use `WithEvalStorageURI` — same as deployed. Prefer GCS over disk unless the user requests otherwise.

## No Spanner / define required

Unlike **add-agui** or **add-scheduler**, evals does not need Spanner proto imports or Terraform modules beyond the GCS bucket. Eval sets and results live in GCS by default; on-disk storage is opt-in when the user asks for it.

## Deployment checklist

- [ ] GCS bucket `{NeuronId}-agent-evals` in `infra/` (extend existing storage tf if present)
- [ ] Service account object read/write on bucket
- [ ] `AGENT_EVALS_BUCKET` on Cloud Run (+ `deployment_spec` if same image on Agent Engine)
- [ ] Go: `WithEvalStorageURI("gs://" + bucket)` from `AGENT_EVALS_BUCKET` (standard — not `WithAgentsDir` unless user asked)
- [ ] `AGENT_EVALS_BUCKET` in local `.env` / launch config when dev uses GCS
- [ ] Pattern A: `evals` in Dockerfile CMD and Cloud Run args (matching)
- [ ] Pattern B: no `evals` CLI arg; `SetupHostRoutes` at startup
- [ ] `local.neuron` matches app/neuron id used for bucket naming
