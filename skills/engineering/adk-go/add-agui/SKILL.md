---
name: add-agui
description: >
  Wires the AG-UI web sublauncher (go.alis.build/adk/launchers/agui, webagui.NewLauncher) into an
  ADK agent entrypoint for CopilotKit and other AG-UI SSE clients. Use when enabling the AG-UI
  protocol, adding a sublauncher beside webui/webapi, or when the user mentions CopilotKit, AG-UI,
  ag-ui, or frontend streaming to the agent—even if they do not say webagui or launchers/agui. Do
  not use for tools.proto or ToolsService (add-tool), long-running operations (add-lro), or embedded
  runtime skills (add-agent-skills). No proto or define step; service id must match infra config.
disable-model-invocation: true
---

# Add AG-UI launcher

Registers the **agui** sublauncher on the existing ADK `web.NewLauncher` stack so clients can use the AG-UI protocol (SSE). One import and one extra sublauncher argument in `main.go`.

Identify the agent module (`go.mod`) and the service id from infra config before editing. In Alis Build projects, the service id is `local.neuron` in `infra/`; if **`.alis/agents/AGENTS.md`** exists, read it for product repo roots.

## When to use

See the skill **description** (primary trigger). One import + sublauncher inside `web.NewLauncher`; no define.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO tools, protos | `../add-tool/SKILL.md`, `../add-lro/SKILL.md` |
| Custom auth/history/A2UI interceptors (full stack) | Follow product-specific patterns beyond this minimal wiring |
| **define** / `tools.proto` | Not required for AG-UI |

## Prerequisites

- ADK agent entrypoint with `universal.NewLauncher(web.NewLauncher(...))` already in place.
- User can **install required dependencies** if `go.alis.build/adk/launchers` is not already in `go.mod` (often present with LRO or other Alis launchers).

## Steps

| # | Action |
|---|--------|
| 1 | Add import: `webagui "go.alis.build/adk/launchers/agui"` |
| 2 | Set service id from infra config (Terraform `locals` or variables) — same value as `lroServiceID` or `weblro.WithServiceID` when LRO is wired |
| 3 | Append sublauncher inside `web.NewLauncher(...)`: `webagui.NewLauncher("<service-id>", webagui.WithCORS(webagui.CORSConfig{}))` |
| 4 | Add `agui` to the launcher CLI args in Dockerfile and Cloud Run / deployment config (see **Deployment: launcher CLI args** below) |
| 5 | Ask user to install/upgrade `go.alis.build/adk/launchers` if needed |
| 6 | `go build ./...` and run the agent locally to verify the AG-UI route is served |

Template: **`references/templates/main-agui-wiring.go.example`**

## Service id

The first argument to `NewLauncher` is the **AG-UI service id**. Use the infra service identifier (e.g. from Terraform `locals` or variables), not the proto package name and not necessarily `llmagent.Config.Name`.

If both LRO and AG-UI are enabled, use the **same** id for `weblro.WithServiceID`, `InitLRO`, and `webagui.NewLauncher`.

### Alis Build projects

The service id is `local.neuron` (or `variables.neuron`) in `infra/`.

## CORS and options

Default wiring uses empty `webagui.CORSConfig{}` (suitable for local dev). For production, adjust `WithCORS` allowed origins per your frontend hosts. Optional `WithInterceptor`, `WithCapabilities`, etc. are out of scope for this minimal skill — see `go.alis.build/adk/launchers/agui` and product examples when needed.

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
- [ ] Agent starts without launcher registration errors

## Pitfalls

- Wrong service id — read the infra config for the agent you are editing, not templates or other agents.
- Adding AG-UI outside `web.NewLauncher` — it must be a **sibling** sublauncher with `webui`, `webapi`, `weblro`, etc.
- Running `go get` before confirming whether `go.alis.build/adk/launchers` is already required — ask user to install dependencies when unsure.
- Missing `agui` in Dockerfile CMD or Cloud Run args — the sublauncher is registered in Go but won't activate without the CLI arg.

## Templates index

| File | Purpose |
|------|---------|
| `references/templates/main-agui-wiring.go.example` | Entrypoint AG-UI sublauncher wiring |
