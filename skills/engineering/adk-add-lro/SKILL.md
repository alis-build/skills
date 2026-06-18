---
name: adk-add-lro
description: >
  Use this skill when the user wants long-running or async ADK tools, google.longrunning.Operation
  handlers, weblro launcher wiring, or conversation resume via /api/run — even if they do not say
  LRO. Bootstraps alis.lro.v2 infra, InitLRO, and resumable tool handlers. Not for sync tools
  (add-tool), AG-UI (add-agui), or embedded runtime skills (add-agent-skills).
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id
    workstations.build_repos workstations.define_repos
---

# Add long-running (LRO) ADK tools

LRO tools return a `google.longrunning.Operation` handle immediately; work continues via Cloud Tasks and Spanner (`alis.lro.v2`). When started from the ADK web UI, completed operations can resume the chat session via `POST /api/run`.

Before creating any new package, search the build module for existing LRO wiring using discovery signals (`InitLRO`, `NewLROTool`, `weblro`). Extend existing packages rather than creating parallel ones. Do not refactor the user's layout to match templates. Templates provide greenfield defaults for new projects only.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos` when proto work is needed.
5. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | LRO service id for `InitLRO`, `weblro.WithServiceID`, and infra |
| Neuron build root | `workstations.build_repos` | Go module with tools, entrypoint, and LRO handlers |
| Neuron define tree | `workstations.define_repos` | Define package for LRO `tools.proto` RPCs |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/workspace-lro.md`**, **`references/alis-workspace.md`**, and **`references/define-stubs.md`**. Follow **`references/alis-workspace.md`** resolution order (script -> runtime context -> MCP -> neuron anchors) — never derive paths from another product or chat.

## When to use

See the skill **description** (primary trigger). LRO proto + infra + InitLRO + optional lroresume; user runs define.

## When not to use

| Need | Use instead |
|------|-------------|
| Synchronous / immediate-return tools | **add-tool** |
| A2A Cloud Tasks resume service (separate HTTP handler) | Out of scope for this skill |
| Running define or terraform apply yourself | Ask the user |

## Prerequisites

- **add-tool** bootstrap (recommended): `tools.proto`, tools package, entrypoint `tools.MyTools()`. If missing, run **add-tool** Phase A first.
- User runs code generation — **`references/define-stubs.md`**.
- Code generation (define) is a user-side operation — the agent does not have access to the build pipeline.

## Architecture

```
tools.proto (LRO RPC + operation_info)
       |  user define
