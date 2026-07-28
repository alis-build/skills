# Evals launcher options (`go.alis.build/adk/launchers/evals`)

`webevals.NewLauncher(opts...)` creates the evals sublauncher. Mount it via **Pattern A** (inside `launchersweb.NewLauncher`) or **Pattern B** (`HostRouteSetup.SetupHostRoutes`) — see **`references/wiring-patterns.md`**.

CLI keyword `evals` applies to **Pattern A only** (activates sublauncher at `Execute` time).

HTTP routes mirror [Evaluate agents](https://adk.dev/evaluate/). See **`SKILL.md`** → Orientation.

Read pinned source: `go list -m go.alis.build/adk/launchers` → `.../evals/` in module cache.

## Trigger words → option

| User says (examples) | Option / action | Pattern |
|----------------------|-----------------|---------|
| eval sets, run eval, dev eval API | Register routes (A: sublauncher + CLI `evals`; B: `SetupHostRoutes`) | A or B |
| LLM judge, rubric metrics | `WithMetricRegistry` + judge client | both |
| GCS storage, cloud eval results | `WithEvalStorageURI` from `AGENT_EVALS_BUCKET` | both (default) |
| local eval files on disk | `WithAgentsDir` / `-agents_dir` | both (user asked only) |
| match api path prefix | `WithPathPrefix` / `-path_prefix` | both |

## Options reference

### `WithMetricRegistry(r *metrics.Registry)`

Metric evaluators used when running evals. Default `metrics.DefaultRegistry` leaves `JudgeClient` nil — LLM-judge metrics return `NOT_EVALUATED`. Wire a registry with `JudgeClient` set (see `references/templates/evals-metrics-registry.go.example`).

### `WithEvalStorageURI(uri string)`

GCS storage for eval sets and results. URI must be `gs://bucket` (bucket name only after scheme). Overrides local storage when set in Go or via `-eval_storage_uri`.

At startup the launcher validates bucket access (15s timeout). Misconfigured URIs fail launcher startup rather than silently degrading.

### `WithAgentsDir(dir string)`

Local on-disk storage at `{dir}/{appName}/{evalSetId}.evalset.json`. **Use only when the user explicitly requests local disk storage** — default is `WithEvalStorageURI` + `AGENT_EVALS_BUCKET` (including local dev via `.env`).

### `WithPathPrefix(prefix string)`

HTTP prefix before `/dev/apps/...`. Default `/api`. Must match webui `-api_server_address=/api` and api sublauncher `-path_prefix`.

### `WithUserSimulatorProvider(p simulation.UserSimulatorProvider)`

Selects user simulator implementation during multi-turn eval inference. Default is empty provider (static simulators only unless configured).

### `WithEvalSetsManager(m)` / `WithEvalSetResultsManager(m)`

Override storage backends (e.g. in-memory for tests). When both are set, URI and agents_dir are ignored for that manager.

## CLI flags (after `evals` keyword)

| Flag | Default | Purpose |
|------|---------|---------|
| `-path_prefix` | `/api` | URL prefix before `/dev/apps` |
| `-agents_dir` | (empty) | Local eval storage root |
| `-eval_storage_uri` | (empty) | GCS URI `gs://bucket` |

Example (Pattern A, user requested local disk only):

```
web -port 8080 webui -api_server_address=/api api evals -agents_dir=internal/evals
```

Standard install uses GCS — no `-agents_dir`.

Example deployed (GCS set in Go via env — no extra flags needed):

```
web -port 8080 webui -api_server_address=/api api agui evals
```

## HTTP routes

Routes mount at `{pathPrefix}/dev/apps/{app_name}/...` where `{app_name}` is the ADK app name (`AppName`, periods).

Canonical paths (hyphens):

```
POST   /api/dev/apps/{app}/eval-sets
GET    /api/dev/apps/{app}/eval-sets
GET    /api/dev/apps/{app}/eval-sets/{id}
DELETE /api/dev/apps/{app}/eval-sets/{id}
POST   /api/dev/apps/{app}/eval-sets/{id}/add-session
POST   /api/dev/apps/{app}/eval-sets/{id}/run
GET    /api/dev/apps/{app}/eval-sets/{id}/eval-cases
GET    /api/dev/apps/{app}/eval-sets/{id}/eval-cases/{caseId}
PUT    /api/dev/apps/{app}/eval-sets/{id}/eval-cases/{caseId}
DELETE /api/dev/apps/{app}/eval-sets/{id}/eval-cases/{caseId}
GET    /api/dev/apps/{app}/eval-results
GET    /api/dev/apps/{app}/eval-results/{resultId}
GET    /api/dev/apps/{app}/metrics-info
```

Legacy underscore paths (`eval_sets`, `run_eval`, etc.) remain for adk-web compatibility.

## Authentication

Eval routes do **not** enforce caller identity. Access control is delegated to a trusted upstream (gateway or BFF). Do not expose this sublauncher on the public internet without that boundary. Package docs describe this as dev-only; production deployments may still enable it behind auth.

## Storage precedence

Package resolution order (when wiring):

1. If both `WithEvalSetsManager` and `WithEvalSetResultsManager` are set → use those.
2. Else if `evalStorageURI` is non-empty (Go option or CLI) → GCS.
3. Else if `agentsDir` is non-empty → local disk.
4. Else → startup error: `agents_dir is required for local eval storage`.

**Skill default:** always wire **`WithEvalStorageURI`** from `AGENT_EVALS_BUCKET` (including local dev via `.env`). Use **`WithAgentsDir`** / **`-agents_dir`** only when the user explicitly requests local disk — do not rely on step 3 as an implicit fallback.

**Pitfall:** Setting `WithEvalStorageURI` in Go while also passing `-agents_dir` on the CLI does not use local storage — GCS wins.

## Prerequisites from launcher config

`SetupHostRoutes` requires:

- `config.SessionService` — for add-session and inference
- `config.AgentLoader` — for agent runs during eval inference

These come from the standard ADK launcher config wired before `l.Execute`.
