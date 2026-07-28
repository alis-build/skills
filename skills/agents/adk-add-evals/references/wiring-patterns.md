# Evals wiring patterns

The evals sublauncher (`go.alis.build/adk/launchers/evals`) exposes the same HTTP API regardless of how it is mounted. **Discover which host pattern the agent already uses** and extend it — do not migrate layouts or invent new file names to match skill templates.

Both patterns require:

- `SessionService` and `AgentLoader` on the config passed to `SetupHostRoutes` or `Execute`
- `webevals.WithMetricRegistry` with a judge-backed registry
- Storage via `WithEvalStorageURI` from `AGENT_EVALS_BUCKET` (default). `WithAgentsDir` only when user explicitly requests local disk — see **`SKILL.md`** → Storage.
- ADK app name (`llmagent.Config.Name` or equivalent) matching `{app_name}` in eval URLs

See **`references/launcher-options.md`** for options and routes.

---

## Pattern A — Launcher stack

**When to use:** Agent already runs via `universal.NewLauncher` + `go.alis.build/adk/launchers/web.NewLauncher` + `l.Execute(ctx, config, os.Args[1:])`.

**Discovery signals:**

- `universal.NewLauncher`
- `launchersweb.NewLauncher` or `web.NewLauncher` from `go.alis.build/adk/launchers/web`
- `l.Execute` with `os.Args`
- Other Alis sublaunchers as arguments inside `web.NewLauncher(...)` (agui, scheduler, lro)

**Contract:**

1. Add `webevals.NewLauncher(...)` as another child inside the existing `web.NewLauncher(...)` call — same position style as sibling sublaunchers already present.
2. Pass `evals` CLI keyword in Dockerfile CMD and Cloud Run args (must match).
3. Wire `WithEvalStorageURI("gs://" + os.Getenv("AGENT_EVALS_BUCKET"))` in `NewLauncher` opts — standard. Do not add `-agents_dir` unless user asks for local disk.
4. Optional CLI flags after `evals`: `-eval_storage_uri`, `-path_prefix` (prefer env + Go option over CLI for storage URI).

**Wire points:** Wherever sibling sublaunchers are registered (often `main.go`, but follow the repo — could be a dedicated launcher/bootstrap file).

**Activation:** Runtime — sublauncher activates only when `evals` appears in CLI args.

Greenfield reference: `references/templates/evals-launcher-stack.go.example`

---

## Pattern B — Direct host routes

**When to use:** Agent serves HTTP via `go.alis.build/mux.ListenAndServe` (or similar) and registers Alis sublaunchers through `HostRouteSetup.SetupHostRoutes`, not through `universal.NewLauncher`.

**Discovery signals:**

- `mux.ListenAndServe`
- `SetupHostRoutes`
- `launchersweb.HostRouteSetup`
- `SetupAGUIRoutes`, `SetupSchedulerRoutes`, or similar `Setup*Routes` helpers
- `LauncherConfig()` (or equivalent) mapping `runner.Config` → `launcher.Config`
- **Absence** of `l.Execute(..., os.Args[1:])` for the web stack

**Contract:**

1. Create or extend a `SetupEvalsRoutes` (or match existing naming: `Setup*Routes`) function alongside peer setup functions.
2. `l := webevals.NewLauncher(opts...)`
3. Assert `l.(launchersweb.HostRouteSetup)` and call `SetupHostRoutes(launcherConfig)` with the same config adapter peer sublaunchers use.
4. Call the setup function from the server entrypoint next to peer `Setup*Routes` calls.
5. Wire `WithEvalStorageURI("gs://" + os.Getenv("AGENT_EVALS_BUCKET"))` in `NewLauncher` opts — standard. Use `WithAgentsDir` only if user explicitly requests local disk. **No** `evals` CLI keyword.

**Wire points:**

- Setup function: follow where `SetupAGUIRoutes` / `SetupSchedulerRoutes` live (e.g. `agent/agui.go`, `agent/scheduler.go`, package `agent`).
- Judge client + registry: follow where Vertex/Gemini clients are created (often agent bootstrap `init`, config package, or next to model setup).
- Server entrypoint: wherever peer setup functions are invoked (e.g. `server.go`, `main.go`).

**Activation:** Startup — routes register when `SetupHostRoutes` runs.

Greenfield reference: `references/templates/evals-direct-routes.go.example`

---

## Choosing a pattern

| Signal | Pattern |
| ------ | ------- |
| `SetupAGUIRoutes` + `SetupHostRoutes` already exist | **B** — add `SetupEvalsRoutes` the same way |
| `webscheduler.NewLauncher` inside `web.NewLauncher(...)` | **A** — add `webevals.NewLauncher` beside it |
| Only `adkrest.NewServer` + mux, no launchers yet | Prefer **B** if adding first Alis sublauncher; or introduce **A** only if user asks for full launcher stack |
| Mixed (launcher stack for some, direct for others) | Unusual — extend whichever pattern owns evals' peer sublaunchers; ask user if unclear |

Do not convert Pattern B agents to Pattern A (or vice versa) unless the user explicitly asks.

---

## Launcher config adapter (Pattern B)

Evals `SetupHostRoutes` requires `*launcher.Config` with at minimum:

- `SessionService`
- `AgentLoader`

If the repo already has `LauncherConfig()` for agui/scheduler, **reuse it**. If agent state lives in `runner.Config`, map the same fields peer sublaunchers use — do not duplicate session/agent wiring in the evals setup function.

---

## Judge client and metric registry placement

These are separate capabilities from route registration:

| Concern | Discover | Extend |
| ------- | -------- | ------ |
| Gemini/Vertex client config | Existing `genai.ClientConfig`, model setup, env reads for project/region | Add a **second** `genai.NewClient` for the judge beside existing model client setup |
| Metric registry | `metrics.NewDefaultRegistry`, `SetConfig`, `JudgeClient`, package importing `launchers/evals/evaluation/metrics` | Extend existing package or create one package that owns eval metrics — follow where similar bootstrap lives (`internal/evals/metrics`, `agent/metrics`, etc.) |

Pass the registry into `webevals.WithMetricRegistry` at the `NewLauncher` call site (Pattern A or B).

Greenfield reference for registry contract: `references/templates/evals-metrics-registry.go.example`

---

## Infra and deployment by pattern

| Concern | Pattern A | Pattern B |
| ------- | --------- | --------- |
| GCS storage (standard) | `WithEvalStorageURI` + `AGENT_EVALS_BUCKET` | Same |
| Dockerfile CMD / Cloud Run args | Append `evals` (no `-agents_dir`) | No `evals` keyword |
| Local disk (user asked only) | CLI `evals -agents_dir=...`; omit GCS in Go | `WithAgentsDir(...)` instead of GCS |

See **`references/infra-evals.md`**.
