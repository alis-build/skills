---
name: adk-add-tool
description: >
  Use this skill when the user wants to add a synchronous ADK tool, bootstrap tools.proto, wire
  ToolsService RPCs, or expose a capability to the model via functiontool — even if they do not say
  proto or define. Proto-first tools with define-generated stubs and MyTools wiring. Not for
  LRO/async tools (add-lro), AG-UI (add-agui), or embedded markdown skills (add-agent-skills).
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations.build_repos workstations.define_repos
---

# Add synchronous ADK tools

Proto comments become the model-facing tool description and JSON Schema. Handlers run in-process via ADK `functiontool`; the same service methods can later back gRPC if you register them.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos`.
5. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | Neuron scope for `tools.proto` and handler wiring |
| Neuron build root | `workstations.build_repos` | Go module with `internal/tools` and entrypoint |
| Neuron define tree | `workstations.define_repos` | Define package containing `tools.proto` |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/workspace-tools.md`**, **`references/alis-workspace.md`**, and **`references/define-stubs.md`**. Follow **`references/alis-workspace.md`** resolution order (script → runtime context → MCP → neuron anchors) — never derive paths from another product or chat.

## When to use

See the skill **description** (primary trigger). Sync proto-backed tools only; user runs define.

## When not to use

| Need | Use instead |
|------|-------------|
| Long-running / `google.longrunning.Operation` RPCs | **add-lro** |
| Quick local spike with a one-off inline `functiontool` | OK for experiments only; production agents use this skill |

## Architecture

```
tools.proto  →  define (user, Alis Build DBD)  →  generated Go (JsonSchema + descriptions)
                    ↓
              internal/tools/service.go  (handlers)
                    ↓
              internal/tools/tools.go    (NewTool bridge)
                    ↓
              agent entrypoint Tools: []tool.Tool
```

Why proto-first: RPC comments become `ToolsService_<Rpc>_FullMethodDescription`; request/response shapes come from `JsonSchema()` after the user runs **define** (options in **`references/json-schema.md`**).

Code generation (define) is a user-side operation — the agent does not have access to the build pipeline, so always ask the user to run it.

After proto edits, follow **`references/define-stubs.md`** in order: ask **run a define on the package** (or neuron) → **stop** (no `go.mod`, no Go) → ask user to **install required dependencies** → then implement Go.

## Phase A — Bootstrap (one-time)

Read and follow **`references/bootstrap.md`**.

Summary:

1. Add `tools.proto` from **`references/templates/tools.proto.example`** with `json_schema.generate` enabled (see **`references/json-schema.md`**).
2. Ask the user to **run a define on the neuron** (bootstrap) or **run a define on the package** `<package from tools.proto>`; wait (**`references/define-stubs.md`**).
3. Ask the user to **install required dependencies**; wait.
4. Copy **`references/templates/tools.go.example`** → `internal/tools/tools.go`.
5. Copy **`references/templates/service.go.example`** → `internal/tools/service.go` (start with empty `MyTools()` if only wiring).
6. Copy **`references/templates/auth.go.example`** → `internal/auth/auth.go` if needed.
7. Wire the entrypoint per **`references/templates/agent-wiring.go.example`**.
8. Optionally **`references/templates/grpc.go.example`** when a gRPC server exists.

Replace all `REPLACE_WITH_*` placeholders with your module and protobuf import paths.

## Phase B — Add a sync tool

Read and follow **`references/sync-tool-checklist.md`**.

For each tool:

1. Add RPC + messages + comments to **this agent’s** `tools.proto` (`references/workspace-tools.md`).
2. Ask the user to **run a define on the package** `<proto package>`; **stop** — no `go.mod` or Go yet.
3. Ask the user to **install required dependencies**; wait.
4. Implement handler on `myToolsService`.
5. Register in `MyTools()` with `NewTool` or `NewToolForEmpty`.
6. `go build ./...` and smoke-test via local ADK web.

Naming: tool name **snake_case** (e.g. `lookup_ticket`). Description: `pb.ToolsService_<Rpc>_FullMethodDescription`.

Sensitive actions: pass `WithRequireConfirmation()` to `NewTool` / `NewToolForEmpty`.

## Toolsets (optional)

Group tools with `NewToolSet` and set `llmagent.Config.Toolsets` instead of (or without duplicating) the flat `Tools` slice. See `MyToolsSet()` in **`references/templates/service.go.example`**.

## Verification (always)

- [ ] `tools.proto` edited in the define package from **`alis-workspace.md`** discovery
- [ ] User ran define on the package or neuron (values from **`alis-workspace.md`** discovery via resolve script or MCP, not from this skill)
- [ ] User installed required dependencies after define
- [ ] `go build ./...` passes
- [ ] Tool registered in `MyTools()` with correct snake_case name
- [ ] Required inputs validated with gRPC `InvalidArgument`
- [ ] Local ADK run shows the tool with expected description

## Pitfalls

- Editing a `tools.proto` or agent module that is not in the user’s current workspace — read **`references/workspace-tools.md`**.
- Running define yourself — the agent does not have access to the build pipeline; ask the user.
- `go mod edit` / `go get` protobuf **before** define and install — stubs are not published yet.
- Continuing Go work before define **and** dependency install finish.
- LRO tools → use add-lro; sync and LRO may share `tools.proto`.
- Registering the same tool in both `Tools` and `Toolsets`.

## Templates index

| File | Purpose |
|------|---------|
| `references/workspace-tools.md` | Quick path discovery checklist |
| `references/alis-workspace.md` | Alis Build repo layout and path discovery |
| `references/define-stubs.md` | define → install deps → then Go (strict order, shared) |
| `references/json-schema.md` | JSON Schema proto options (applied when define runs) |
| `references/templates/tools.proto.example` | Starter ToolsService + messages |
| `references/templates/tools.go.example` | NewTool, NewToolForEmpty, NewToolSet |
| `references/templates/service.go.example` | Service + MyTools examples |
| `references/templates/auth.go.example` | Minimal ForwardAuth |
| `references/templates/agent-wiring.go.example` | Entrypoint Tools slice |
| `references/templates/grpc.go.example` | Optional gRPC registration |
