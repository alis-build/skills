---
name: adk-add-console
description: >
  Use this skill when the user wants a browser chat UI, operator console, custom frontend, agentsui,
  or agent branding — even if they do not say console. Default path installs the agentsui CodeBlock
  (Vue BFF + SPA) via InstallBlock and wires the agent as a backend. Requires add-agui and
  add-scheduler on the agent. Bundled console.NewLauncher is a fallback only. Not for LRO (add-lro),
  sync tools (add-tool), or embedded runtime skills (add-agent-skills).
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    organisation_id product_id focus_neuron_id workstations.build_repos
---

# Add console (custom agentsui BFF)

Installs the **agentsui** CodeBlock to lay down a custom Vue operator console as a **Backend For Frontend (BFF)**. The browser talks only to the console service; the BFF authenticates the user, serves the SPA, and proxies AG-UI and gRPC-Web calls to the ADK agent. The agent does **not** register `console.NewLauncher`.

Before installing, search the neuron for an existing `console/server.go` or console Cloud Run resources — extend in place rather than reinstalling.

Read **`references/post-install-agentsui.md`** for what the block delivers and what you verify on the agent.

## Console modes

| Mode | Default | Agent wiring | Deploy shape |
|------|---------|--------------|--------------|
| **Custom console (agentsui BFF)** | **Yes** | `agui` + `scheduler` + gRPC registrar; **no** `console.NewLauncher`, **no** `console` CLI arg | Two Cloud Run services: agent + `{neuron}-console` |
| **Bundled ADK console** | Fallback | `console.NewLauncher(...)` registered **last**; `console` CLI arg | Single Cloud Run service |

Use the bundled launcher only when the user explicitly wants the SPA served from the agent binary (single container, no separate console image).

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`.
5. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Landing zone id | `organisation_id` | MCP `GetLandingZone`; needed for `InstallBlock` |
| Product id | `product_id` | MCP `ViewProduct`; needed for `InstallBlock` |
| Neuron / service id | `focus_neuron_id` | Neuron scope for console install and agent verification |
| Neuron build root | `workstations.build_repos` | Parent of `infra/` and install target for `console/` |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/alis-workspace.md`** for path rules and discovery. Use `workstations.build_repos` for the neuron root.

**Do not confuse packages and artifacts:**

| Package / artifact | Role |
|--------------------|------|
| **`agentsui` CodeBlock** | Custom Vue BFF + SPA — **default path** (this skill) |
| `go.alis.build/adk/launchers/console` | Bundled SPA sublauncher — **fallback only** |
| `google.golang.org/adk/cmd/launcher/console` | Stock ADK CLI/TUI — out of scope |

## When to use

See the skill **description** (primary trigger). Default: `InstallBlock(agentsui)` → verify agent backends → customize SPA → deploy two images.

## Relationship to add-agui and add-scheduler

The console SPA is not standalone — it calls **agui** and **scheduler** backends on the agent (directly in bundled mode; via BFF proxy in agentsui mode).

| Piece | Skill name | What it wires |
|-------|------------|---------------|
| Web UI (Vue SPA) | **add-console** (this skill) | `agentsui` block — BFF + SPA (**default**) or `console.NewLauncher` (**fallback**) |
| Threads / chat (required) | **add-agui** | `webagui.NewLauncher` — `/agui/*`; BFF reverse-proxies to agent |
| Automation / crons (required) | **add-scheduler** | `webscheduler.NewLauncher`, `internal/scheduler`; BFF proxies gRPC-Web |

A user asking to **expose the agent with a UI**, **add a frontend**, or **add console** needs **add-agui** and **add-scheduler** wired on the agent unless those sublaunchers are already present. LRO (`api` + `lro`) is only needed when chat should resume after long-running operations.

In BFF mode the agent must also expose gRPC `ThreadService` and `SchedulerService` via `WithGRPCRegistrar` so the console BFF can proxy browser gRPC-Web clients.

## When not to use

