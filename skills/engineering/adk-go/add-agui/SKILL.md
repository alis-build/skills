---
name: adk-add-agui
description: >
  Wires the AG-UI web sublauncher (go.alis.build/adk/launchers/agui, webagui.NewLauncher) into an
  ADK agent entrypoint, exposing the agent to end users through a custom frontend over the AG-UI
  protocol (SSE). Present this as a candidate whenever the user wants to expose or serve an agent
  to users, build a web / UI / interface layer or product frontend, integrate CopilotKit or other
  AG-UI clients, or put an authenticated edge in front of the agent — even if they do not say
  webagui, ag-ui, or launchers/agui. AG-UI is the interface/transport layer and the insertion point
  for edge auth (WithInterceptor + CORS); it does NOT implement login or mint identity — pair it
  with the product's auth pattern. Do not use for tools.proto or ToolsService (add-tool),
  long-running operations (add-lro), or embedded runtime skills (add-agent-skills). Requires proto
  imports for Spanner table provisioning (see Proto imports for Spanner tables); service id must
  match infra config.
---

# Add AG-UI launcher

Registers the **agui** sublauncher on the existing ADK `web.NewLauncher` stack so clients can use the AG-UI protocol (SSE). One import and one extra sublauncher argument in `main.go`.

Identify the agent module (`go.mod`) and the service id from infra config before editing. In Alis Build projects, the service id is `local.neuron` in `infra/`; if **`.alis/agents/AGENTS.md`** exists, read it for product repo roots.

## Exposing an agent to users

When the goal is "let users actually use this agent," there are two interface surfaces on the `web` launcher stack:

- **Built-in `webui` + `api`** — the bundled ADK chat UI. Zero frontend code, but you don't control the UX. Best for internal/demo use.
- **`agui` (this skill)** — exposes the agent over the AG-UI protocol so a **custom frontend you own** (CopilotKit, or any AG-UI client) can stream messages, tool calls, and state. Choose this for a product-grade, branded, or embedded interface.

**Authentication.** AG-UI is the edge your frontend connects to, so it's where you *enforce* auth — `webagui.WithCORS` (which origins may connect) and `webagui.WithInterceptor` (inspect the request, read identity). It does **not** implement login or mint identity: on Alis Build the platform gateway injects the caller identity (Bearer JWT) ahead of the service, and your interceptor consumes it. For the login/identity mechanism itself, follow the product's auth pattern — this skill only wires the layer where auth is applied.

> The frontend web app (e.g. a CopilotKit Next.js project) is **not** part of this skill — it's a separate project that consumes the AG-UI endpoint this skill exposes.

## Orientation: how a request flows

When a user wants to understand how AG-UI works or where auth happens — not just wire it — walk them through the real code rather than describing it abstractly. The request path spans two modules:

- `go.alis.build/mux` (`auth.go`) — authentication middleware that establishes identity.
- `go.alis.build/adk/launchers/agui` — the sublauncher that runs the agent and streams AG-UI events.

Open the source in the user's module cache at the version their `go.mod` pins (`go list -m go.alis.build/adk/launchers go.alis.build/mux`, then read under `$(go env GOMODCACHE)`). Follow the trace in **`references/request-flow.md`**, which names files and functions (not line numbers, which drift between versions).

## When to use

