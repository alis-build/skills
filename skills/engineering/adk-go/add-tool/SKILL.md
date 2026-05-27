---
name: add-tool
description: >
  Adds synchronous ADK tools using proto-first tools.proto, define-generated stubs, and
  functiontool wrappers (NewTool, MyTools). Use when bootstrapping internal/tools, adding a
  ToolsService RPC, wiring tools.MyTools into the entrypoint, or when the user asks to add a
  tool, expose a capability to the model, tools.proto, JsonSchema, or register a function
  tool—even if they do not say proto, ToolsService, or define. Do not use for
  google.longrunning.Operation or async jobs (add-lro), AG-UI launcher (add-agui), or embedded
  markdown skills under internal/skills (add-agent-skills). Agent must not run define; user runs
  define then installs dependencies.
---

# Add synchronous ADK tools

Proto comments become the model-facing tool description and JSON Schema. Handlers run in-process via ADK `functiontool`; the same service methods can later back gRPC if you register them.

**Start with `references/workspace.md`**, **`references/alis-workspace.md`**, and **`references/define-stubs.md`**. Discover this agent’s code generation and build paths from open folders — never from another product or chat.

## When to use

See the skill **description** (primary trigger). Sync proto-backed tools only; user runs define.

## When not to use

| Need | Use instead |
|------|-------------|
| Long-running / `google.longrunning.Operation` RPCs | `../add-lro/SKILL.md` |
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

**Never run define yourself** — it is part of Alis Build’s define-build-deploy (DBD) toolchain, not an agent capability.

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

1. Add RPC + messages + comments to **this agent’s** `tools.proto` (`references/workspace.md`).
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

- [ ] `tools.proto` edited in the define package discovered for this workspace
- [ ] User ran define on the package or neuron (values from workspace, not from this skill)
- [ ] User installed required dependencies after define
- [ ] `go build ./...` passes
- [ ] Tool registered in `MyTools()` with correct snake_case name
- [ ] Required inputs validated with gRPC `InvalidArgument`
- [ ] Local ADK run shows the tool with expected description

## Pitfalls

- Editing a `tools.proto` or agent module that is not in the user’s current workspace — read **`references/workspace.md`**.
- Running define yourself — you cannot; ask the user.
- `go mod edit` / `go get` protobuf **before** define and install — stubs are not published yet.
- Continuing Go work before define **and** dependency install finish.
- LRO tools → use add-lro; sync and LRO may share `tools.proto`.
- Registering the same tool in both `Tools` and `Toolsets`.

## Templates index

| File | Purpose |
|------|---------|
| `references/workspace.md` | Quick path discovery checklist |
| `references/alis-workspace.md` | Alis build vs define repos, neuron layout (shared) |
| `references/define-stubs.md` | define → install deps → then Go (strict order, shared) |
| `references/json-schema.md` | JSON Schema proto options (applied when define runs) |
| `references/templates/tools.proto.example` | Starter ToolsService + messages |
| `references/templates/tools.go.example` | NewTool, NewToolForEmpty, NewToolSet |
| `references/templates/service.go.example` | Service + MyTools examples |
| `references/templates/auth.go.example` | Minimal ForwardAuth |
| `references/templates/agent-wiring.go.example` | Entrypoint Tools slice |
| `references/templates/grpc.go.example` | Optional gRPC registration |
