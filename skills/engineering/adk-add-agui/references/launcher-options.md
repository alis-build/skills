# AG-UI launcher options (`go.alis.build/adk/launchers/agui`)

`webagui.NewLauncher(appName, opts...)` registers the AG-UI sublauncher. The first argument is the **ADK app name** (`info.AppName` — must match `llmagent.Config.Name`). Standard install always includes `WithThreadService` + `WithGRPCRegistrar`.

Read the pinned module source when details drift: `go list -m go.alis.build/adk/launchers`, then `$(go env GOMODCACHE)/go.alis.build/adk/launchers@<version>/agui/`.

## Trigger words → option

When the user asks for a capability in natural language, map it to the option below. `WithThreadService` and `WithGRPCRegistrar` are **always** wired in the standard install.

| User says (examples) | Option | Standard install |
|----------------------|--------|------------------|
| thread history, threads, conversation history, thread list, thread metadata, unread/pinned threads | `WithThreadService` | **always** |
| history JSON-RPC, ThreadService gRPC, gRPC-Web history | `WithGRPCRegistrar` | **always** (requires `WithThreadService`; host `mux.HandleGRPC`) |
| CORS, cross-origin, browser frontend, SPA on different port, CopilotKit from localhost:3000 | `WithCORS` | add-on (omit when BFF/console proxies same-origin) |
| auth interceptor, per-request auth, authorize requests, inspect identity, edge auth | `WithInterceptor` | add-on |
| capabilities, feature discovery, GET /capabilities, advertise tools/HITL | `WithCapabilities` | add-on |
| CopilotKit co-agent state, predictive state, optimistic state preview, useCoAgentStateRender | `WithPredictState` | add-on |
| agent state endpoint, on-demand state/messages, useCoAgentState without a run | `WithAgentStateEndpoint` | add-on |
| messages snapshot at run end, full history without streaming TEXT_MESSAGE_* | `WithMessagesSnapshotOnRunEnd` | add-on |
| multi-agent routing, custom app name resolution | `WithAppNameResolver` | add-on |
| custom part mapping, generative UI parts, A2UI payloads, override genai.Part → AG-UI events | `WithGenAIPartConverter` | add-on |
| history JSON-RPC CORS | `WithHistoryJSONRPCOptions` | add-on (requires `WithThreadService`) |

**Thread metadata** (list, pin, unread, display names) requires `WithThreadService`. **Session message history** (`GET /threads/{id}/messages`) uses ADK sessions and works whenever AG-UI is wired, but thread listing does not without `WithThreadService`.

## Options reference

### `WithCORS(cors CORSConfig)`

Enables CORS on AG-UI routes and OPTIONS preflight. Use when the frontend origin differs from the agent server (CopilotKit, Vue/React SPAs calling the agent directly). Omit when a console BFF reverse-proxies `/agui/*` same-origin.

`CORSConfig`: `AllowedOrigins`, `AllowedHeaders` (default `Content-Type`, `Authorization`), `ExposeHeaders`, `AllowCredentials`.

### `WithInterceptor(interceptor CallInterceptor)`

Hooks around each `/run_sse` request: `Before` (reject/enrich before SSE), `OnEmit` (mutate/suppress SSE events), `After` (cleanup, reverse order). Handler pre-fills `CallContext.User` from mux IAM identity; interceptors may override. Embed `PassthroughInterceptor` for partial impls.

### `WithCapabilities(caps Capabilities)`

Registers `GET {path_prefix}/capabilities` (public). Clients discover streaming, tools, HITL, multimodal, etc. `MergeInterruptCapabilities` and `MergeClientToolCapabilities` run automatically — set `humanInTheLoop.interrupts` / `approveWithEdits` to `false` to opt out.

### `WithThreadService(svc *historyservice.ThreadService)`

Enables thread **metadata** backed by Spanner:

