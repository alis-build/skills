---
name: adk-add-evals
description: >
  Use this skill when the user wants ADK agent evaluations, eval sets, LLM-as-judge metrics,
  scoring agent responses, the evals web sublauncher, dev eval HTTP API, or wiring eval metrics
  — even if they do not say evals launcher. Wires go.alis.build/adk/launchers/evals with metric
  registry and GCS eval storage via WithEvalStorageURI. Branches on ADK-Go version (pre-v2 vs v2) and on host
  pattern (launcher stack vs direct SetupHostRoutes). Not for harness-eval external suites,
  platform evals neurons, add-agui, or add-scheduler.
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations
---

# Add ADK evals

Exposes the ADK dev eval HTTP API (eval sets, run eval, metrics-info) via `go.alis.build/adk/launchers/evals`, with parity to adk-python DevServer eval endpoints.

This is a **capability-based** skill: define contracts, discover what the repo already has, extend in place. Templates are greenfield references only — not canonical paths. Do not treat `main.go` or `internal/evals/metrics` as required locations; infer placement from the working directory's patterns (where agui/scheduler/model setup already live).

**Workflow:** Discover → extend or create → wire → verify **contract** (not folder names).

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads
`alis.context.requires` below to decide which context fields to include; the block carries
**only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **`<alis-runtime-context>`** — use injected context fields verbatim.
2. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)`. Never invent environment IDs.
3. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; list packages and grep discovery signals.
4. **Ask user** — smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after runtime context) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | Used to derive `NeuronId` and GCS bucket name |
| Neuron build root | `workstations` | Use the focused workstation's `build_repos` entry |
| Infra directory | `workstations` | Derive as `<build_repos entry>/infra` |

Then read **`references/workspace-evals.md`** and **`references/wiring-patterns.md`**.

## Repo reconnaissance (before any edit)

1. Read **`go.mod`** — ADK version, launchers version, module path.
2. List packages — especially `internal/`, agent bootstrap, infra.
3. Grep capability discovery signals (below).
4. Read the server entrypoint and any `Setup*Routes` or launcher wiring — determine **host pattern** (see **`references/wiring-patterns.md`**).
5. Find where peer concerns live (Gemini client, agui, scheduler) and **place evals code beside them**, not in skill-default paths.

## When to use

See the skill **description**. Delivers: version-aligned launchers dep, judge-backed metric registry, evals route registration, GCS storage (deployed), activation appropriate to host pattern.

| User intent | Capability |
| ----------- | ---------- |
| Run eval sets, score agent, dev eval API | Evals route registration |
| LLM judge, rubric scoring | Metric registry + judge client |
| Cloud eval persistence | GCS via `WithEvalStorageURI` + `AGENT_EVALS_BUCKET` |
| Local eval files on disk | `WithAgentsDir` — **only when user explicitly asks** |
| Understand eval design | [adk.dev/evaluate](https://adk.dev/evaluate/) — see Orientation |

## Orientation: ADK evaluation concepts

For **why** and **what** to evaluate, see [Evaluate agents](https://adk.dev/evaluate/). Use adk.dev for eval case design and metric choice; use this skill for Go wiring on Alis Build.

On Alis Build, the dev eval API comes from **`webevals.NewLauncher`** — not stock `adk web` alone. Some adk.dev sections are Python-only (`adk eval` CLI, RecordingsPlugin); eval set schema and web UI workflow still apply.

## When not to use

| Need | Use instead |
|------|-------------|
| External harness suites (`.evals/` folders) | Separate workflow |
| Platform evals service neuron | Out of scope |
| AG-UI / scheduler / tools | **add-agui**, **add-scheduler**, **add-tool**, **add-lro** |

## Prerequisites

- ADK agent with `SessionService` and an agent loadable via `AgentLoader` (or equivalent in `launcher.Config` / `LauncherConfig()`).
- One of two **host patterns** (discover which — do not assume launcher stack):
  - **Launcher stack:** `universal.NewLauncher` + `go.alis.build/adk/launchers/web`
  - **Direct routes:** `mux.ListenAndServe` + `SetupHostRoutes` (like existing `SetupAGUIRoutes`)
- Vertex/Gemini credentials for judge client.
- User can install/upgrade deps in `go.mod`.

## ADK version branching

Read **`go.mod`** before any import edit.

| `go.alis.build/adk/launchers` | ADK-Go |
| ----------------------------- | ------ |
| **pre v1.0.0** (v0.x) | pre-v2 (`google.golang.org/adk`) |
| **v1.0.0+** (v1.x) | v2.0.0+ (`google.golang.org/adk/v2`) |

Evals minimum: **v0.3.10+** / **v1.0.10+**. Do not mix launchers major line with ADK major line.

## Capabilities

For each: **discover → extend or create → wire → verify contract**.

### Capability: ADK version + launchers pin

| | |
|-|-|
| **Contract** | `go.mod` launchers major line matches ADK; evals min versions satisfied. |
| **Discovery signals** | `google.golang.org/adk/v2`, `google.golang.org/adk`, `go.alis.build/adk/launchers` |
| **Wire points** | `go.mod` require block |
| **Greenfield default** | v1.0.10+ (ADK v2) or v0.3.10+ (pre-v2) |

### Capability: Host pattern (evals route registration)

Two valid patterns — **discover which the repo uses**; see **`references/wiring-patterns.md`**.

#### Pattern A — Launcher stack

| | |
|-|-|
| **Contract** | `webevals.NewLauncher(...)` registered inside existing `launchersweb.NewLauncher(...)` alongside peer sublaunchers. **`WithEvalStorageURI("gs://" + os.Getenv("AGENT_EVALS_BUCKET"))`** in Go (standard). CLI keyword `evals` in Dockerfile CMD and Cloud Run args (matching). `WithAgentsDir` only if user requests local disk storage. |
| **Discovery signals** | `universal.NewLauncher`, `launchersweb.NewLauncher`, `l.Execute`, sibling `webagui`/`webscheduler`/`weblro` inside `NewLauncher` |
| **Wire points** | Same file/call as peer sublaunchers — often entrypoint, not necessarily `main.go` |
| **Greenfield default** | `references/templates/evals-launcher-stack.go.example` |

If stock `google.golang.org/adk/cmd/launcher/web` is the web host, migrate to `go.alis.build/adk/launchers/web` before adding evals (same rule as **add-agui** / **add-scheduler**).

#### Pattern B — Direct host routes

| | |
|-|-|
| **Contract** | `webevals.NewLauncher(...)` → assert `launchersweb.HostRouteSetup` → `SetupHostRoutes(launcherConfig)`. Invoked from server startup next to peer `Setup*Routes`. **`WithEvalStorageURI`** from `AGENT_EVALS_BUCKET` (standard). **No** `evals` CLI keyword. `WithAgentsDir` only if user requests local disk storage. |
| **Discovery signals** | `SetupHostRoutes`, `HostRouteSetup`, `SetupAGUIRoutes`, `SetupSchedulerRoutes`, `mux.ListenAndServe`, `LauncherConfig()` |
| **Wire points** | New or extended `Setup*Routes` beside agui/scheduler setup; called from server `main` with peers |
| **Greenfield default** | `references/templates/evals-direct-routes.go.example` |

Reuse existing `LauncherConfig()` — do not duplicate session/agent wiring.

### Capability: Judge client bootstrap

| | |
|-|-|
| **Contract** | Dedicated `genai.NewClient` for eval judge, separate from agent model client. Fail fast at startup on misconfiguration. Same Vertex project/region as agent. |
| **Discovery signals** | Existing `genai.ClientConfig`, `gemini.NewModel`, env reads for `GOOGLE_CLOUD_PROJECT` / `ALIS_OS_PROJECT` |
| **Wire points** | Next to existing model/client bootstrap — wherever the repo already initializes Gemini |
| **Greenfield default** | Inline in server bootstrap or agent `init` — follow repo convention |

### Capability: Metric registry with judge

| | |
|-|-|
| **Contract** | Registry with `JudgeClient` wired via `SetConfig` on `metrics.NewDefaultRegistry()`. Exported constructor accepting `*genai.Client` + default model name. |
| **Discovery signals** | `JudgeClient`, `SetConfig`, `launchers/evals/evaluation/metrics`, `NewDefaultRegistry` |
| **Wire points** | Package that owns eval/metrics concerns; passed to `webevals.WithMetricRegistry` at `NewLauncher` site |
| **Greenfield default** | `internal/evals/metrics` — see `references/templates/evals-metrics-registry.go.example` |

Without judge client, LLM-judge metrics return `NOT_EVALUATED`. See **`references/metrics-guide.md`**.

### Capability: GCS eval storage

| | |
|-|-|
| **Contract** | Bucket `{NeuronId}-agent-evals`; env `AGENT_EVALS_BUCKET`; service account object access. Go always wires `WithEvalStorageURI("gs://" + bucket)` when env is set — **default for all environments** including local dev (via `.env`). |
| **Discovery signals** | `google_storage_bucket`, `AGENT_EVALS_BUCKET`, existing storage terraform |
| **Wire points** | `infra/` — extend existing storage file or add bucket resource; Cloud Run + `deployment_spec` env |
| **Greenfield default** | `references/templates/infra/storage-bucket.tf.example` |

No define/proto step.

### Capability: Activation (pattern-dependent)

| | |
|-|-|
| **Contract (A)** | `evals` in Dockerfile CMD and Cloud Run args; must match. |
| **Contract (B)** | Routes live at startup via `SetupHostRoutes`; no CLI change. |
| **Discovery signals** | Container `args`, `SetupHostRoutes` vs `l.Execute` |
| **Wire points** | Terraform/Dockerfile (A) or server startup only (B) |

## Steps

| # | Action |
|---|--------|
| 0 | **Recon** — `go.mod`, list packages, grep signals, read entrypoint and peer wiring (agui/scheduler/model) |
| 1 | **Host pattern** — A (launcher stack) or B (direct routes); read **`references/wiring-patterns.md`** |
| 2 | **Version pin** — align launchers ↔ ADK; evals minimums; ask user to install/upgrade |
| 3 | **Judge client** — extend existing Gemini bootstrap with separate judge client |
| 4 | **Metric registry** — extend existing or create one package; wire `JudgeClient` |
| 5 | **Evals routes** — Pattern A: add to `web.NewLauncher(...)`; Pattern B: add `SetupEvalsRoutes` + call from server main |
| 6 | **Infra** — GCS + `AGENT_EVALS_BUCKET` — **`references/infra-evals.md`** |
| 7 | **Activation** — Pattern A: append `evals` to CLI args; Pattern B: skip CLI |
| 8 | **Verify** — `go build ./...`; optional `GET /api/dev/apps/{AppName}/metrics-info` |

## Storage

**Default: GCS via `WithEvalStorageURI`.** Wire `WithEvalStorageURI("gs://" + os.Getenv("AGENT_EVALS_BUCKET"))` in `NewLauncher` opts whenever the env var is set. Standard install includes the GCS bucket, `AGENT_EVALS_BUCKET` on Cloud Run, and the same env in local `.env` / launch config so dev and prod share GCS storage.

**Do not use `WithAgentsDir` or CLI `-agents_dir` unless the user explicitly asks for local on-disk eval storage.** Local GCS (env var pointing at the dev bucket) is preferred over local disk.

| | Pattern A | Pattern B |
| --- | --------- | --------- |
| **Standard** | `WithEvalStorageURI` in Go; CLI `evals` only (no `-agents_dir`) | `WithEvalStorageURI` in Go |
| **Opt-in local disk** (user asked) | CLI: `evals -agents_dir=...` and omit `WithEvalStorageURI` | Go: `WithAgentsDir(...)` instead of GCS |

If both `WithEvalStorageURI` and `-agents_dir` are set, GCS wins — do not mix unless intentional.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `AGENT_EVALS_BUCKET` | Bucket name (no `gs://` prefix) |
| `GOOGLE_CLOUD_PROJECT` / `ALIS_OS_PROJECT` | Vertex project for judge |
| `GOOGLE_CLOUD_LOCATION` / `ALIS_REGION` | Vertex region for judge |

