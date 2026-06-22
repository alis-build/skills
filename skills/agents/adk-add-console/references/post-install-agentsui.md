# Post-install: agentsui custom console

Reference for what the **agentsui** CodeBlock delivers and what the running agent must provide after `InstallBlock`.

## What the block lays down

Do **not** hand-author these — `InstallBlock(block_id: "agentsui")` creates them:

```text
<neuron>/
├── console/                    # CodeBlock root
│   ├── server.go               # BFF entrypoint — routes, SPA, proxies
│   ├── Dockerfile              # Node build (app/) + Go binary
│   ├── go.mod
│   ├── internal/
│   │   ├── handlers/           # /auth/me
│   │   ├── services/           # gRPC-Web proxy to agent
│   │   └── utils/              # Auth forwarding helpers
│   └── app/                    # Vue SPA root (package.json, src/)
└── infra/                      # Parent neuron infra — block merges snippets
    ├── cloudrun.tf             # + google_cloud_run_v2_service.console
    ├── loadbalancing.tf        # + console NEG + backend service
    └── variables.tf            # + local.agent_service_url (if absent)
```

Infra merges into the **parent neuron `infra/`**, not a separate `console/infra/` directory.

## Architecture

```text
Browser
  └─ Console BFF (console/server.go, Cloud Run {neuron}-console)
       ├─ GET  /                                    → SPA (dist/ or Vite dev proxy)
       ├─ GET  /auth/me                             → IAM identity (mux session)
       ├─ GET  /assets/config/runtime-config.json   → deploy-time config
       ├─ POST /agui/*                              → reverse proxy → Agent
       ├─ GET  /agui/threads[...]                   → reverse proxy → Agent
       ├─ POST /a2a                                 → reverse proxy → Agent
       └─ gRPC-Web /                                → ThreadService, SchedulerService → Agent

Agent (separate Cloud Run service)
  ├─ ADK launchers: agui, scheduler, api, lro, …
  ├─ Spanner-backed history + scheduler
  └─ No console.NewLauncher — SPA is not served here
```

## Agent responsibilities (you verify / extend)

The block does **not** wire the agent. After install, confirm the agent entrypoint has:

| Requirement | Why |
|-------------|-----|
| `webagui.NewLauncher` with `WithThreadService` + `WithGRPCRegistrar` | BFF proxies `/agui/*` and gRPC-Web ThreadService |
| `webscheduler.NewLauncher` with `WithGRPCRegistrar` | BFF proxies gRPC-Web SchedulerService |
| Host `grpc.Server` with IAM interceptors + `mux.HandleGRPC` | Browser gRPC-Web auth |
| **No** `console.NewLauncher` | SPA is served by the BFF, not the agent |
| Agent args: `agui`, `scheduler`, `-app_name=…` — **no** `console` | CLI activates only agent backends |

If agui or scheduler is missing, apply **add-agui** and **add-scheduler** before expecting a working console.

Template: **`references/templates/agent-bff-prerequisites.go.example`**

## Auth forwarding

The BFF reads the authenticated IAM identity from the mux session and forwards it to the agent:

- **HTTP** (AG-UI, A2A): `x-alis-identity` + `X-Alis-Forwarded-Authorization` headers
- **gRPC-Web**: same metadata via outgoing context helpers in `internal/utils/`
- **Cloud Run invoker**: BFF attaches an OIDC ID token when calling the agent; user cookies are never forwarded

## Env vars

### Console Cloud Run (required)

| Variable | Purpose |
|----------|---------|
| `AGENT_SERVICE_URL` | Agent Cloud Run URL (e.g. `https://my-agent-….run.app`) |
| `IDENTITY_SERVICE_URL` | IAM Users service for session auth |
| `ALIS_OS_PROJECT` | GCP project (runtime config, tracing) |
| `PORT` | Listen port (default `8080`) |

### Console local dev (optional)

| Variable | Purpose |
|----------|---------|
| `SPA_DEV_SERVER_URL` | Vite URL (default `http://localhost:8000`) |
| `COOKIE_DOMAIN` | Sets `mux.AuthCookiesDomain` |
| `ALOG_LEVEL` | Log level when not local |

`IsLocal` is true when `K_SERVICE` is unset — BFF proxies `GET /` to Vite and enables debug logging.

## SPA customization

Edit `console/app/src/constants/agentUi.ts`:

```typescript
export const DEFAULT_AGENT_ID = 'my.agent.v1'       // must match llmagent.Config.Name / -app_name
export const AGENT_DISPLAY_NAME = 'My Agent'
export const AGENT_ICON_SRC = '/logo.svg'
export const SUGGESTION_CHIPS = [ /* home-page starters */ ]
```

## Image paths

Console Artifact Registry image suffix must match install location:

| Install path | Image expression |
|--------------|------------------|
| `<neuron>/console/` | `…/neurons/${local.neuron}/console:${sha}` |
| Neuron root | `…/neurons/${local.neuron}:${sha}` |

Verification template: **`references/templates/infra-console-bff.snippet.example`**

## Local development

1. Start the agent: `go run . web -port 8080 scheduler -app_name=my.agent.v1 agui` (from agent module).
2. From `console/app/`: `pnpm install && pnpm dev` (port 8000).
3. Run the BFF from `console/`: `go run .` (or use VS Code launch config from the block).
4. Open the **BFF** URL — not `:8000` directly — so `/auth/me` and proxied APIs share the same origin.

## Block README for SPA features

The installed `console/README.md` documents SPA-specific features in depth:

- AG-UI chat streaming and tool interrupts
- A2UI interactive surfaces
- Automation / cron pages
- Vite proxy and VS Code tasks

Use the block README for feature work; this skill reference covers install boundaries and agent wiring only.