| Need | Use skill |
|------|-----------|
| AG-UI protocol / SSE / thread APIs only (no browser SPA — e.g. CopilotKit, custom client) | **add-agui** |
| A2A scheduler / cron automation | **add-scheduler** |
| Long-running operations / LRO resume | **add-lro** |
| Sync / LRO tools, protos | **add-tool**, **add-lro** |
| Embedded runtime agent skills (`skilltoolset`) | **add-agent-skills** |
| Stock ADK TUI console | `google.golang.org/adk/cmd/launcher/console` (different package) |
| **define** / `tools.proto` for console wiring alone | Not required for console |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(launchersweb.NewLauncher(...))` already in place.
- **add-agui** and **add-scheduler** wired on the agent (`webagui.NewLauncher`, `webscheduler.NewLauncher`, `internal/scheduler`, gRPC registrar) unless already present.
- `ALIS_OS_PROJECT` and `IDENTITY_SERVICE_URL` set on both agent and console deployments.
- MCP access for `InstallBlock` (or user installs the block manually in Build Kit).

## Discovery signals

Before installing or editing, grep the neuron to determine which mode is in use:

| Signal | Mode |
|--------|------|
| `console/server.go` + `AGENT_SERVICE_URL` on console Cloud Run | BFF (agentsui) |
| `google_cloud_run_v2_service.console` in parent `infra/` | BFF (agentsui) |
| `console.NewLauncher` in agent entrypoint | Bundled ADK console |
| `"console"` in agent Cloud Run args | Bundled launcher active |

If BFF signals are present, skip `InstallBlock` and proceed to post-install verification and customization.

## Install `agentsui` (default path)

| # | Action |
|---|--------|
| 0 | Run `bash scripts/resolve-alis-workspace.sh --json`; MCP `ViewProduct` if `organisation_id` or `product_id` is missing |
| 1 | **Discover** — grep for `console/server.go`, `google_cloud_run_v2_service.console` in `infra/`; if present, skip to **Post-install wiring** |
| 2 | **`InstallBlock`** with `block_id: "agentsui"`, resolved `landing_zone_id` (= `organisation_id`), `product_id`, and `neuron_id` (= `focus_neuron_id`). On failure only, call `ListBlocks` to confirm the block id |
| 3 | Inspect `BlockInstall` response (`package`, `git_branch`, `state`); read installed `console/README.md` for block-local SPA and feature docs |
| 4 | **Verify infra merges** in `<neuron>/infra/` — see **`references/templates/infra-console-bff.snippet.example`** |
| 5 | **Verify agent** — no `console.NewLauncher`; agui + scheduler + gRPC registrar present. If missing, apply **add-agui** / **add-scheduler** (do not duplicate their full workflows here) |
| 6 | **Customize SPA** — edit `console/app/src/constants/agentUi.ts` |
| 7 | **Build/deploy** both agent and console images via MCP or Build Kit |

### What the block delivers (do not hand-author)

The `agentsui` install lays down:

| Artifact | Location |
|----------|----------|
| BFF + SPA | `<neuron>/console/` — `server.go`, `app/`, `internal/`, `Dockerfile`, `go.mod` |
| Console Cloud Run + public invoker IAM | merged into `<neuron>/infra/cloudrun.tf` |
| Load balancer backend | merged into `<neuron>/infra/loadbalancing.tf` |
| URL locals (if absent) | `<neuron>/infra/variables.tf` — `local.agent_service_url`, `local.identity_service_url` |

Infra merges into the **parent neuron `infra/`** — not a separate `console/infra/` directory.

Template: **`references/templates/agent-bff-prerequisites.go.example`** — agent launcher stack without console.

## Post-install wiring

### Agent contract

The agent serves AG-UI and gRPC backends only. Verify (extend in place if missing):

- Host `grpc.Server` with `iam.UnaryInterceptor` + `iam.StreamInterceptor` and `mux.HandleGRPC`
- `webagui.NewLauncher(adkAppName, webagui.WithThreadService(history.Service), webagui.WithGRPCRegistrar(grpcServer))`
- `webscheduler.NewLauncher(adkAppName, scheduler.Service, webscheduler.WithGRPCRegistrar(grpcServer))`
- **No** `console.NewLauncher` in `launchersweb.NewLauncher(...)`
- Agent Dockerfile / Cloud Run args include `agui`, `scheduler`, `-app_name=<adkAppName>` — **omit** `console`
- Agent image: `neurons/${local.neuron}/agent:…`

### SPA customization

Edit `console/app/src/constants/agentUi.ts`:

| Constant | Must match |
|----------|------------|
| `DEFAULT_AGENT_ID` | ADK app name — `llmagent.Config.Name` / `-app_name` CLI arg (periods, not hyphens) |
| `AGENT_DISPLAY_NAME` | Human-readable shell title |
| `AGENT_ICON_SRC` | Logo path (e.g. `/logo.svg` in SPA `dist/`) |
| `SUGGESTION_CHIPS` | Home-page starter prompts (optional) |

### BFF env vars (console Cloud Run)

| Variable | Purpose |
|----------|---------|
| `AGENT_SERVICE_URL` | Agent Cloud Run URL — BFF proxies AG-UI and gRPC-Web here |
| `IDENTITY_SERVICE_URL` | IAM Users service for session auth |
| `ALIS_OS_PROJECT` | GCP project (runtime config, tracing) |
| `SPA_DEV_SERVER_URL` | Vite URL for local dev (default `http://localhost:8000`) |
| `COOKIE_DOMAIN` | Optional; sets `mux.AuthCookiesDomain` |
| `PORT` | Listen port (default `8080`) |

