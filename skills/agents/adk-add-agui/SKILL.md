---
name: adk-add-agui
description: >
  Use this skill when the user wants to expose an ADK agent to a custom frontend, integrate
  CopilotKit or other AG-UI clients, wire the AG-UI SSE endpoints, add thread history, add AG-UI capabilities and more. Wires
  webagui.NewLauncher with WithThreadService and WithGRPCRegistrar into the web launcher stack.
  For browser UI use add-console after AG-UI wiring.
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations.build_repos workstations.define_repos workstations.infra
---

# Add AG-UI launcher

Registers the **agui** sublauncher on the existing ADK `web.NewLauncher` stack with Spanner-backed thread history (`WithThreadService` + `WithGRPCRegistrar`).

Before creating any new package, search the build module for existing capabilities using the discovery signals documented below. Extend existing packages rather than creating parallel ones. Do not refactor the user's layout to match templates. Templates provide greenfield defaults for new projects only.

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

| Value               | Context field               | If absent (after script + block)                               |
| ------------------- | --------------------------- | -------------------------------------------------------------- |
| Neuron / service id | `focus_neuron_id`           | Discover via resolve script or ask — used to derive `NeuronId` |
| Neuron build root   | `workstations.build_repos`  | Parent of the neuron's `infra/` where `main.go` lives          |
| Neuron define tree  | `workstations.define_repos` | Define package for Spanner proto imports                       |
| Infra directory     | `workstations.infra`        | Terraform for `alis.agui.history.v1` module                    |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/alis-workspace.md`** for path rules and tier 3+ discovery.

## Exposing an agent to users

When the goal is "let users actually use this agent," there are three interface surfaces on the `web` launcher stack:

- **Built-in `webui` + `api`** — the bundled ADK chat UI. Zero frontend code, but you don't control the UX. Best for internal/demo use.
- **`agui` (this skill)** — exposes the agent over the AG-UI protocol so a **custom frontend you own** (CopilotKit, `@ag-ui/adk`, or any AG-UI client) can stream messages, tool calls, and state.
- **add-console** — browser chat UI via a console BFF or bundled SPA. Uses AG-UI under the hood; apply **add-console** when the user wants a browser UI (see **Browser UI** below).

**Authentication.** AG-UI routes use `go.alis.build/mux` auth middleware — `IDENTITY_SERVICE_URL` must be set on the agent deployment. Optional `webagui.WithCORS` and `webagui.WithInterceptor` add cross-origin or per-request hooks. See **`references/request-flow.md`**.

> This skill wires the **agent-side** AG-UI endpoint. For browser UI, BFF reverse-proxy, or gRPC-Web frontend clients, cross-link **add-console** after AG-UI wiring is in place.

## Orientation: how a request flows

When a user wants to understand how AG-UI works or where auth happens — not just wire it — walk them through the real code rather than describing it abstractly. The request path spans two modules:

- `go.alis.build/mux` (`auth.go`) — authentication middleware that establishes identity.
- `go.alis.build/adk/launchers/agui` — the sublauncher that runs the agent and streams AG-UI events.

Open the source in the user's module cache at the version their `go.mod` pins (`go list -m go.alis.build/adk/launchers go.alis.build/mux`, then read under `$(go env GOMODCACHE)`). Follow the trace in **`references/request-flow.md`**.

## When to use

See the skill **description** (primary trigger). Standard install wires: central identity, thread history service, `WithThreadService` + `WithGRPCRegistrar`, define proto imports, Terraform history module, deployment env vars.

### Natural-language → option mapping

Users rarely name `With*` options. Map their intent using **`references/launcher-options.md`** (full catalog). `WithThreadService` and `WithGRPCRegistrar` are **always** wired in the standard install.

| User intent                                 | Option                                                                    |
| ------------------------------------------- | ------------------------------------------------------------------------- |
| Browser frontend on another origin, CORS    | `WithCORS` (add-on — not required when a BFF/console proxies same-origin) |
| Per-request auth/authz at the AG-UI edge    | `WithInterceptor`                                                         |
| CopilotKit predictive / co-agent state      | `WithPredictState`, `WithAgentStateEndpoint`                              |
| Advertise tools, HITL, streaming to clients | `WithCapabilities`                                                        |

## When not to use

| Need                                          | Use instead                                              |
| --------------------------------------------- | -------------------------------------------------------- |
| Sync / LRO tools, protos                      | **add-tool**, **add-lro**                                |
| Bundled Vue web UI, console BFF, browser chat | **add-console** (requires AG-UI; also **add-scheduler**) |
| Scheduled/recurring runs only                 | **add-scheduler**                                        |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(web.NewLauncher(...))` already in place.
- User can **install required dependencies** if not already in `go.mod`: `go.alis.build/adk/launchers`, `go.alis.build/agui/history`, `go.alis.build/mux`.

