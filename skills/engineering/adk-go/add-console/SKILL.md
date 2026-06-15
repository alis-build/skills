---
name: adk-add-console
description: >
  Wires the bundled Vue web UI sublauncher (go.alis.build/adk/launchers/console,
  console.NewLauncher) into an ADK agent entrypoint with branding, runtime config,
  and /auth/me. The console SPA is the AG-UI frontend for users to interact with
  the agent in the browser. Use when adding a web UI, frontend, console launcher,
  exposing the agent with UI, shell branding, or when the user mentions agent UI,
  chat UI, frontend—even if they do not say console or
  launchers/console. Requires add-agui and add-scheduler alongside console for the
  bundled SPA (chat and automation pages). Do not use for LRO (add-lro), sync tools
  (add-tool), or embedded
  runtime skills (add-agent-skills). No proto or define step.
---

# Add console launcher

Registers the **console** sublauncher on the existing ADK `launchersweb.NewLauncher` stack so users get the embedded Vue web UI at `/`, runtime config, and `/auth/me`. The bundled SPA depends on **add-agui** (threads/chat) and **add-scheduler** (automation) — wire those sublaunchers in Go and include `agui`, `scheduler`, and `-app_name=...` in deployment CLI args alongside `console`. One import, one sublauncher argument (registered **last**), and optional branding in `main.go`.

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/alis-workspace.md`** for the full discovery tier order. Use `workstations.build_repos` for the agent module.

**Do not confuse packages:**

| Package | Role |
|---------|------|
| `go.alis.build/adk/launchers/console` | Vue SPA web sublauncher (**this skill**) |
| `google.golang.org/adk/cmd/launcher/console` | Stock ADK CLI/TUI — out of scope |

## When to use

See the skill **description** (primary trigger). One import + sublauncher inside `launchersweb.NewLauncher` (last position); optional `WithBranding`; no define.

## Relationship to add-agui and add-scheduler

The bundled console SPA is not standalone — it calls **agui** and **scheduler** backends at runtime.

| Piece | Skill name | What it wires |
|-------|------------|---------------|
| Web UI (Vue SPA at `/`) | **add-console** (this skill) | `console.NewLauncher` — shell, branding, `/auth/me` |
| Threads / chat (required) | **add-agui** | `webagui.NewLauncher` — `/agui/*` APIs the SPA calls |
| Automation / crons (required) | **add-scheduler** | `webscheduler.NewLauncher`, `internal/scheduler` — scheduler JSON-RPC |

A user asking to **expose the agent with a UI**, **add a frontend**, or **add console** needs **add-agui** and **add-scheduler** wired unless those sublaunchers are already present. LRO (`api` + `lro`) is only needed when chat should resume after long-running operations.

## When not to use

| Need | Use skill |
|------|-----------|
| AG-UI protocol / SSE / thread APIs only (no bundled SPA — e.g. CopilotKit, custom client) | **add-agui** |
| A2A scheduler / cron automation | **add-scheduler** |
| Long-running operations / LRO resume | **add-lro** |
| Sync / LRO tools, protos | **add-tool**, **add-lro** |
| Embedded runtime agent skills (`skilltoolset`) | **add-agent-skills** |
| Stock ADK TUI console | `google.golang.org/adk/cmd/launcher/console` (different package) |
| **define** / `tools.proto` for console wiring alone | Not required for console |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(launchersweb.NewLauncher(...))` already in place.
- **add-agui** and **add-scheduler** wired in Go (`webagui.NewLauncher`, `webscheduler.NewLauncher`, `internal/scheduler`) unless already present — the console SPA requires both at runtime.
- `ALIS_OS_PROJECT` and `IDENTITY_SERVICE_URL` set at process start (required by `go.alis.build/mux`, pulled in via `go.alis.build/adk/launchers/web`).
- User can **install required dependencies** if `go.alis.build/adk/launchers` is not already in `go.mod`.

## Steps

| # | Action |
|---|--------|
| 1 | Add import: `console "go.alis.build/adk/launchers/console"` |
| 2 | Append sublauncher **last** inside `launchersweb.NewLauncher(...)`: `console.NewLauncher(console.WithBranding(...))` — see **Branding** below |
| 3 | Add `agui`, `scheduler`, `-app_name=<adkAppName>`, and `console` to launcher CLI args in Dockerfile and Cloud Run / deployment config (see **Deployment: launcher CLI args** below) |
| 4 | Ask user to install/upgrade `go.alis.build/adk/launchers` if needed |
| 5 | `go build ./...` and run the agent locally; verify SPA loads at `/` and `GET /assets/config/runtime-config.json` returns branding |

Template: **`references/templates/main-console-wiring.go.example`**

## Registration order

Register `console.NewLauncher` **last** inside `launchersweb.NewLauncher(...)`. The console installs a `GET /` catch-all for the Vue SPA; if it is registered before `agui`, `scheduler`, or other host routes, those routes are shadowed.

```go
launchersweb.NewLauncher(
    // ... other sublaunchers (webui, api, agui, scheduler, lro, etc.) ...
    console.NewLauncher(console.WithBranding(...)), // LAST
)
```

## Branding

Pass shell chrome via `console.WithBranding(console.Branding{...})`. This is the primary customization surface for console wiring.

### How branding flows

1. Pass `console.WithBranding(console.Branding{...})` to `console.NewLauncher`.
2. At setup, `Logo` and `Favicon` resolvers run and populate `LogoURL` / `FaviconURL` (do **not** set `LogoURL`/`FaviconURL` directly — they are output fields).
3. Resolved values are served in `GET /assets/config/runtime-config.json` under `branding.logoUrl` and `branding.faviconUrl`.
4. The Vue SPA reads runtime-config and applies shell chrome. Omit `Logo`/`Favicon` resolvers to use bundled SPA defaults (`/logo.svg` and index.html favicon).

### `console.Branding` fields

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `Title` | `string` | Optional | Browser tab / shell title |
| `DisplayName` | `string` | Optional | Human-readable name shown in the web UI |
| `Logo` | `AssetResolver` | Optional | Logo image resolver (see below) |
| `Favicon` | `AssetResolver` | Optional | Favicon resolver (see below) |

### Asset resolvers for `Logo` and `Favicon`

| Resolver | When to use | Example |
|----------|-------------|---------|
| `console.URLAsset(href)` | External CDN URL, or a path already served by another route | `console.URLAsset("https://cdn.example.com/logo.png")` or `console.URLAsset("/my-agent/branding/logo.svg")` |
| `console.EmbedAsset(files, root, relativePath)` | File in a `go:embed` FS; console registers it at `/console/branding/<relativePath>` | `console.EmbedAsset(brandingFS, "branding", "logo.svg")` |
| `console.DirAsset(dir, relativePath)` | File on the host filesystem at deploy time; served at `/console/branding/<relativePath>` | `console.DirAsset("./assets/branding", "favicon.ico")` |

### Branding examples

```go
// Minimal — strings only; SPA uses bundled logo/favicon
console.NewLauncher(console.WithBranding(console.Branding{
    Title:       "My Agent",
    DisplayName: "My Agent",
}))

// External URLs
console.NewLauncher(console.WithBranding(console.Branding{
    Title:       "Test Agent V1",
    DisplayName: "Test Agent V1",
    Favicon:     console.URLAsset("https://placehold.co/400x400"),
    Logo:        console.URLAsset("https://placehold.co/400x400"),
}))

// Agent-served paths — register agent branding routes BEFORE console in web.NewLauncher
console.NewLauncher(console.WithBranding(console.Branding{
    Title:       "My Agent",
    DisplayName: "My Agent",
    Favicon:     console.URLAsset("/my-agent/branding/favicon.ico"),
    Logo:        console.URLAsset("/my-agent/branding/logo.svg"),
}))

// go:embed branding assets
//go:embed branding/*
var brandingFS embed.FS

console.NewLauncher(console.WithBranding(console.Branding{
    Logo:    console.EmbedAsset(brandingFS, "branding", "logo.svg"),
    Favicon: console.EmbedAsset(brandingFS, "branding", "favicon.ico"),
}))
```

### Branding pitfalls

- Setting `LogoURL`/`FaviconURL` directly — use `Logo`/`Favicon` resolvers instead.
- Using `URLAsset` for agent paths that are not yet registered — agent branding routes must be mounted before console (console is last).
- Empty `URLAsset("")` — errors at setup; href is required.
- `EmbedAsset` / `DirAsset` file must exist at setup or launcher fails.

### Other `NewLauncher` options

- `WithDevServerURL(url)` — force Vite dev proxy target (see **Local development**).
- `WithIsLocal(fn)` — override embedded-dist vs dev-proxy selection (default: proxy when `SPA_DEV_SERVER_URL` is set).

## SPA feature backends

The console SPA ships with threads and automation pages — both backends must be wired for a functional deployment:

| Web UI page | Backend API | Required skill |
|-------------|-------------|----------------|
| Threads / chat | `/agui/run_sse`, `/agui/threads/*`, history JSON-RPC | **add-agui** — `webagui.NewLauncher` + `agui` CLI arg; `WithThreadService` for history |
| Automation (crons) | `/alis.a2a.extension.v1.SchedulerService` JSON-RPC | **add-scheduler** — `webscheduler.NewLauncher`, `internal/scheduler`, `scheduler` + `-app_name` CLI args |
| LRO resume in chat | `/api` + `lro` sublauncher | **add-lro** (optional) — `weblro.NewLauncher`, `api` + `lro` CLI args |

Thread/history and scheduler Spanner tables (provisioned when wiring **add-agui** or **add-scheduler**) require both proto imports below on any one define proto (typically `tools.proto`), even if unused — then run define:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

## Local development

By default the console serves the **embedded** `app/dist` build from `go.alis.build/adk/launchers/console`. For Vite HMR on the agent host:

```bash
cd console/app && pnpm dev   # port 8000
SPA_DEV_SERVER_URL=http://localhost:8000 go run . web -port 8080 scheduler -app_name=my.agent agui console
```

Unset `SPA_DEV_SERVER_URL` to test the production embed locally. Override in code with `WithIsLocal(func() bool { return false })` or `WithDevServerURL(...)`.

When developing the console frontend on the Vite port, `console/app/vite.config.ts` forwards `/agui` and JSON-RPC paths to `AGENT_HOST` (default `http://localhost:8080`).

## Deployment: launcher CLI args

The ADK binary uses **positional CLI args** to activate each sublauncher at runtime. Registering `console.NewLauncher` in Go is not enough — you must also pass the CLI args when running the binary.

The bundled console SPA requires **agui** and **scheduler** at runtime. Include `agui`, `scheduler`, `-app_name=<adkAppName>` (must match `llmagent.Config.Name`), and `console` in deployment args. Place `console` last to match registration order in `launchersweb.NewLauncher`.

### Dockerfile

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME", "agui", "console"]
```

### Cloud Run (Terraform)

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME", "agui", "console"]
}
```

### Full example (with optional sublaunchers)

A typical production agent may also include webui, api, and lro:

```
args = ["web", "-port", "8080", "webui", "-api_server_address=/api", "api", "lro", "scheduler", "-app_name=my.agent", "agui", "console"]
```

Add `webui`, `api`, `lro`, etc. only when the agent uses them. `agui`, `scheduler`, `-app_name`, and `console` are required for the bundled console SPA.

### Local development

```bash
go run . web -port 8080 scheduler -app_name=REPLACE_WITH_ADK_APP_NAME agui console
```

## Verification

- [ ] `go build ./...` passes
- [ ] Console sublauncher is inside `launchersweb.NewLauncher(...)`, registered **last**
- [ ] Dockerfile CMD and Cloud Run args include `agui`, `scheduler`, `-app_name=<adkAppName>`, and `console` (last)
- [ ] `ALIS_OS_PROJECT` and `IDENTITY_SERVICE_URL` are set on the deployment target
- [ ] Agent starts without launcher registration errors
- [ ] SPA loads at `/`; `GET /assets/config/runtime-config.json` returns expected branding
- [ ] Branding uses `Logo`/`Favicon` resolvers, not `LogoURL`/`FaviconURL` directly

## Pitfalls

- Using `google.golang.org/adk/cmd/launcher/console` instead of `go.alis.build/adk/launchers/console` — different launcher, different integration.
- Adding console outside `launchersweb.NewLauncher` — it must be a **sibling** sublauncher with `webui`, `webapi`, `webagui`, etc.
- Registering console before other sublaunchers — its `GET /` catch-all shadows `agui`, `scheduler`, and other host routes.
- Missing `console` in Dockerfile CMD or Cloud Run args — the sublauncher is registered in Go but won't activate without the CLI arg.
- Deploying with `console` only — threads and automation pages fail without `agui`, `scheduler`, and `-app_name` in CLI args (and matching Go wiring).
- Wiring console without **add-agui** or **add-scheduler** — the SPA loads but `/agui/*` and scheduler JSON-RPC calls fail.
- Running `go get` before confirming whether `go.alis.build/adk/launchers` is already required — ask user to install dependencies when unsure.
- Setting `LogoURL`/`FaviconURL` in `Branding` — use `Logo`/`Favicon` asset resolvers instead.

## Templates index

| File | Purpose |
|------|---------|
| `references/templates/main-console-wiring.go.example` | Entrypoint console sublauncher wiring with branding options |