### Image path suffix

Console image path must match install location:

| CodeBlock install path | Image in `infra/cloudrun.tf` |
|------------------------|-------------------------------|
| `<neuron>/console/` | `…/neurons/${local.neuron}/console:…` |
| Neuron root (block *is* the neuron) | `…/neurons/${local.neuron}:…` |

### Local development (BFF)

1. Run the agent locally with `agui`, `scheduler`, `-app_name=…` (no `console`).
2. From `console/app/`: `pnpm dev` (port 8000).
3. Run the console BFF (`go run .` from `console/` or VS Code launch).
4. Open the **BFF** URL (not `:8000` directly) so auth and API calls share the same origin.

See installed `console/README.md` for Vite proxy settings and VS Code launch configs.

## Deployment (BFF — two images)

Build and deploy **both** images:

| Service | Dockerfile | Image suffix |
|---------|------------|--------------|
| Agent | `<neuron>/agent/Dockerfile` | `…/agent:…` |
| Console BFF | `<neuron>/console/Dockerfile` | `…/console:…` (when nested) |

The console Dockerfile is block-owned — multi-stage Node (`app/`) + Go (`server.go`), copies `dist/` next to the binary.

User-facing URL is the **console** load balancer / Cloud Run service (`{neuron}-console`), not the agent service.

## SPA feature backends

The console SPA ships with threads and automation pages — agent backends must be wired:

| Web UI page | BFF route | Agent backend | Required skill |
|-------------|-----------|---------------|----------------|
| Threads / chat | `POST /agui/run_sse` (proxied) | `/agui/*` | **add-agui** |
| Thread metadata | gRPC-Web (proxied) | `ThreadService` | **add-agui** + gRPC registrar |
| Automation (crons) | gRPC-Web (proxied) | `SchedulerService` | **add-scheduler** + gRPC registrar |
| LRO resume in chat | proxied `/api` | `api` + `lro` sublauncher | **add-lro** (optional) |

Thread/history and scheduler Spanner tables require both proto imports on any one define proto (typically `tools.proto`), even if unused — then run define:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

---

## Alternative: bundled ADK console

Use only when the user explicitly wants a **single-container** deployment with the SPA embedded in the agent binary via `go.alis.build/adk/launchers/console`.

### Web launcher stack

Before adding `console`, ensure the entrypoint uses Alis launchers — not stock ADK google launchers.

| | |
|-|-|
| **Contract** | When wiring any `go.alis.build/adk/launchers/*` sublauncher (console, agui, scheduler, lro), the web host must import `go.alis.build/adk/launchers/web` — not `google.golang.org/adk/cmd/launcher/web`. Alis sublaunchers use `go.alis.build/adk/launchers/*`. Stock ADK sublaunchers without Alis equivalents (api, webui, a2a, agentengine) keep `google.golang.org/adk/cmd/launcher/*` imports as children inside the Alis web host. Do not use a google web host with Alis sublaunchers. `google.golang.org/adk/cmd/launcher/universal` stays unchanged. |
| **Discovery signals** | `google.golang.org/adk/cmd/launcher/web`, `google.golang.org/adk/cmd/launcher/webui`, `webapi`, `weba2a`, `webagentengine` |
| **Wire points** | Entrypoint import block and `universal.NewLauncher(launchersweb.NewLauncher(...))` call |

