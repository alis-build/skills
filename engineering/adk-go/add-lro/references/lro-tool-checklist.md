# Add one LRO tool

Per-tool checklist. Complete every step unless the RPC already exists from a prior pass.

Read **`workspace.md`**. Proto + code generation order: **`define-stubs.md`**.

## 1. Proto (define repo)

- [ ] Add RPC to `ToolsService` returning `google.longrunning.Operation`
- [ ] Set `option (google.longrunning.operation_info)` with `response_type` and `metadata_type`
- [ ] Add request, response, and metadata messages with field comments
- [ ] Write RPC comments for humans and the model (when to call, async behavior)

Starter snippet: **`references/templates/tools.proto.lro-snippet.example`**

LRO RPCs may share `tools.proto` with sync tools (default pattern).

## 2. Define + dependencies

- [ ] Ask user: **run a define on the package** `<package from tools.proto>`
- [ ] **Stop** — no Go until define finishes
- [ ] Ask user: **install required dependencies**
- [ ] Wait for confirmation

## 3. Private state + gob

- [ ] Define `REPLACE_WITH_LRO_TOOL_PrivateState` with tool fields + `Resume lroresume.ADKResumeContext`
- [ ] `gob.Register` the struct in `internal/lroresume/context.go` `init()`

## 4. RPC handler (`service.go`)

- [ ] Guard `LRO == nil` → `FailedPrecondition`
- [ ] Validate required request fields → `InvalidArgument`
- [ ] `LRO.NewOperation(ctx, "operations/"+uuid, metadataProto)`
- [ ] Copy `ADKResumeContext` from `lroresume.ResumeContextFromContext(ctx)` into private state
- [ ] `op.SavePrivateState(&priv)`
- [ ] `op.ResumeViaTasks(<uniqueResumePath>, delay)` — unique path per tool
- [ ] Return `op.OperationPb()`

Pattern: **`references/templates/service.lro-handler.example`**

## 5. Resumable handler

- [ ] `const <resumePath> = "kebab-case-unique-per-tool"`
- [ ] Handler func `func(op *lro.Operation)` — decode private state, unmarshal metadata
- [ ] Use `op.ResumePoint()` for multi-step workflows; `SetResumePoint` + `ResumeViaTasks` to requeue
- [ ] Update metadata for progress; `op.SaveMetadata`
- [ ] On success: `op.Complete(responseProto)`; on failure: `op.Fail(...)`
- [ ] If ADK chat should continue: `lroresume.ResumeAfterOperation` after `Complete` — see **`references/resume-flow.md`**

## 6. Register handler

- [ ] In `InitLRO`: `client.AddResumableHandler(<resumePath>, <handlerFunc>)`
- [ ] Do **not** reuse the same resume path for two tools

## 7. Extend resume decode (if using wrapper private state)

- [ ] Uncomment/extend `resumeContextFromOperation` in `lroresume/run_api.go` for your private state type

## 8. ADK registration

- [ ] `MyTools()`: `NewLROTool("<snake_case>", pb.ToolsService_<Rpc>_FullMethodDescription, toolsService.<Rpc>)`
- [ ] Tool name snake_case matches model-facing name

## 9. Verify

```bash
go build ./...
```

- [ ] Local ADK web: LRO tool appears with operation-shaped output schema
- [ ] Calling tool returns operation `name` with `done: false`
- [ ] LRO sublauncher / operations UI works when infra is deployed
- [ ] Optional: after completion, session resumes via `/api/run` when resume context was captured

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Duplicate resume path | One `AddResumableHandler` path per LRO tool |
| `serviceID` ≠ infra neuron | Align `lroServiceID`, `InitLRO`, `weblro.WithServiceID` |
| Go before define | Follow define-stubs order |
| Forgot `WrapToolContext` | Use `NewLROTool` from lro snippet, not raw `NewTool` |
| No `ResumeAfterOperation` | Add when chat must continue after async work |
| Sync tool in LRO-only checklist | Use **add-tool** instead |