## Capabilities

This skill introduces three capabilities. For each: discover existing → extend or create → wire → verify contract.

### Capability: Central identity

|                        |                                                                                                                                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contract**           | Exactly one exported source for `AppName` (periods, e.g. `my.neuron.v1`) and `NeuronId` (hyphens, e.g. `my-neuron-v1`). All other packages import from this source. |
| **Discovery signals**  | `AppName`, `NeuronId`, `llmagent.Config.Name`, existing constants package                                                                                           |
| **Wire points**        | Imported by thread history bootstrap, scheduler, `main.go` launcher calls                                                                                           |
| **Greenfield default** | `internal/info/info.go` — see `references/templates/central-identity.go.example`                                                                                    |

**Derivation:** `focus_neuron_id` (hyphenated) = `NeuronId`. Replace `-` with `.` = `AppName`.

**Action:** If a central source already exists, use it. If identity is scattered across packages, consolidate only with user permission. If nothing exists, create from template.

### Capability: Thread history service

|                        |                                                                                                                                                                                                                                                                                           |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contract**           | Package exposes `var Service *historyservice.ThreadService`; constructs via `historyservice.NewThreadService` using central `NeuronId` for Spanner table prefix; env vars: `ALIS_MANAGED_SPANNER_PROJECT`, `ALIS_MANAGED_SPANNER_INSTANCE`, `ALIS_MANAGED_SPANNER_DB`, `ALIS_OS_PROJECT`. |
| **Discovery signals**  | `NewThreadService`, `historyservice`, `agui/history`, `ThreadService`, existing Spanner thread bootstrap                                                                                                                                                                                  |
| **Wire points**        | `webagui.WithThreadService(...)` in the launcher stack                                                                                                                                                                                                                                    |
| **Greenfield default** | `internal/agui/history/history.go` — see `references/templates/thread-service-bootstrap.go.example`                                                                                                                                                                                       |

### Capability: Alis web launcher stack

| | |
|-|-|
| **Contract** | When wiring any `go.alis.build/adk/launchers/*` sublauncher, the web host must import `go.alis.build/adk/launchers/web` — not `google.golang.org/adk/cmd/launcher/web`. Alis sublaunchers (lro, agui, scheduler, console) use `go.alis.build/adk/launchers/*`. Stock ADK sublaunchers without Alis equivalents (api, webui, a2a, agentengine) keep `google.golang.org/adk/cmd/launcher/*` imports as children inside the Alis web host. Do not use a google web host with Alis sublaunchers. `google.golang.org/adk/cmd/launcher/universal` stays unchanged. |
| **Discovery signals** | `google.golang.org/adk/cmd/launcher/web`, `google.golang.org/adk/cmd/launcher/webui`, `webapi`, `weba2a`, `webagentengine` |
| **Wire points** | Entrypoint import block and `universal.NewLauncher(web.NewLauncher(...))` call |
| **Greenfield default** | See `references/templates/agui-launcher-wiring.go.example` |

**Action:** If the entrypoint uses `google.golang.org/adk/cmd/launcher/web` as the web host, replace it with `go.alis.build/adk/launchers/web` before adding `webagui`. Migrate any existing Alis sublaunchers to `go.alis.build/adk/launchers/*`. Stock ADK sublaunchers (webui, api, a2a, agentengine) without Alis equivalents may keep their google imports inside the Alis web host. API surface is similar; Alis web adds mux/auth and other platform behavior. Keep existing sublauncher call order.

### Capability: AG-UI launcher wiring

|                        |                                                                                                                                                                                                                 |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contract**           | `webagui.NewLauncher(appName, webagui.WithThreadService(historyService), webagui.WithGRPCRegistrar(grpcServer))` registered inside `web.NewLauncher(...)`. Host `grpc.Server` with `iam.UnaryInterceptor` + `iam.StreamInterceptor` (`go.alis.build/iam/v3`) registered with `mux.HandleGRPC`. |
| **Discovery signals**  | `webagui.NewLauncher`, `WithThreadService`, `WithGRPCRegistrar`, `iam.UnaryInterceptor`, `iam.StreamInterceptor`, existing AG-UI sublauncher                                                                                                                     |
| **Wire points**        | Agent entrypoint, inside the `web.NewLauncher(...)` call                                                                                                                                                        |
| **Greenfield default** | See `references/templates/agui-launcher-wiring.go.example`                                                                                                                                                      |

## Steps