- `GET /threads` — list with unread/pinned state
- `GET /threads/{threadId}` — single thread metadata
- `DELETE /threads/{threadId}` — delete thread
- Each `/run_sse` upserts metadata (run count, last activity, display name on first run)
- Mounts history JSON-RPC at `POST /alis.agui.history.v1.ThreadService`

Does **not** replace ADK `SessionService` — conversation events still live in the session store.

### `WithGRPCRegistrar(reg grpc.ServiceRegistrar)`

Registers `ThreadService` on the host gRPC server during `SetupHostRoutes`. **Requires `WithThreadService`.** Pass the same `grpc.Server` used with `mux.HandleGRPC`. Do not call `threadService.Register` separately for the same instance.

### `WithHistoryJSONRPCOptions(opts ...historyjsonrpc.JSONRPCHandlerOption)`

Forwards options (e.g. CORS) to the history JSON-RPC handler. Requires `WithThreadService`.

### `WithGenAIPartConverter(converter GenAIPartConverter)`

Override mapping of `genai.Part` → AG-UI events before default handling. Return non-nil slice to handle; `(nil, nil)` to fall through.

### `WithMessagesSnapshotOnRunEnd()`

Emit `MESSAGES_SNAPSHOT` before `RunFinished` on every successful run (not only interrupt boundaries).

### `WithPredictState(mappings ...PredictStateMapping)`

Emit `PredictState` custom events before matching tool calls (CopilotKit `useCoAgentStateRender`). Fields: `StateKey`, `Tool`, `ToolArgument`.

### `WithAgentStateEndpoint()`

Registers `POST {path_prefix}/agents/state` — returns thread state and messages without starting a run (CopilotKit `useCoAgentState`).

### `WithAppNameResolver(resolver AppNameResolver)`

Custom app name extraction from `RunAgentInput` before state/context/default chain. Validates against `AgentLoader.ListAgents` when multi-agent.

## CLI flag (not a `With*` option)

After the `agui` keyword on the web command line:

| Flag | Default | Purpose |
|------|---------|---------|
| `-path_prefix` | `/agui` | URL prefix for all AG-UI routes |

Example: `web -port 8080 agui -path_prefix=/api/agui`

## Standard AG-UI wiring

Templates (capability-named):
- `references/templates/central-identity.go.example` — central `AppName` + `NeuronId`
- `references/templates/thread-service-bootstrap.go.example` — Spanner `ThreadService`
- `references/templates/agui-launcher-wiring.go.example` — entrypoint wiring

Infra: **`references/infra-agui-history.md`**

Discover existing capabilities before creating new packages. The steps below use greenfield default paths as examples only.

1. **Central identity** — single source for `AppName` + `NeuronId` (discover existing or create).
2. **Thread history** — `ThreadService` bootstrap using central `NeuronId` for table prefix.
3. **Entrypoint** — host `grpc.Server`, `mux.HandleGRPC(grpcServer)`, then:

```go
webagui.NewLauncher(info.AppName,
    webagui.WithThreadService(history.Service),
    webagui.WithGRPCRegistrar(grpcServer),
)
```

4. **Proto imports** (common protobundle) + run define + Terraform history module.
5. **Deployment** — `agui` CLI arg; Dockerfile CMD must match Cloud Run args.

Add `WithCORS(webagui.CORSConfig{...})` only when the browser client calls the agent from a different origin.

## Routes summary

| Route | Requires |
|-------|----------|
| `POST /agui/run_sse` | AG-UI wired (always) |
| `GET /agui/threads/{id}/messages` | AG-UI wired (session history) |
| `GET /agui/threads`, `GET/DELETE /agui/threads/{id}` | `WithThreadService` (standard install) |
| `POST /alis.agui.history.v1.ThreadService` (JSON-RPC) | `WithThreadService` (standard install) |
| `GET /agui/capabilities` | `WithCapabilities` |
| `POST /agui/agents/state` | `WithAgentStateEndpoint` |
