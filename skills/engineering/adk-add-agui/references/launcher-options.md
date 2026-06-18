# AG-UI launcher options (`go.alis.build/adk/launchers/agui`)

`webagui.NewLauncher(appName, opts...)` registers the AG-UI sublauncher. The first argument is the **ADK app name** (root agent name for step filtering and default routing). Options are functional `webagui.Option` values.

Read the pinned module source when details drift: `go list -m go.alis.build/adk/launchers`, then `$(go env GOMODCACHE)/go.alis.build/adk/launchers@<version>/agui/`.

## Trigger words → option

When the user asks for a capability in natural language, map it to the option below. Apply only what they need — minimal wiring is still `WithCORS` only.

| User says (examples) | Option | Also required |
|----------------------|--------|---------------|
| thread history, threads, conversation history, chat history, thread list, thread metadata, unread/pinned threads, persist threads, thread sidebar | `WithThreadService` | Proto imports + define; usually `WithGRPCRegistrar` + `internal/agui/history` |
| history JSON-RPC, ThreadService gRPC, gRPC-Web history | `WithGRPCRegistrar` | `WithThreadService`; host `mux.HandleGRPC` |
| CORS, cross-origin, browser frontend, SPA on different port, CopilotKit from localhost:3000 | `WithCORS` | `CORSConfig.AllowedOrigins` in production |
| auth interceptor, per-request auth, authorize requests, inspect identity, edge auth | `WithInterceptor` | Product-specific `CallInterceptor` impl |
| capabilities, feature discovery, GET /capabilities, advertise tools/HITL | `WithCapabilities` | Populate only supported fields |
| CopilotKit co-agent state, predictive state, optimistic state preview, useCoAgentStateRender | `WithPredictState` | `PredictStateMapping` per tool |
| agent state endpoint, on-demand state/messages, useCoAgentState without a run | `WithAgentStateEndpoint` | — |
| messages snapshot at run end, full history without streaming TEXT_MESSAGE_* | `WithMessagesSnapshotOnRunEnd` | — |
| multi-agent routing, custom app name resolution | `WithAppNameResolver` | Multi-agent `AgentLoader` |
| custom part mapping, generative UI parts, A2UI payloads, override genai.Part → AG-UI events | `WithGenAIPartConverter` | — |
| history JSON-RPC CORS | `WithHistoryJSONRPCOptions` | `WithThreadService` |

**Thread history** always means `WithThreadService` — not a separate package or interceptor. Session message history (`GET /threads/{id}/messages`) is always available when AG-UI is wired; **thread metadata** (list, pin, unread, display names) requires `WithThreadService`.

## Options reference

### `WithCORS(cors CORSConfig)`

Enables CORS on AG-UI routes and OPTIONS preflight. Required when the frontend origin differs from the agent server (CopilotKit, Vue/React SPAs).

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

Does **not** replace ADK `SessionService` — conversation events still live in the session store. `GET /threads/{threadId}/messages` works without `WithThreadService` but only returns session-backed messages.

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

## Thread history wiring (reference agent)

Pattern from `alis/build/ge/test/agent/v1/agent`:

1. **`internal/agui/history/history.go`** — construct shared `*historyservice.ThreadService` in `init()` from Spanner env vars and neuron-scoped table names.
2. **`main.go`** — create host `grpc.Server`, `mux.HandleGRPC(grpcServer)`, then:

```go
webagui.NewLauncher(adkAppName,
    webagui.WithThreadService(history.Service),
    webagui.WithCORS(webagui.CORSConfig{}),
    webagui.WithGRPCRegistrar(grpcServer),
)
```

3. **Proto imports** — `alis/agui/history/v1/history.proto` (+ `scheduler.proto` for define table provisioning); run define.
4. **Deployment** — `agui` CLI arg unchanged.

When the user only needs SSE streaming without thread sidebar/metadata, skip `WithThreadService` and the history package.

## Routes summary

| Route | Requires |
|-------|----------|
| `POST /agui/run_sse` | AG-UI wired (always) |
| `GET /agui/threads/{id}/messages` | AG-UI wired (session history) |
| `GET /agui/threads`, `GET/DELETE /agui/threads/{id}` | `WithThreadService` |
| `POST /alis.agui.history.v1.ThreadService` (JSON-RPC) | `WithThreadService` |
| `GET /agui/capabilities` | `WithCapabilities` |
| `POST /agui/agents/state` | `WithAgentStateEndpoint` |