tools service         NewOperation -> ResumeViaTasks -> resumable handler
tools package         NewLROTool (WrapToolContext)
LRO init package      InitLRO + AddResumableHandler
lroresume package     ResumeAfterOperation -> POST /api/run
infra alis.lro.v2     Spanner + Cloud Tasks queue
agent entrypoint      MustInitLRO + weblro sublauncher
```

`lroServiceID` in Go must match `focus_neuron_id` from the resolve script. `lroresume.DefaultAppName` must match `llmagent.Config.Name`.

## Phase A — Bootstrap LRO (one-time)

Read and follow **`references/bootstrap-lro.md`**.

Summary:

1. Add **`references/infra-lro.md`** module under `infra/`.
2. Ensure `tools.proto` imports `google/longrunning/operations.proto`.
3. Ask user to **run a define on the package** or **neuron** -> **stop** -> ask **install required dependencies**.
4. Merge LRO helpers into tools package, add LRO init, copy lroresume, wire entrypoint + `weblro`.

## Phase B — Add an LRO tool

Read and follow **`references/lro-tool-checklist.md`**.

For each tool:

1. Add LRO RPC + messages + `operation_info` to **this agent's** `tools.proto`.
2. define -> install deps -> implement RPC + resumable handler -> `AddResumableHandler` -> `NewLROTool` in `MyTools()`.
3. `go build ./...` and smoke-test locally.

Naming: tool name **snake_case** (e.g. `run_deep_research`). Resume path: **unique kebab-case string** per tool (e.g. `run-deep-research`).

## Deployment: launcher CLI args

The ADK binary uses **positional CLI args** to activate each sublauncher at runtime. Registering `weblro.NewLauncher` in Go is not enough — you must also pass `lro` in the command args when running the binary.

Only include sublauncher args for sublaunchers the agent actually uses. The `lro` sublauncher requires `api` to also be active (for `/api/run` resume). Other sublaunchers (`webui`, `agui`, `scheduler`, etc.) are independent — include them only if the agent uses them.

### Dockerfile

```dockerfile
CMD ["/app/main", "web", "-port", "8080", "api", "lro"]
```

### Cloud Run (Terraform)

```hcl
containers {
  command = ["/app/main"]
  args    = ["web", "-port", "8080", "api", "lro"]
}
```

### Minimal vs full example

The above shows only what LRO requires. A typical agent with web UI might look like:

```
args = ["web", "-port", "8080", "webui", "-api_server_address=/api", "api", "lro"]
```

Add other sublaunchers (`webui`, `agui`, `scheduler`, etc.) only if the agent uses them — they are not LRO prerequisites.

## Verification (always)

- [ ] `tools.proto` LRO RPC has `google.longrunning.operation_info`
- [ ] User ran define on the package or neuron
- [ ] User installed LRO dependencies (`go.alis.build/lro/v2`, `go.alis.build/adk/launchers`, etc.)
- [ ] `lroServiceID` matches `focus_neuron_id` from resolve script (or runtime context)
- [ ] Reasoning engine `deployment_spec` has LRO env vars (`references/infra-lro.md`)
- [ ] Each LRO tool has unique `AddResumableHandler` path
- [ ] Dockerfile CMD and Cloud Run args include `lro` (and `api` for resume)
- [ ] `go build ./...` passes
- [ ] `ResumeAfterOperation` called when ADK chat should continue after completion

## Pitfalls

- Creating new LRO packages without discovering existing ones — search for `InitLRO`, `NewLROTool`, `weblro` before creating
- Refactoring the user's layout to match skill templates without being asked
- Editing protos or code outside the user's current workspace — **`references/workspace-lro.md`**
- Running define or `go mod edit` before define + install finish
- `LRO == nil` at runtime — `MustInitLRO` not called or wrong `serviceID`
- Mismatched neuron id between `focus_neuron_id`, `InitLRO`, and `weblro.WithServiceID` — run the resolve script first; do not read infra Terraform for the id
- Duplicate resume paths across LRO tools
- Using `NewTool` instead of `NewLROTool` for Operation-returning RPCs
- Forgetting `ResumeAfterOperation` when the web session should get the final function response
- Missing LRO env vars on `google_vertex_ai_reasoning_engine` `deployment_spec` — `lro.NewFromEnv` fails at runtime on Agent Engine
- Missing `lro` in Dockerfile CMD or Cloud Run args — the sublauncher is registered in Go but won't activate without the CLI arg
- Implementing sync tools here — use **add-tool**

## Templates index

| File | Purpose |
|------|---------|
| `references/workspace-lro.md` | Path discovery + LRO id alignment |
| `references/bootstrap-lro.md` | One-time LRO bootstrap |
| `references/lro-tool-checklist.md` | Per-tool steps |
| `references/infra-lro.md` | alis.lro.v2 Terraform module |
| `references/resume-flow.md` | /api/run resume semantics |
| `references/define-stubs.md` | Code generation -> install deps -> Go |
| `references/alis-workspace.md` | Agent workspace layout and path discovery |
| `references/json-schema.md` | Input schema options |
| `references/templates/tools.proto.lro-snippet.example` | LRO RPC + messages |
| `references/templates/tools.go.lro-snippet.example` | NewLROTool |
| `references/templates/grpc.go.example` | InitLRO / RegisterGRPC |
| `references/templates/service.lro-handler.example` | RPC + handler + MyTools |
| `references/templates/main-lro-wiring.go.example` | Entrypoint LRO + weblro |
| `references/templates/lroresume/` | Conversation resume package |
| `references/templates/infra/` | LRO Terraform module |
| `references/templates/infra/agent.tf.deployment_spec-lro-envs.example` | Agent Engine LRO env vars |