## Security

Eval routes do not enforce caller identity. Use gateway/BFF auth; do not expose publicly without a boundary.

## Verification (contracts, not paths)

- [ ] Launchers major line ↔ ADK major line; evals min versions
- [ ] Host pattern correctly applied (A or B)
- [ ] Separate judge `genai.Client`; registry with `JudgeClient`
- [ ] Evals HTTP routes registered (`webevals.NewLauncher` + stack or `SetupHostRoutes`)
- [ ] Pattern A: `evals` in Dockerfile CMD and Cloud Run args (matching)
- [ ] Pattern B: setup called at startup; **no** `evals` CLI arg required
- [ ] `WithEvalStorageURI` wired from `AGENT_EVALS_BUCKET` (standard — not `WithAgentsDir` unless user asked)
- [ ] GCS bucket + `AGENT_EVALS_BUCKET` env (Cloud Run + local `.env` when dev uses GCS)
- [ ] App name matches eval URL `{app_name}`
- [ ] `go build ./...` passes

## Pitfalls

- **Template-driven placement** — copying skill paths into repos with different layouts
- **Wrong host pattern** — adding `evals` CLI to direct-route agents, or `SetupHostRoutes` on launcher-stack agents
- **Migrating host pattern** without user request
- Mixing launchers v0.x / v1.x with wrong ADK line
- Default registry without judge → `NOT_EVALUATED`
- Defaulting to `WithAgentsDir` or `-agents_dir` without user request
- `WithEvalStorageURI` in Go + expecting `-agents_dir` to override
- Sharing judge client with agent model
- Vertex metrics without `VertexEvalClient`
- Pattern A: missing `evals` CLI keyword

## References

| File | Purpose |
| ---- | ------- |
| `references/wiring-patterns.md` | Pattern A vs B — primary wiring guide |
| `references/workspace-evals.md` | Path discovery, version detection |
| `references/infra-evals.md` | GCS, env vars, deployment by pattern |
| `references/launcher-options.md` | Options, routes, CLI flags |
| `references/metrics-guide.md` | Metric catalog, judge vs Vertex |
| `references/templates/*.example` | Greenfield references only — not canonical layout |
