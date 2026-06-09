# AG-UI request flow

Trace of a single `POST {prefix}/run_sse` request, the authenticated SSE endpoint
a frontend (CopilotKit etc.) calls. Open each file in the module cache at the
pinned version; landmarks are function/type names, stable across patch releases.

## Two layers

1. **Auth** — `go.alis.build/mux/auth.go` (`authMiddleware`). Establishes identity
   before the handler runs.
2. **Handler** — `go.alis.build/adk/launchers/agui/agui.go` (`runSSEFunc`). Parses
   the request, runs interceptors, drives the ADK agent, emits AG-UI SSE events.

## The trace

1. **Route registration** — `agui.go` → `mountHostRoutes`. The endpoint is wired with
   `alismux.AuthenticatedPost(ssePath, l.runSSEFunc(), corsMW...)`. "Authenticated"
   is the key word: auth is not in the agui handler, it's in the mux wrapper.

2. **Authentication** — `mux/auth.go` → `AuthenticatedPost` → `AuthenticatedHandle` →
   `authMiddleware`. This runs *before* the handler:
   - Reads the access token from the `access_token` cookie, falling back to the
     `Authorization: Bearer <token>` header (this is the path the platform gateway
     and `.playground/jwt.go` use).
   - Calls `AuthClient.Authenticate(...)` against `IDENTITY_SERVICE_URL` (set during
     package `init`); refreshes and re-sets cookies if tokens rotated.
   - On success: `iam.MustFromJWT(accessToken)` → `identity.Context(...)` stores the
     identity on the request context.
   - On failure: a browser *navigation* is redirected to the identity service login;
     any other request (i.e. an API/SSE call) gets `401`. So an unauthenticated
     frontend fetch fails closed with 401 — it is not silently anonymous.

3. **Identity in the handler** — `agui.go` → `runSSEFunc`. Decodes the JSON body into
   `types.RunAgentInput`, then reads identity back out with `iam.FromContext(ctx)`,
   setting `callCtx.User.Name = identity.ID` and `Authenticated = true`. **This is the
   join point: `iam.Identity.ID` becomes the ADK user id**, and the AG-UI `threadId`
   maps 1:1 to the ADK session id — so a user only ever sees their own threads.

4. **Interceptors (the auth/authz extension hook)** — `interceptor.go`, `CallInterceptor`.
   `Before(ctx, callCtx, req, httpRequest)` runs after identity is populated and can
   reject (return error → request refused before SSE starts), enrich the context, or
   override `callCtx.User`. The handler then requires a non-empty `User.Name`. This is
   where product-specific authorization (role checks, tenant scoping) belongs —
   identity is already established by step 2; the interceptor decides what they may do.

5. **App-name resolution & thread metadata** — `resolveAppName` picks the target agent
   (request state/context, loader, or the `NewLauncher` default); thread metadata is
   upserted only after interceptors pass, so rejected calls don't bump run counts.

6. **SSE commitment point** — headers (`text/event-stream`), `Flush`, then
   `RunStartedEvent`. After this line, errors can no longer be HTTP status codes — they
   become `RunErrorEvent` on the stream. This is why auth and validation live *before*
   this point.

7. **Running the agent** — `l.runtime.RunSSE(ctx, runReq)` (`internal/adkrun`). The
   handler ranges over ADK events and maps each to AG-UI events via the emitter;
   `CallInterceptor.OnEmit` can observe/mutate/suppress each event before it's written.

8. **Finalization** — `RunFinishedEvent` on success (or `RunErrorEvent`), plus
   pending-interrupt persistence for human-in-the-loop resume.

## Where auth actually lives (summary)

| Concern | Mechanism | File |
|---|---|---|
| Which origins may call (browser) | `WithCORS` → `setCORSOriginHeaders` | `agui.go` |
| Who the caller is (identity) | `authMiddleware` → `iam.MustFromJWT` | `mux/auth.go` |
| What the caller may do (authz) | `CallInterceptor.Before` | your code + `interceptor.go` |
| Identity → ADK user/session | `iam.FromContext` → `callCtx.User.Name`; threadId = sessionId | `agui.go` |

Identity originates upstream: on Alis Build the platform gateway authenticates the
user and forwards a Bearer token; `IDENTITY_SERVICE_URL` is the service the mux layer
validates against. Locally, `.playground/jwt.go` mints a test token (HS256,
`authz-test-key`) carrying `sub`/`email` so you can exercise the path as a fake user.

## Public vs authenticated endpoints

`GET {prefix}/capabilities` is public (registered with `alismux.Get`). Everything else
— `/run_sse`, `/threads/...`, `/agents/state` — is `Authenticated*` and fails closed.