**Action:** If the entrypoint uses `google.golang.org/adk/cmd/launcher/web` as the web host, replace it with `go.alis.build/adk/launchers/web` before appending `console.NewLauncher`.

### Bundled steps

| # | Action |
|---|--------|
| 0 | **Web launcher stack** — migrate web host to `go.alis.build/adk/launchers/web` if needed |
| 1 | Add import: `console "go.alis.build/adk/launchers/console"` |
| 2 | Append sublauncher **last** inside `launchersweb.NewLauncher(...)`: `console.NewLauncher(console.WithBranding(...))` — see **Branding** below |
| 3 | Add `agui`, `scheduler`, `-app_name=<adkAppName>`, and `console` to launcher CLI args in Dockerfile and Cloud Run config |
| 4 | Ask user to install/upgrade `go.alis.build/adk/launchers` if needed |
| 5 | `go build ./...`; verify SPA loads at `/` and `GET /assets/config/runtime-config.json` returns branding |

Template: **`references/templates/main-console-wiring.go.example`** (fallback only)

For a custom SPA dist in the same container, use `console.WithDist(console.DirDist("/app/dist"))` or `console.WithDist(console.HandlerDist(...))` — see installed `console/app/README.md` when the block is present.

### Registration order

Register `console.NewLauncher` **last** inside `launchersweb.NewLauncher(...)`. The console installs a `GET /` catch-all for the Vue SPA; if it is registered before `agui`, `scheduler`, or other host routes, those routes are shadowed.

```go
launchersweb.NewLauncher(
    // ... other sublaunchers (webui, api, agui, scheduler, lro, etc.) ...
    console.NewLauncher(console.WithBranding(...)), // LAST
)
```

### Branding

Pass shell chrome via `console.WithBranding(console.Branding{...})`.

#### How branding flows

1. Pass `console.WithBranding(console.Branding{...})` to `console.NewLauncher`.
2. At setup, `Logo` and `Favicon` resolvers run and populate `LogoURL` / `FaviconURL` (do **not** set `LogoURL`/`FaviconURL` directly — they are output fields).
3. Resolved values are served in `GET /assets/config/runtime-config.json` under `branding.logoUrl` and `branding.faviconUrl`.
4. The Vue SPA reads runtime-config and applies shell chrome.

#### `console.Branding` fields

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `Title` | `string` | Optional | Browser tab / shell title |
| `DisplayName` | `string` | Optional | Human-readable name shown in the web UI |
| `Logo` | `AssetResolver` | Optional | Logo image resolver |
| `Favicon` | `AssetResolver` | Optional | Favicon resolver |

#### Asset resolvers

| Resolver | When to use | Example |
|----------|-------------|---------|
| `console.URLAsset(href)` | External CDN URL, or a path already served by another route | `console.URLAsset("https://cdn.example.com/logo.png")` |
| `console.EmbedAsset(files, root, relativePath)` | File in a `go:embed` FS | `console.EmbedAsset(brandingFS, "branding", "logo.svg")` |
| `console.DirAsset(dir, relativePath)` | File on the host filesystem at deploy time | `console.DirAsset("./assets/branding", "favicon.ico")` |

#### Other `NewLauncher` options

- `WithDist(...)` — serve a custom SPA build instead of the embedded default.
- `WithDevServerURL(url)` — force Vite dev proxy target.
- `WithIsLocal(fn)` — override embedded-dist vs dev-proxy selection.

### Bundled local development

```bash
cd console/app && pnpm dev   # port 8000
SPA_DEV_SERVER_URL=http://localhost:8000 go run . web -port 8080 scheduler -app_name=my.agent agui console
```

When developing on the Vite port, `console/app/vite.config.ts` forwards `/agui` and JSON-RPC paths to `AGENT_HOST` (default `http://localhost:8080`).

### Bundled deployment: launcher CLI args

