---
name: adk-new-agent
description: >
  Guides users through creating a brand-new base ADK-Go agent service on the Alis Build
  platform. Use when the user wants to create, scaffold, install, understand, build, or deploy
  a new ADK-Go agent/neuron with blocks/agent; when they mention the Build Kit Agent flow,
  agent.v1, a base agent, Agent Engine, ADK-Go launcher setup, or establishing the foundation
  before using other ADK-Go skills. This is an educational setup journey: explain each stage,
  verify product/environment/neuron context, install blocks/agent, review generated code,
  run define/build/deploy as appropriate, and then route follow-up extensions to the other
  ADK-Go skills.
---

# New ADK-Go Agent

Create the base agent service that the other ADK-Go skills extend. Keep the tone educational:
teach the user what each platform step creates and why it matters, while still doing the work
when tools and workspace access are available.

Start by reading:

- `references/build-kit-flow.md` for the guided journey and platform concepts.
- `references/generated-agent.md` before reviewing or explaining generated files.

## Operating Mode

Prefer the Alis Build MCP when available. If MCP access is not available, guide the user through
the equivalent Build Kit Agent flow and stop at points where they must run platform actions.

Do not jump straight to code edits. A new agent is a platform workflow:

1. Choose the landing zone, product, environment, and target service.
2. Create or select the agent neuron, usually `agent-v1`.
3. Install `blocks/agent`.
4. Review and publish the generated definition package.
5. Review the generated ADK-Go service.
6. Configure environment variables.
7. Build and deploy.
8. Hand off to the extension skills.

Explain the purpose of the current step before acting. Keep explanations short but concrete.

## Discovery

Determine these values from MCP, workspace metadata, or the user's active Alis Build context:

- Landing zone ID and product ID.
- Environment ID and display name.
- Active neuron/service ID.
- Product repo path, normally `~/alis.build/<landing-zone>/build/<product>`.
- Define repo path, normally `~/alis.build/<landing-zone>/define`.

If any value is ambiguous, ask for the smallest missing decision. Do not invent IDs.

Use `ViewProduct` before any deploy-related action so environment IDs come from Alis Build,
not from memory or naming conventions.

## Create Or Select The Agent Service

If the product does not already have the intended agent neuron, create one with the product's
existing naming convention. Prefer `agent-v1` when there is no product-specific convention.

If more than one active service is selected, ask the user which service should receive
`blocks/agent`; installing into the wrong neuron is expensive to unwind.

Teach this concept: the neuron is the deployable service boundary. `blocks/agent` turns that
service into an ADK-Go agent runtime with infrastructure, launcher code, and a proto-backed
tool contract.

## Install `blocks/agent`

Use `ListBlocks` if the exact block ID is not confirmed, then install `blocks/agent` into the
selected neuron with `InstallBlock`.

After installation, inspect the generated workspace rather than assuming paths. The expected
shape is:

```text
<product-repo>/<neuron>/agent/main.go
<product-repo>/<neuron>/agent/Dockerfile
<product-repo>/<neuron>/infra/*.tf
<define-repo>/<product>/<neuron>/tools.proto
```

Teach this concept: the block lays down a working base, not the final product agent. The base
agent proves the runtime, deployment, memory/session wiring, and extension points.

## Define, Build, Deploy

Definition generation and dependency publication are platform steps. If using Alis Build MCP:

1. Refresh or inspect the define repo.
2. Use an explicit define commit when running `RunDefine`; never pass `HEAD`.
3. Wait for generated artifacts when later Go work depends on them.

If using the Build Kit UI, guide the user to review `tools.proto`, commit/push definition
changes, and run Define from the Agent flow.

For build:

1. Inspect Dockerfiles under the selected neuron.
2. Use `RunBuild` with Docker build paths derived from the filesystem.
3. Deploy the resulting build version with `RunDeploy`.
4. Use `plan_only: true` first when Terraform changes need review.

Teach this concept: define publishes typed contracts; build creates the service image; deploy
applies the Cloud Run and Vertex AI Reasoning Engine infrastructure.

## Environment Variables

Guide the user to configure:

- `AGENT_SERVICE_URL=https://<agent-service-domain>`
- `IDENTITY_SERVICE_URL=https://<users-service-domain>`

The Build Kit flow derives defaults from the selected environment's project number and region:

```text
<neuron-id>-<project-number>.<region>.run.app
users-v1-<project-number>.<region>.run.app
```

Confirm the actual deployed domains before treating these as final values.

## Review The Generated Agent

When the scaffold exists, read `references/generated-agent.md`, then review:

- `agent/main.go` for `llmagent.Config`, Gemini model setup, session/memory services, and
  universal launcher wiring.
- `infra/agent.tf` for Vertex AI Reasoning Engine configuration.
- `tools.proto` for the proto-first tool contract and JSON Schema generation.

When explaining the code, connect each file to the user's next likely extension step.

## Hand Off To Extension Skills

After the base agent builds or deploys, suggest the next ADK-Go skill based on the user's goal:

| User goal | Use |
|---|---|
| Add synchronous proto-backed tools | `adk-add-tool` |
| Add async / long-running operation tools | `adk-add-lro` |
| Add runtime markdown skills loaded by the model | `adk-add-agent-skills` |
| Add AG-UI support | `adk-add-agui` |
| Add A2A scheduler support | `adk-add-scheduler` |

Do not use those skills during base setup unless the user explicitly asks to extend the agent
after the scaffold is working.

## Verification

- [ ] Landing zone, product, environment, and neuron were verified from workspace or MCP context.
- [ ] `blocks/agent` is installed in the selected neuron.
- [ ] Generated `agent/main.go`, `infra/`, and `tools.proto` exist in this workspace.
- [ ] Define was run from an explicit definition commit or the user completed the Build Kit define step.
- [ ] Dependencies were refreshed after define if generated Go packages are needed.
- [ ] Build uses Docker paths discovered from this neuron's filesystem.
- [ ] Deploy targets an environment ID returned by `ViewProduct`.
- [ ] User understands which ADK-Go skill to use next.

## Pitfalls

- Treating this as only file generation. The value is the full Alis Build journey from service
  boundary to deployable ADK runtime.
- Installing `blocks/agent` into the wrong active neuron.
- Reusing paths, package names, or proto packages from another product.
- Running `RunDefine` with `HEAD` or a guessed commit.
- Starting extension work before the base scaffold is reviewed and buildable.
