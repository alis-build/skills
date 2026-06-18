---
name: adk-add-agui
description: >
  Use this skill when the user wants to expose an ADK agent to a custom frontend, integrate
  CopilotKit or other AG-UI clients, wire the AG-UI SSE endpoint, add thread history or threads
  (WithThreadService), or put CORS/auth at the agent edge — even if they do not say ag-ui or
  webagui. Wires webagui.NewLauncher into the web launcher stack. Not for sync tools (add-tool),
  LRO (add-lro), embedded runtime skills (add-agent-skills), or the bundled Vue console
  (add-console).
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations.build_repos workstations.define_repos
---

# Add AG-UI launcher

Registers the **agui** sublauncher on the existing ADK `web.NewLauncher` stack so clients can use the AG-UI protocol (SSE). One import and one extra sublauncher argument in `main.go`.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos` when proto work is needed.
5. **Ask user** — Smallest missing piece only (which `go.mod` when several exist).

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths — use `focus_neuron_id` and `workstations` from the resolve script (or runtime context).

### Context fields (`alis.context.requires`)

Path-valued fields live on `workstations`; use the entry for the current workstation.

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | AG-UI service id and neuron scope — obtain via resolve script or ask |
| Neuron build root | `workstations.build_repos` | Parent of the neuron's `infra/` where `main.go` lives |
| Neuron define tree | `workstations.define_repos` | Define package for optional Spanner proto imports (`history.proto`, `scheduler.proto`) |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/alis-workspace.md`** for path rules and tier 3+ discovery. Use `focus_neuron_id` from the script or runtime context as the service id and `workstations.build_repos` for the agent module.

## Exposing an agent to users

When the goal is "let users actually use this agent," there are three interface surfaces on the `web` launcher stack:

- **Built-in `webui` + `api`** — the bundled ADK chat UI. Zero frontend code, but you don't control the UX. Best for internal/demo use.
- **`agui` (this skill)** — exposes the agent over the AG-UI protocol so a **custom frontend you own** (CopilotKit, or any AG-UI client) can stream messages, tool calls, and state. Choose this for a product-grade, branded, or embedded interface you build separately.
- **add-console** (`console` sublauncher) — bundled Vue web UI served from the agent (chat shell, branding, `/auth/me`). Uses AG-UI under the hood; choose when the user wants a browser UI without building a separate frontend project.

**Authentication.** AG-UI is the edge your frontend connects to, so it's where you *enforce* auth — `webagui.WithCORS` (which origins may connect) and `webagui.WithInterceptor` (inspect the request, read identity). It does **not** implement login or mint identity: on Alis Build the platform gateway injects the caller identity (Bearer JWT) ahead of the service, and your interceptor consumes it. For the login/identity mechanism itself, follow the product's auth pattern — this skill only wires the layer where auth is applied.

> A separate frontend (e.g. CopilotKit) or the bundled SPA (**add-console**) are **not** part of this skill — this skill only wires the AG-UI endpoint. If the user also needs or wants a UI, frontend, console, or chat UI in the browser, **ask** whether they want to use **add-console** after AG-UI wiring is in place; wait for confirmation before applying that skill.

## Orientation: how a request flows

When a user wants to understand how AG-UI works or where auth happens — not just wire it — walk them through the real code rather than describing it abstractly. The request path spans two modules:

- `go.alis.build/mux` (`auth.go`) — authentication middleware that establishes identity.
- `go.alis.build/adk/launchers/agui` — the sublauncher that runs the agent and streams AG-UI events.

Open the source in the user's module cache at the version their `go.mod` pins (`go list -m go.alis.build/adk/launchers go.alis.build/mux`, then read under `$(go env GOMODCACHE)`). Follow the trace in **`references/request-flow.md`**, which names files and functions (not line numbers, which drift between versions).

## When to use

See the skill **description** (primary trigger). One import + sublauncher inside `web.NewLauncher`; proto imports + define for Spanner tables when `WithThreadService` is used.

### Natural-language → option mapping

