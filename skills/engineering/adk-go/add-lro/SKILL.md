---
name: add-lro
description: >
  Adds long-running ADK tools backed by google.longrunning.Operation, go.alis.build/lro/v2, alis.lro.v2
  infra, weblro launcher, resumable handlers, and /api/run conversation resume. Use when bootstrapping
  LRO on an agent, adding operation_info RPCs, InitLRO, NewLROTool, Cloud Tasks operations, or when
  the user mentions long-running tools, async tools, deep research operations, lroresume, or work
  that returns an operation handle—even if they do not say LRO or longrunning. Do not use for
  immediate-return sync tools (add-tool), AG-UI (add-agui), or embedded SKILL.md skills
  (add-agent-skills). User runs define then installs dependencies; agent must not run define.
disable-model-invocation: true
---

# Add long-running (LRO) ADK tools

LRO tools return a `google.longrunning.Operation` handle immediately; work continues via Cloud Tasks and Spanner (`alis.lro.v2`). When started from the ADK web UI, completed operations can resume the chat session via `POST /api/run`.

**Start with `references/workspace.md`**, **`../../references/alis-workspace.md`**, and **`../../references/define-stubs.md`**. If **`.alis/agents/AGENTS.md`** exists, read it first. Discover this neuron’s define/build/infra paths from open folders — never from another product or chat.

## When to use

See the skill **description** (primary trigger). LRO proto + infra + InitLRO + optional lroresume; user runs define.

## When not to use

| Need | Use instead |
|------|-------------|
| Synchronous / immediate-return tools | `../add-tool/SKILL.md` |
| A2A Cloud Tasks resume service (separate HTTP handler) | Out of scope for this skill |
| Running define or terraform apply yourself | Ask the user |

## Prerequisites

- **add-tool** bootstrap (recommended): `tools.proto`, `internal/tools`, entrypoint `tools.MyTools()`. If missing, run **add-tool** Phase A first.
- User runs **define** via Alis Build DBD — **`../../references/define-stubs.md`**.
- **Never run define yourself.**

## Architecture

```
tools.proto (LRO RPC + operation_info)
       ↓  user define
internal/tools/service.go   NewOperation → ResumeViaTasks → resumable handler
internal/tools/tools.go     NewLROTool (WrapToolContext)
internal/tools/grpc.go      InitLRO + AddResumableHandler
internal/lroresume          ResumeAfterOperation → POST /api/run
infra alis.lro.v2           Spanner + Cloud Tasks queue
agent entrypoint            MustInitLRO + weblro sublauncher
```

`lroServiceID` in Go must match infra `local.neuron`. `lroresume.DefaultAppName` must match `llmagent.Config.Name`.

## Phase A — Bootstrap LRO (one-time)

Read and follow **`references/bootstrap-lro.md`**.

Summary:

1. Add **`references/infra-lro.md`** module under `infra/`.
2. Ensure `tools.proto` imports `google/longrunning/operations.proto`.
3. Ask user to **run a define on the package** or **neuron** → **stop** → ask **install required dependencies**.
4. Merge LRO helpers into `tools.go`, add `grpc.go`, copy `internal/lroresume`, wire entrypoint + `weblro`.

## Phase B — Add an LRO tool

Read and follow **`references/lro-tool-checklist.md`**.

For each tool:

1. Add LRO RPC + messages + `operation_info` to **this agent’s** `tools.proto`.
2. define → install deps → implement RPC + resumable handler → `AddResumableHandler` → `NewLROTool` in `MyTools()`.
3. `go build ./...` and smoke-test locally.

Naming: tool name **snake_case** (e.g. `run_deep_research`). Resume path: **unique kebab-case string** per tool (e.g. `run-deep-research`).

## Verification (always)

- [ ] `tools.proto` LRO RPC has `google.longrunning.operation_info`
- [ ] User ran define on the package or neuron
- [ ] User installed LRO dependencies (`go.alis.build/lro/v2`, `go.alis.build/adk/launchers`, etc.)
- [ ] `lroServiceID` matches infra neuron id
- [ ] Reasoning engine `deployment_spec` has LRO env vars (`references/infra-lro.md`)
- [ ] Each LRO tool has unique `AddResumableHandler` path
- [ ] `go build ./...` passes
- [ ] `ResumeAfterOperation` called when ADK chat should continue after completion

## Pitfalls

- Editing protos or code outside the user’s current workspace — **`references/workspace.md`**.
- Running define or `go mod edit` before define + install finish.
- `LRO == nil` at runtime — `MustInitLRO` not called or wrong `serviceID`.
- Mismatched neuron id between infra, `InitLRO`, and `weblro.WithServiceID`.
- Duplicate resume paths across LRO tools.
- Using `NewTool` instead of `NewLROTool` for Operation-returning RPCs.
- Forgetting `ResumeAfterOperation` when the web session should get the final function response.
- Missing LRO env vars on `google_vertex_ai_reasoning_engine` `deployment_spec` — `lro.NewFromEnv` fails at runtime on Agent Engine.
- Implementing sync tools here — use **add-tool**.

## Templates index

| File | Purpose |
|------|---------|
| `references/workspace.md` | Path discovery + LRO id alignment |
| `references/bootstrap-lro.md` | One-time LRO bootstrap |
| `references/lro-tool-checklist.md` | Per-tool steps |
| `references/infra-lro.md` | alis.lro.v2 Terraform module |
| `references/resume-flow.md` | /api/run resume semantics |
| `../../references/define-stubs.md` | define → install deps → Go (shared) |
| `../../references/alis-workspace.md` | Build vs define repos (shared) |
| `../add-tool/references/json-schema.md` | Input schema options |
| `references/templates/tools.proto.lro-snippet.example` | LRO RPC + messages |
| `references/templates/tools.go.lro-snippet.example` | NewLROTool |
| `references/templates/grpc.go.example` | InitLRO / RegisterGRPC |
| `references/templates/service.lro-handler.example` | RPC + handler + MyTools |
| `references/templates/main-lro-wiring.go.example` | Entrypoint LRO + weblro |
| `references/templates/lroresume/` | Conversation resume package |
| `references/templates/infra/` | LRO Terraform module |
| `references/templates/infra/agent.tf.deployment_spec-lro-envs.example` | Agent Engine LRO env vars |
