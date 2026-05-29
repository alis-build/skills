# Conversation resume after LRO completes

When the model calls an LRO tool from an ADK web session, the tool returns an operation handle immediately. The user’s conversation may still be waiting for a **function response**. This skill wires automatic resume via `POST /api/run`.

## Flow

```
Model calls LRO tool
  → NewLROTool / WrapToolContext stores session + functionCallId on ctx
  → RPC handler saves ADKResumeContext in LRO private state
  → ResumeViaTasks runs resumable handler (Cloud Tasks)
  → Handler Complete() + ResumeAfterOperation()
  → POST /api/run with functionResponse payload
  → ADK continues the session
```

## When to call ResumeAfterOperation

| Scenario | Call ResumeAfterOperation? |
|----------|----------------------------|
| LRO started from ADK tool in web UI; user should see final result in chat | **Yes** — end of resumable handler after `Complete()` |
| LRO only used from external gRPC clients / polling UI | **No** |
| Fire-and-forget background job | **No** |

## Private state shape

Prefer a tool-specific struct with a `Resume lroresume.ADKResumeContext` field (see `service.lro-handler.example`). In the RPC handler:

```go
priv := myPrivateState{...}
if rc, ok := lroresume.ResumeContextFromContext(ctx); ok {
    priv.Resume = rc
}
op.SavePrivateState(&priv)
```

Register the struct in `lroresume/context.go` `init()` with `gob.Register`.

Extend `resumeContextFromOperation` in `run_api.go` to decode the wrapper struct and return `.Resume` (template includes a commented example).

## Defaults to align

| Constant | Set to |
|----------|--------|
| `lroresume.DefaultAppName` | `llmagent.Config.Name` |
| `lroresume.DefaultNeuron` | `lroServiceID` / infra `local.neuron` |
| Entrypoint `lroServiceID` | Same as `InitLRO` and `weblro.WithServiceID` |

## Launcher requirement

The entrypoint must include the **api** web sublauncher (for `/api/run`) and **lro** sublauncher (`weblro.NewLauncher`). See `main-lro-wiring.go.example`.

## Out of scope

A2A + Cloud Tasks resume handlers (separate `lroresume` service pattern) — not covered by this skill.