Users rarely name `With*` options. Map their intent using **`references/launcher-options.md`** (full catalog). Common mappings:

| User intent | Option |
|-------------|--------|
| Thread history, threads, conversation history, thread list/metadata | `WithThreadService` |
| Browser frontend on another origin, CORS | `WithCORS` |
| Per-request auth/authz at the AG-UI edge | `WithInterceptor` |
| CopilotKit predictive / co-agent state | `WithPredictState`, `WithAgentStateEndpoint` |
| Advertise tools, HITL, streaming to clients | `WithCapabilities` |

**Thread history** = `WithThreadService` + `internal/agui/history` Spanner service + proto imports + define. Session messages (`GET /threads/{id}/messages`) work without it; thread **metadata** (list, pin, unread) does not.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO tools, protos | **add-tool**, **add-lro** |
| Bundled Vue web UI (console launcher, branding, chat shell) | **add-console** (requires AG-UI; also **add-scheduler**) |
| Custom auth/history/A2UI interceptors (full stack) | Follow product-specific patterns beyond this minimal wiring |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(web.NewLauncher(...))` already in place.
- User can **install required dependencies** if `go.alis.build/adk/launchers` is not already in `go.mod` (often present with LRO or other Alis launchers).

## Steps

| # | Action |
|---|--------|
| 1 | Add import: `webagui "go.alis.build/adk/launchers/agui"` |
| 2 | Set service id from `focus_neuron_id` (resolve script or runtime context). Reuse `lroServiceID` only when it already matches that id |
| 3 | Append sublauncher inside `web.NewLauncher(...)`: `webagui.NewLauncher("<app-name>", webagui.WithCORS(webagui.CORSConfig{}))` — add other options from **Launcher options** when the user needs them |
| 4 | When user wants thread history / threads: add `webagui.WithThreadService(...)`, usually `webagui.WithGRPCRegistrar(grpcServer)`; scaffold `internal/agui/history` (see **Thread history (WithThreadService)**); add proto imports and ask user to run define |
| 5 | Add `agui` to the launcher CLI args in Dockerfile and Cloud Run / deployment config (see **Deployment: launcher CLI args** below) |
| 6 | Ask user to install/upgrade `go.alis.build/adk/launchers` if needed |
| 7 | `go build ./...` and run the agent locally to verify the AG-UI route is served |
| 8 | If the user needs or wants a browser UI (frontend, console, chat UI) and does not already have a separate AG-UI client, **ask** whether they want **add-console** for the bundled Vue web UI — do not auto-apply; wait for confirmation |
| 9 | Offer to orient the user in how a request flows (auth → handler → SSE) using `references/request-flow.md`. Recommended when the user is new to AG-UI or asked about auth / exposing to users; skip if they only wanted the wiring |

Template: **`references/templates/main-agui-wiring.go.example`**

## Service id

The first argument to `NewLauncher` is the **AG-UI service id**. Use `focus_neuron_id` from the resolve script (or runtime context) — not the proto package name and not necessarily `llmagent.Config.Name`.

If both LRO and AG-UI are enabled, use the **same** `focus_neuron_id` for `weblro.WithServiceID`, `InitLRO`, and `webagui.NewLauncher`.

## Proto imports for Spanner tables

AG-UI thread/history storage uses Spanner tables provisioned through define. Add the following imports to **any one** proto in the agent's define package (typically `tools.proto`), even if nothing in the file references them:

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Add **both** imports whenever threads/history Spanner tables are required — even if the agent does not use the scheduler yet. The imports are for table provisioning, not for RPC definitions in your service.

Ask the user to **run define** on the package (or neuron) after editing the proto. Add **both** imports whenever either thread/history or scheduler Spanner tables are needed — the same rule applies for **add-scheduler**.

## Launcher options

`webagui.NewLauncher` accepts functional options. Default minimal wiring: `WithCORS(webagui.CORSConfig{})`. Add options when the user's request maps to them (see **`references/launcher-options.md`** for the full table, trigger words, and routes).

| Option | Purpose |
|--------|---------|
| `WithCORS` | Browser frontends on a different origin (required for most SPAs) |
| `WithInterceptor` | Per-request auth/authz and SSE event hooks |
| `WithThreadService` | Thread metadata (list, pin, unread) + history JSON-RPC — **thread history** |
| `WithGRPCRegistrar` | Register `ThreadService` on host gRPC (requires `WithThreadService`) |
| `WithHistoryJSONRPCOptions` | CORS etc. for history JSON-RPC handler |
| `WithCapabilities` | `GET /capabilities` discovery document |
| `WithGenAIPartConverter` | Custom `genai.Part` → AG-UI event mapping |
| `WithMessagesSnapshotOnRunEnd` | Full message snapshot before every successful `RunFinished` |
| `WithPredictState` | CopilotKit predictive state custom events |
| `WithAgentStateEndpoint` | `POST /agents/state` on-demand state/messages |
| `WithAppNameResolver` | Custom multi-agent app name resolution |

CLI flag (not a `With*` option): `-path_prefix` (default `/agui`) after the `agui` keyword.

For production CORS, set `AllowedOrigins` to frontend hosts — empty `CORSConfig{}` is fine for local dev. `WithInterceptor` is product-specific (see **Authentication** and `references/request-flow.md`).

### Thread history (`WithThreadService`)

When the user wants **thread history**, **threads**, or **thread metadata** on AG-UI:

1. Scaffold **`internal/agui/history`** — `historyservice.NewThreadService` with Spanner env vars and neuron-scoped table prefix (see `alis/build/ge/test/agent/v1/agent/internal/agui/history/history.go`).
2. In `main.go`, create a host `grpc.Server`, `mux.HandleGRPC(grpcServer)`, then pass the service and registrar:

```go
webagui.NewLauncher(adkAppName,
    webagui.WithThreadService(history.Service),
    webagui.WithCORS(webagui.CORSConfig{}),
    webagui.WithGRPCRegistrar(grpcServer),
)
```

3. Add proto imports (below) and run define.
4. `agui` CLI arg is unchanged.

Without `WithThreadService`, `/run_sse` and `GET /threads/{id}/messages` (session-backed) still work; `GET /threads` listing and JSON-RPC history do not.

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
- [ ] Service id matches `focus_neuron_id` from resolve script (or runtime context)
- [ ] Dockerfile CMD and Cloud Run args include `agui`
- [ ] When thread history requested: `WithThreadService` (+ `WithGRPCRegistrar` if using host gRPC), `internal/agui/history` wired
- [ ] Proto imports for history (and scheduler) Spanner tables present when `WithThreadService` used; user ran define
- [ ] Agent starts without launcher registration errors

## Pitfalls

- Wrong service id — use `focus_neuron_id` from the resolve script, not infra Terraform locals or templates from other agents.
- Adding AG-UI outside `web.NewLauncher` — it must be a **sibling** sublauncher with `webui`, `webapi`, `weblro`, etc.
- Running `go get` before confirming whether `go.alis.build/adk/launchers` is already required — ask user to install dependencies when unsure.
- Missing `agui` in Dockerfile CMD or Cloud Run args — the sublauncher is registered in Go but won't activate without the CLI arg.
- Skipping proto imports for Spanner tables — `WithThreadService` storage will not be provisioned; add both `scheduler.proto` and `history.proto` imports and run define.
- Confusing session message history with thread metadata — `GET /threads/{id}/messages` uses ADK sessions; thread list/pin/unread requires `WithThreadService`.
- Calling `threadService.Register` manually when `WithGRPCRegistrar` is already set — the launcher registers it during `SetupHostRoutes`.

## References & templates

| File | Purpose |
|------|---------|
| `references/templates/main-agui-wiring.go.example` | Entrypoint AG-UI sublauncher wiring |
| `references/launcher-options.md` | All `NewLauncher` options, trigger words, routes, thread-history reference wiring |
| `references/request-flow.md` | Guided code walkthrough: how a /run_sse request flows through mux auth and the agui handler |