Include `agui`, `scheduler`, `-app_name=<adkAppName>`, and `console` in deployment args. Place `console` last.

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME", "agui", "console"]
```

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "scheduler", "-app_name=REPLACE_WITH_ADK_APP_NAME", "agui", "console"]
}
```

---

## Verification

### Custom BFF (default)

- [ ] `agentsui` installed; `console/server.go` + `console/Dockerfile` present
- [ ] Parent `infra/` has console Cloud Run + load balancer resources
- [ ] Console image path uses `/console` suffix when block is at `<neuron>/console/`
- [ ] Agent: agui + scheduler + gRPC registrar; **no** `console.NewLauncher`
- [ ] Agent args omit `console`
- [ ] `DEFAULT_AGENT_ID` in `agentUi.ts` matches ADK app name
- [ ] Console env: `AGENT_SERVICE_URL`, `IDENTITY_SERVICE_URL`, `ALIS_OS_PROJECT`
- [ ] Both images build; agent and console deploy successfully
- [ ] SPA loads at console URL; chat + threads + automation work through BFF

### Bundled ADK console (fallback)

- [ ] `go build ./...` passes
- [ ] Console sublauncher is inside `launchersweb.NewLauncher(...)` from `go.alis.build/adk/launchers/web`, registered **last**
- [ ] No `google.golang.org/adk/cmd/launcher/web` import when console or other Alis sublaunchers are wired
- [ ] Dockerfile CMD and Cloud Run args include `agui`, `scheduler`, `-app_name=<adkAppName>`, and `console` (last)
- [ ] `ALIS_OS_PROJECT` and `IDENTITY_SERVICE_URL` are set on the deployment target
- [ ] Agent starts without launcher registration errors
- [ ] SPA loads at `/`; `GET /assets/config/runtime-config.json` returns expected branding
- [ ] Branding uses `Logo`/`Favicon` resolvers, not `LogoURL`/`FaviconURL` directly

## Pitfalls

### BFF (agentsui)

- Hand-authoring `console/` instead of using `InstallBlock` — the block owns BFF code, SPA scaffold, Dockerfile, and infra merges
- Installing `agentsui` **and** wiring `console.NewLauncher` — pick one mode
- `DEFAULT_AGENT_ID` not matching `llmagent.Config.Name` / `-app_name` — thread routing breaks
- Console image path missing `/console` suffix when block is nested under neuron
- Agent missing `WithGRPCRegistrar` — BFF gRPC-Web calls to Thread/Scheduler fail
- Opening Vite on `:8000` directly in BFF mode — use BFF origin for auth and same-origin API
- Forgetting to deploy the console image — only deploying the agent leaves no UI endpoint
- User cookies forwarded to agent — BFF must attach invoker OIDC, not forward session cookies

### Bundled ADK console

- Mixing `google.golang.org/adk/cmd/launcher/web` with Alis `console`, `webagui`, `webscheduler`, or other `go.alis.build/adk/launchers/*` sublaunchers — migrate web host first
- Using `google.golang.org/adk/cmd/launcher/console` instead of `go.alis.build/adk/launchers/console` — different launcher
- Registering console before other sublaunchers — its `GET /` catch-all shadows routes
- Missing `console` in Dockerfile CMD or Cloud Run args — sublauncher won't activate
- Deploying with `console` only — threads and automation fail without `agui`, `scheduler`, and `-app_name`
- Setting `LogoURL`/`FaviconURL` in `Branding` — use `Logo`/`Favicon` asset resolvers instead

### General

- Refactoring existing launcher wiring to match skill templates without being asked — discover and extend in place
- Wiring console without **add-agui** or **add-scheduler** — SPA loads but backend calls fail
- Running `go get` before confirming whether `go.alis.build/adk/launchers` is already required

## Templates index

| File | Purpose |
|------|---------|
| `references/post-install-agentsui.md` | Block deliverables, agent responsibilities, env vars |
| `references/templates/agent-bff-prerequisites.go.example` | Agent launcher stack without console (default path) |
| `references/templates/infra-console-bff.snippet.example` | Infra snippets the block merges (verification) |
| `references/templates/main-console-wiring.go.example` | Bundled console sublauncher wiring (**fallback only**) |