| #   | Action                                                                                                                                                                                                   |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0   | **Discover** — search the build module for existing central identity, thread history service, and AG-UI wiring using discovery signals above                                                             |
| 1   | **Central identity** — ensure one source for `AppName` + `NeuronId` exists (extend existing or create from template)                                                                                     |
| 2   | **Thread history service** — ensure capability exists (extend existing or create from template); must use central `NeuronId`                                                                             |
| 3   | **Web launcher stack** — if entrypoint imports `google.golang.org/adk/cmd/launcher/web`, migrate web host to `go.alis.build/adk/launchers/web` before adding `webagui`          |
| 4   | **Host gRPC** — ensure `grpc.Server` with `iam.UnaryInterceptor` + `iam.StreamInterceptor` (`go.alis.build/iam/v3`) + `mux.HandleGRPC(grpcServer)` exists (shared with scheduler when both skills apply)                                                                                |
| 5   | **AG-UI launcher** — wire `webagui.NewLauncher(appName, WithThreadService(...), WithGRPCRegistrar(...))` inside `web.NewLauncher(...)` — add `WithCORS` only when user needs cross-origin browser client |
| 6   | **Proto imports** — add orphan imports to define proto (common protobundle); ask user to **run define**                                                                                                  |
| 7   | **Infra** — ensure `alis.agui.history.v1` Terraform module exists in `infra/modules/` and is wired in `main.tf` — see **`references/infra-agui-history.md`**                                             |
| 8   | **Deployment** — add env vars (`ALIS_MANAGED_SPANNER_*`, `ALIS_OS_PROJECT`, `IDENTITY_SERVICE_URL`, `AGENT_SERVICE_URL`) and `agui` CLI arg — Dockerfile CMD **must match** Cloud Run args               |
| 9   | **Dependencies** — ask user to install/upgrade if needed                                                                                                                                                 |
| 10  | **Verify** — `go build ./...` and run locally                                                                                                                                                            |
| 11  | **Browser UI** — if needed, ask whether they want **add-console**                                                                                                                                        |
| 12  | **Orientation** — offer `references/request-flow.md` when relevant                                                                                                                                       |

## Spanner metadata vs session messages

| Data                                               | Storage                       | API                                       |
| -------------------------------------------------- | ----------------------------- | ----------------------------------------- |
| Thread metadata (list, pin, unread, display names) | Spanner (`WithThreadService`) | `GET /agui/threads`, gRPC `ThreadService` |
| Conversation message content                       | ADK `SessionService`          | `GET /agui/threads/{id}/messages`         |

## Proto imports for Spanner tables

History and scheduler protos ship in the **common protobundle** (`go.alis.build/common`) — import only, do not author locally.

Add both orphan imports to **any one** proto in the define package (typically `tools.proto`):

```protobuf
import "alis/a2a/extension/scheduler/v1/scheduler.proto";
import "alis/agui/history/v1/history.proto";
```

Ask the user to **run define** on the package (or neuron). **Also** wire the Terraform history module — define and Terraform are both required. See **`references/infra-agui-history.md`**.

## Launcher options

`webagui.NewLauncher` accepts functional options. Standard install always includes `WithThreadService` + `WithGRPCRegistrar`. See **`references/launcher-options.md`** for the full catalog.

| Option                   | Standard install | Purpose                                         |
| ------------------------ | ---------------- | ----------------------------------------------- |
| `WithThreadService`      | **always**       | Thread metadata + history JSON-RPC              |
| `WithGRPCRegistrar`      | **always**       | Register `ThreadService` on host gRPC           |
| `WithCORS`               | add-on           | Cross-origin browser clients (CopilotKit, etc.) |
| `WithInterceptor`        | add-on           | Per-request auth/authz hooks                    |
| `WithCapabilities`       | add-on           | `GET /capabilities` discovery                   |
| `WithPredictState`       | add-on           | CopilotKit predictive state                     |
| `WithAgentStateEndpoint` | add-on           | On-demand state/messages                        |

CLI flag (not a `With*` option): `-path_prefix` (default `/agui`) after the `agui` keyword.

### Table naming

Go and Terraform must use the same prefix:

```
tablePrefix = replace(ALIS_OS_PROJECT, "-", "_") + "_" + replace(NeuronId, "-", "_")
ThreadsTable          = tablePrefix + "_Threads"
UserThreadStatesTable = tablePrefix + "_UserThreadStates"
```

## Deployment: launcher CLI args and env vars

Registering `webagui.NewLauncher` in Go is not enough — pass `agui` in Dockerfile CMD and Cloud Run args.

**Dockerfile CMD and Cloud Run args must match** — same sublauncher list. Only include sublaunchers you activate at runtime.

