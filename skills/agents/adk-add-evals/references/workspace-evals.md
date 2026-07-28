# Agent workspace layout (Evals)

Portable rules for wiring ADK evals on Alis Build. **Discover the repo's patterns first** — do not assume `main.go`, `internal/evals/metrics`, or launcher stack layout.

Read **`references/wiring-patterns.md`** to determine Pattern A (launcher stack) vs Pattern B (direct `SetupHostRoutes`).

## Platform hierarchy

Landing zone → product → neuron. Build repos under `~/alis.build/`.

## Repo reconnaissance

Before any edit:

1. **`go.mod`** — module path, ADK version (`/v2` or not), `go.alis.build/adk/launchers` version.
2. **List packages** — find agent bootstrap, server entry, infra, existing sublauncher setup.
3. **Grep discovery signals** — see **`SKILL.md`** capabilities.
4. **Identify host pattern** — launcher stack vs direct routes (signals below).
5. **Follow peer placement** — put evals code where agui, scheduler, or model setup already live.

## Host pattern detection

| Signal | Likely pattern |
| ------ | -------------- |
| `universal.NewLauncher`, `l.Execute(..., os.Args)` | **A** — launcher stack |
| `SetupAGUIRoutes`, `SetupSchedulerRoutes`, `SetupHostRoutes` | **B** — direct routes |
| `mux.ListenAndServe` without `l.Execute` | **B** |
| `LauncherConfig()` mapping to `launcher.Config` | **B** |

When Pattern B is present, add `SetupEvalsRoutes` (or match existing `Setup*Routes` naming) — do not introduce launcher stack unless user asks.

## ADK version detection

**Platform rule:**

| `go.alis.build/adk/launchers` | ADK-Go |
| ----------------------------- | ------ |
| pre v1.0.0 (v0.x) | pre-v2 |
| v1.0.0+ (v1.x) | v2.0.0+ |

**Evals minimum:** v0.3.10+ / v1.0.10+.

Import paths (`google.golang.org/adk` vs `/v2`) must match the launchers line.

## App name

Eval URLs use `{app_name}` — must match `llmagent.Config.Name` or the repo's canonical app name constant (`info.Name`, `AppName`, etc.). Discover where identity lives; do not invent a second name.

## Inferring file placement

| Concern | Where to look | Extend |
| ------- | ------------- | ------ |
| Server startup | `main.go`, `server.go`, `cmd/` | Add `SetupEvalsRoutes()` call next to peer setup |
| Sublauncher setup | `agui.go`, `scheduler.go`, `agent/*.go` | Add evals setup beside peers (Pattern B) |
| Launcher composition | File with `web.NewLauncher(...)` | Add `webevals.NewLauncher` (Pattern A) |
| Gemini / model | Agent `init`, config package, bootstrap | Add judge `genai.NewClient` beside model client |
| Metric registry | Any package importing eval metrics, or new package under `internal/` | One package owning judge registry |
| Infra / GCS | `infra/*.tf` | Extend storage terraform; match `local.neuron`; wire `AGENT_EVALS_BUCKET` + `WithEvalStorageURI` (standard — not `WithAgentsDir` unless user asked) |

Greenfield defaults in templates apply **only when no pattern exists**.

## Canonical paths (context)

| Artifact | Context field |
| -------- | ------------- |
| Neuron build root | `workstations.build_repos[]` |
| Infra | `<build_repos entry>/infra` |

## Hard rules

| Do | Do not |
| ---- | ------ |
| Discover host pattern and peer file layout | Copy template paths into unlike repos |
| Reuse `LauncherConfig()` on Pattern B | Duplicate session/agent wiring for evals |
| Extend existing packages | Create parallel packages without searching |
| Verify contracts | Verify folder names from templates |

User corrections override everything.
