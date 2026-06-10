# Build Kit Agent Flow

Use this reference to mirror the educational journey from the Alis Build Kit Agent flow.

## Stages

### 1. Overview

Orient the user around ADK-Go and Alis Build:

- `agent/main.go` builds an `llmagent.Config` containing the agent name, description,
  instructions, model, tools, callbacks, schemas, sub-agents, and toolsets.
- The base scaffold uses Gemini through Vertex AI.
- Local runs use in-memory session and memory services.
- Deployed runs use Vertex AI session and memory services through Agent Engine context.
- The universal launcher exposes the same agent through Agent Engine, web UI, API, and A2A.

Teaching point: the generated service is intentionally small and visible so the user can learn
where future tools, skills, callbacks, and launchers will be attached.

### 2. Prerequisites

Confirm:

- Product and landing zone.
- Deployment environment.
- One target service/neuron.
- Identity service domain.

The UI flow lets the user create or select a service, typically `agent.v1` in display form
or `agent-v1` as an ID. If more than one service is active, stop and resolve that first.

Teaching point: the product owns the business capability; the environment owns deployed runtime
configuration; the neuron is the service boundary receiving the agent block.

### 3. Agent Service

Install `blocks/agent`, then review the generated definition and service files.

The UI flow performs these actions:

- Install the `blocks/agent` codeblock for the active neuron package.
- Open and review `tools.proto`.
- Commit and push definition changes.
- Run Define for the active agent service.
- Open `agent/main.go`.
- Configure local debug settings.
- Open environment variables for the selected environment.
- Build and deploy the agent service.

Teaching point: the proto contract, Go runtime, and Terraform infrastructure are generated
together so the base service can be deployed before product-specific extensions are added.

### 4. Next Steps

Once the base service is working, route the user to:

- `adk-add-agent-skills` for embedded runtime skills.
- `adk-add-agui` for AG-UI.
- `adk-add-lro` for long-running tools.
- `adk-add-scheduler` for scheduler support.
- `adk-add-tool` for synchronous proto-backed tools.

Do not blur the base setup with extensions unless the user asks for both.

## Default Domains

When the environment exposes project number and region, the UI derives:

```text
AGENT_SERVICE_URL=https://<neuron-id>-<project-number>.<region>.run.app
IDENTITY_SERVICE_URL=https://users-v1-<project-number>.<region>.run.app
```

Use these as explainable defaults, not guaranteed deployed URLs. Confirm the actual domains
from the environment or deployed service before finalizing configuration.