### Dockerfile

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "agui"]
```

### Cloud Run (Terraform)

See **`references/templates/infra/cloudrun-args.tf.snippet.example`** for env vars (`IDENTITY_SERVICE_URL`, `AGENT_SERVICE_URL`, Spanner vars).

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "agui"]
}
```

When **add-scheduler** is also wired, append `scheduler` and `-app_name=<AppName>`. See **add-scheduler** for scheduler CLI requirements.

## Browser UI (add-console)

Agent-side AG-UI wiring is a prerequisite for browser chat. **add-console** defaults to `InstallBlock(agentsui)` — a separate Vue BFF that proxies `/agui/*` and gRPC-Web to the agent. For the bundled SPA sublauncher (`console.NewLauncher` in the agent binary) or load balancer setup, use **add-console** after this skill completes.

## Verification

- [ ] One source for `AppName` + `NeuronId` — no duplicates introduced
- [ ] Thread history service exists; uses central `NeuronId` for table prefix; exports `Service`
- [ ] `go build ./...` passes
- [ ] `webagui.NewLauncher(appName, WithThreadService, WithGRPCRegistrar)` inside `web.NewLauncher(...)` from `go.alis.build/adk/launchers/web`
- [ ] No `google.golang.org/adk/cmd/launcher/web` import when `webagui` is wired
- [ ] Host `grpc.Server` with `iam.UnaryInterceptor` + `iam.StreamInterceptor` registered with `mux.HandleGRPC`
- [ ] Proto imports in define; user ran define
- [ ] `infra/modules/alis.agui.history.v1` present; module wired in `infra/main.tf`
- [ ] `local.neuron` / `NEURON` matches central `NeuronId`
- [ ] Application env vars (`ALIS_PROJECT_NR`, Spanner, `IDENTITY_SERVICE_URL`, `AGENT_SERVICE_URL`) in **both** `cloudrun.tf` and `agent.tf` `deployment_spec`
- [ ] `GOOGLE_CLOUD_*` vars on Cloud Run only — not in `deployment_spec`
- [ ] Dockerfile CMD and Cloud Run args include `agui` and **match each other**
- [ ] Agent starts without history initialization errors

## Pitfalls

- Mixing `google.golang.org/adk/cmd/launcher/web` with Alis `webagui` or other `go.alis.build/adk/launchers/*` sublaunchers — migrate web host first
- Creating new packages without discovering existing ones — always search first
- Refactoring the user's layout to match skill templates without being asked
- Passing hyphenated `focus_neuron_id` to `NewLauncher` — use `AppName` (periods)
- Inventing `AppName` independently of discovered neuron id — must be same id, different separator
- Go/TF table prefix mismatch — central `NeuronId` must equal `local.neuron` / module `NEURON`
- Calling `history.RegisterGRPC` when `WithGRPCRegistrar` already set — launcher registers during `SetupHostRoutes`
- Dockerfile CMD differs from Cloud Run args — sublauncher drift
- Skipping define **or** skipping Terraform history module — both required
- Confusing session messages with thread metadata — messages are session-backed; list/pin/unread need Spanner
- Missing `agui` in CLI args — sublauncher won't activate without it
- Missing `IDENTITY_SERVICE_URL` — mux auth on `/agui/*` fails at runtime
- Host `grpc.Server` without `iam.UnaryInterceptor` + `iam.StreamInterceptor` — use `go.alis.build/iam/v3`
- Application env vars added to only one of `cloudrun.tf` or `agent.tf` — same image, both runtimes need them
- `GOOGLE_CLOUD_*` vars added to `deployment_spec` — Reasoning Engine injects these automatically

## References & templates

| File                                                          | Purpose                                          |
| ------------------------------------------------------------- | ------------------------------------------------ |
| `references/templates/agui-launcher-wiring.go.example`        | Entrypoint AG-UI sublauncher wiring              |
| `references/templates/central-identity.go.example`            | Central `AppName` + `NeuronId`                   |
| `references/templates/thread-service-bootstrap.go.example`    | Spanner `ThreadService` bootstrap                |
| `references/templates/infra/history-module.tf.example`        | Full `alis.agui.history.v1` Terraform module     |
| `references/templates/infra/main.tf.snippet.example`          | Module block for `infra/main.tf`                 |
| `references/templates/infra/cloudrun-args.tf.snippet.example` | Cloud Run args + env vars                        |
| `references/templates/infra/agent.tf.deployment_spec-envs.example` | Agent Engine `deployment_spec` env vars     |
| `references/infra-agui-history.md`                            | Define + Terraform + deployment guide            |
| `references/launcher-options.md`                              | All `NewLauncher` options, trigger words, routes |
| `references/request-flow.md`                                  | Auth → handler → SSE code walkthrough            |
| `references/alis-workspace.md`                                | Path discovery and workspace rules               |