See the skill **description** (primary trigger). One import + sublauncher inside `web.NewLauncher`; proto imports + define for Spanner tables when threads/history are used.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO tools, protos | **add-tool**, **add-lro** |
| Custom auth/history/A2UI interceptors (full stack) | Follow product-specific patterns beyond this minimal wiring |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(web.NewLauncher(...))` already in place.
- User can **install required dependencies** if `go.alis.build/adk/launchers` is not already in `go.mod` (often present with LRO or other Alis launchers).

## Steps

| # | Action |
|---|--------|
| 1 | Add import: `webagui "go.alis.build/adk/launchers/agui"` |
| 2 | Set service id from infra config (Terraform `locals` or variables) — same value as `lroServiceID` or `weblro.WithServiceID` when LRO is wired |
| 3 | Append sublauncher inside `web.NewLauncher(...)`: `webagui.NewLauncher("<service-id>", webagui.WithCORS(webagui.CORSConfig{}))` |
| 4 | Add proto imports for Spanner tables if not already present (see **Proto imports for Spanner tables** below); ask user to run define |
| 5 | Add `agui` to the launcher CLI args in Dockerfile and Cloud Run / deployment config (see **Deployment: launcher CLI args** below) |
| 6 | Ask user to install/upgrade `go.alis.build/adk/launchers` if needed |
| 7 | `go build ./...` and run the agent locally to verify the AG-UI route is served |
| 8 | Offer to orient the user in how a request flows (auth → handler → SSE) using `references/request-flow.md`. Recommended when the user is new to AG-UI or asked about auth / exposing to users; skip if they only wanted the wiring |

Template: **`references/templates/main-agui-wiring.go.example`**

## Service id

The first argument to `NewLauncher` is the **AG-UI service id**. Use the infra service identifier (e.g. from Terraform `locals` or variables), not the proto package name and not necessarily `llmagent.Config.Name`.

If both LRO and AG-UI are enabled, use the **same** id for `weblro.WithServiceID`, `InitLRO`, and `webagui.NewLauncher`.

### Alis Build projects

The service id is `local.neuron` (or `variables.neuron`) in `infra/`.

## Proto imports for Spanner tables

AG-UI thread/history storage uses Spanner tables provisioned through define. Add the following imports to **any one** proto in the agent's define package (typically `tools.proto`), even if nothing in the file references them:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Add **both** imports whenever threads/history Spanner tables are required — even if the agent does not use the scheduler yet. The imports are for table provisioning, not for RPC definitions in your service.

Ask the user to **run define** on the package (or neuron) after editing the proto. Add **both** imports whenever either thread/history or scheduler Spanner tables are needed — the same rule applies for **add-scheduler**.

## CORS and options

Default wiring uses empty `webagui.CORSConfig{}` (suitable for local dev). For production, adjust `WithCORS` allowed origins per your frontend hosts. `WithInterceptor` is the hook where per-request auth/authz attaches (see **Authentication** above and `references/request-flow.md`); implementing the interceptor logic is product-specific. `WithCapabilities` and other options are out of scope for this minimal skill — see `go.alis.build/adk/launchers/agui` and product examples when needed.

## Deployment: launcher CLI args

The ADK binary uses **positional CLI args** to activate each sublauncher at runtime. Registering `webagui.NewLauncher` in Go is not enough — you must also pass `agui` in the command args when running the binary.

Only include sublauncher args for sublaunchers the agent actually uses. The AG-UI sublauncher is independent — it has no dependencies on other sublaunchers.

### Dockerfile

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "agui"]
```

### Cloud Run (Terraform)

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "agui"]
}
```

### Minimal vs full example

The above shows only what AG-UI requires. A typical agent with multiple sublaunchers might look like:

```
args = ["web", "-port", "8080", "webui", "-api_server_address=/api", "api", "agui"]
```

Add other sublaunchers (`webui`, `api`, `lro`, `scheduler`, etc.) only if the agent uses them — they are not AG-UI prerequisites.

## Verification

- [ ] `go build ./...` passes
- [ ] AG-UI sublauncher is inside `web.NewLauncher(...)`, not outside `universal.NewLauncher`
- [ ] Service id matches infra service identifier
- [ ] Dockerfile CMD and Cloud Run args include `agui`
- [ ] Proto imports for history (and scheduler) Spanner tables present; user ran define
- [ ] Agent starts without launcher registration errors

## Pitfalls

- Wrong service id — read the infra config for the agent you are editing, not templates or other agents.
- Adding AG-UI outside `web.NewLauncher` — it must be a **sibling** sublauncher with `webui`, `webapi`, `weblro`, etc.
- Running `go get` before confirming whether `go.alis.build/adk/launchers` is already required — ask user to install dependencies when unsure.
- Missing `agui` in Dockerfile CMD or Cloud Run args — the sublauncher is registered in Go but won't activate without the CLI arg.
- Skipping proto imports for Spanner tables — thread/history storage will not be provisioned; add both `scheduler.proto` and `history.proto` imports and run define.

## References & templates

| File | Purpose |
|------|---------|
| `references/templates/main-agui-wiring.go.example` | Entrypoint AG-UI sublauncher wiring |
| `references/request-flow.md` | Guided code walkthrough: how a /run_sse request flows through mux auth and the agui handler |
