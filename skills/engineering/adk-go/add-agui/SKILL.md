---
name: add-agui
description: >
  Wires the AG-UI web sublauncher (go.alis.build/adk/launchers/agui, webagui.NewLauncher) into an
  ADK agent entrypoint for CopilotKit and other AG-UI SSE clients. Use when enabling the AG-UI
  protocol, adding a sublauncher beside webui/webapi, or when the user mentions CopilotKit, AG-UI,
  ag-ui, or frontend streaming to the agent—even if they do not say webagui or launchers/agui. Do
  not use for tools.proto or ToolsService (add-tool), long-running operations (add-lro), or embedded
  runtime skills (add-agent-skills). No proto or define step; service id must match infra neuron id.
disable-model-invocation: true
---

# Add AG-UI launcher

Registers the **agui** sublauncher on the existing ADK `web.NewLauncher` stack so clients can use the AG-UI protocol (SSE). One import and one extra sublauncher argument in `main.go`.

Read **`../../references/alis-workspace.md`** for neuron path discovery. If **`.alis/agents/AGENTS.md`** exists, read it for product repo roots.

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
| 2 | Set service id to the neuron id from `infra/` (`locals.neuron` / `variables.neuron`) — same value as `lroServiceID` or `weblro.WithServiceID` when LRO is wired |
| 3 | Append sublauncher inside `web.NewLauncher(...)`: `webagui.NewLauncher("<neuron-id>", webagui.WithCORS(webagui.CORSConfig{}))` |
| 4 | Ask user to install/upgrade `go.alis.build/adk/launchers` if needed |
| 5 | `go build ./...` and run the agent locally to verify the AG-UI route is served |

Template: **`references/templates/main-agui-wiring.go.example`**

## Service id

The first argument to `NewLauncher` is the **AG-UI service id**. Use the infra **neuron** string (e.g. from `variables.neuron`), not the proto package name and not necessarily `llmagent.Config.Name`.

If both LRO and AG-UI are enabled, use the **same** id for `weblro.WithServiceID`, `InitLRO`, and `webagui.NewLauncher`.

## CORS and options

Default wiring uses empty `webagui.CORSConfig{}` (suitable for local dev). For production, adjust `WithCORS` allowed origins per your frontend hosts. Optional `WithInterceptor`, `WithCapabilities`, etc. are out of scope for this minimal skill — see `go.alis.build/adk/launchers/agui` and product examples when needed.

## Verification

- [ ] `go build ./...` passes
- [ ] AG-UI sublauncher is inside `web.NewLauncher(...)`, not outside `universal.NewLauncher`
- [ ] Service id matches infra neuron id
- [ ] Agent starts without launcher registration errors

## Pitfalls

- Wrong service id (folder name vs `locals.neuron`) — read `infra/` for the neuron you are editing.
- Adding AG-UI outside `web.NewLauncher` — it must be a **sibling** sublauncher with `webui`, `webapi`, `weblro`, etc.
- Running `go get` before confirming whether `go.alis.build/adk/launchers` is already required — ask user to install dependencies when unsure.
