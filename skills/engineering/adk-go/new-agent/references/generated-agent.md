# Generated Agent Scaffold

Use this reference when reviewing files created by `blocks/agent`.

## Expected Files

The block typically creates:

```text
<product-repo>/<neuron>/agent/go.mod
<product-repo>/<neuron>/agent/main.go
<product-repo>/<neuron>/agent/Dockerfile
<product-repo>/<neuron>/infra/agent.tf
<product-repo>/<neuron>/infra/cloudrun.tf
<product-repo>/<neuron>/infra/main.tf
<product-repo>/<neuron>/infra/variables.tf
<define-repo>/<product>/<neuron>/tools.proto
```

Discover actual paths from the current workspace. Do not copy paths from examples.

## `agent/main.go`

The generated entrypoint usually contains:

- Environment discovery for `GOOGLE_CLOUD_PROJECT` / `ALIS_OS_PROJECT` and
  `GOOGLE_CLOUD_AGENT_ENGINE_LOCATION` / `ALIS_REGION`.
- Reasoning engine ID parsing from `GOOGLE_CLOUD_AGENT_ENGINE_ID`.
- `llmagent.Config` with name, description, instruction, tools, callbacks, schemas,
  sub-agents, and toolsets.
- Gemini model creation with `genai.BackendVertexAI`.
- Local `session.InMemoryService()` and `memory.InMemoryService()`.
- Deployed Vertex AI session and memory services.
- After-agent callback wiring to add sessions to memory.
- Universal launcher wiring for Agent Engine, web UI, API, and A2A.

Teaching point: this one file is the agent's control room. Most later ADK-Go skills add imports,
tools, toolsets, callbacks, or launchers here.

## `tools.proto`

The generated definition package establishes the proto-first tool surface:

- `option (alis.open.options.v1.file).json_schema.generate = true;`
- `service ToolsService` as the source of truth for tool contracts.
- Comments on services, RPCs, messages, and fields become model-facing tool descriptions
  and JSON Schema metadata after Define.

Teaching point: tool quality starts in proto comments. The model sees the generated schema and
descriptions, so vague comments become vague tool behavior.

## `infra/agent.tf`

The generated infrastructure typically creates a Vertex AI Reasoning Engine:

- `agent_framework = "google-adk"`.
- Container image from the neuron's built `agent` Docker image.
- Deployment resource settings.
- Telemetry and message-content capture environment variables.
- Memory bank configuration.
- Artifact Registry read permissions for the Agent Engine service agent.

Teaching point: the deployment is more than Cloud Run. Agent Engine provides managed runtime
context for sessions, memory, and ADK-compatible serving.

## Review Questions

Use these questions to help the user understand the scaffold:

- What is the agent's initial instruction, and what product behavior should it learn next?
- Which launcher surfaces matter now: Agent Engine, web UI, API, or A2A?
- Does the base `tools.proto` include only example tools, or product-owned tools?
- Are memory and session defaults acceptable for the first deployment?
- Which extension skill should be used after the base agent is deployed?
