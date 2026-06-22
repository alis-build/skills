---
name: adk-new-agent
description: >
  Use this skill when the user wants to create, scaffold, or deploy a new ADK-Go agent neuron with
  blocks/agent, set up Agent Engine and the ADK launcher foundation, or start from scratch before
  other ADK extensions — even if they do not say agent.v1 or Build Kit. Guides the full setup
  journey through define, build, and deploy, then routes to other ADK-Go skills. Not for extending
  an existing agent with tools, AG-UI, or LRO only.
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    organisation organisation_id product product_id environment
    workstations.root_directory workstations.define_repos
    workstations.build_repos session.ide
---

# New ADK-Go Agent

Create the base agent service that the other ADK-Go skills extend. Keep the tone educational:
teach the user what each platform step creates and why it matters, while still doing the work
when tools and workspace access are available.

Start by reading:

- `references/build-kit-flow.md` for the guided journey and platform concepts.
- `references/generated-agent.md` before reviewing or explaining generated files.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`; `tools.proto` under `workstations.define_repos` when reviewing generated layout.
5. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** This skill **creates a new neuron** — do not treat `focus_neuron_id` (from the script only) as the new service id; ask the user for the new neuron ID. Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Organisation | `organisation` (`organisations/*`) | MCP `GetLandingZone`; else ask the user |
| Landing zone id | `organisation_id` | MCP `GetLandingZone`; else ask the user |
| Product | `product` (`organisations/*/products/*`) | MCP `ViewProduct`; else ask the user |
| Product id | `product_id` | MCP `ViewProduct`; else ask the user |
| Environment | `environment` (`.../environments/*`) | MCP `ViewProduct`; **never invent** |
| Alis Build root | `workstations.root_directory` | Default `~/alis.build`; confirm with the user if unsure |
| Neuron define tree | `workstations.define_repos` | Entry for the **new** neuron after `blocks/agent` install |
| Neuron build root | `workstations.build_repos` | Parent of the new neuron's `infra/` after install |
| Host editor | `session.ide` | If absent or unknown, use MCP / manual steps; do not use IDE deep-link commands |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before platform actions**, run the workspace resolver when working from a local checkout:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Follow the **resolution order** above. Use `ViewProduct` before any deploy-related action so environment IDs come from Alis Build, not from memory or naming conventions.

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

Use the **resolution order** in **Runtime Context** above. In short:

- Landing zone ID and product ID — from script, runtime context, or MCP.
- Environment ID — MCP `ViewProduct` only; never invent.
- **New** neuron/service ID — ask the user; do not treat `focus_neuron` as the target.
- Product repo path — normally `~/alis.build/<landing-zone>/build/<product>` (or `workstations.build_repos`).
- Define repo path — normally `~/alis.build/<landing-zone>/define` (or `workstations.define_repos`).

If any value is ambiguous, ask for the smallest missing decision.

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
