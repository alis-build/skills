---
name: getting-started
description: >
  Use this skill when the user is new to Alis Build, asks how the platform works, wants
  onboarding, wants to understand the Define, Build, Deploy (DBD) workflow, or wants to create
  and deploy a first custom API with blocks/simpleapi. Orients new builders through the DBD
  workflow and optionally guides a first Simple API quickstart.
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    organisation organisation_id product product_id
    focus_neuron focus_neuron_id environment
    workstations.root_directory workstations.define_repos
    workstations.build_repos workstations.playground
---
# Getting Started

Help new developers understand how work moves through Alis Build. Keep an educational tone:
explain why each step exists, what the platform is doing behind the scenes, and what the user
should look for before moving on.

The core concept is **Define, Build, Deploy (DBD)**. Present every getting-started path through
these three steps.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads this skill's
`alis.context.requires` manifest — a set of `Context` field paths (`alis.os.context.v1`) — and
uses it as the `read_mask` on `GetContext`, so the block carries exactly those resolved fields.
**When the block is present, its values are authoritative**: use the exact paths and resource
names verbatim, and do **not** scan folders, derive paths from the filesystem, or ask the user
to confirm a value that was already provided.

When the block is **absent or a value is missing** (for example, the skill was loaded outside
the Alis MCP), obtain each value using the "If absent" rule in the table below. Some come from
placeholder path conventions, some from an MCP lookup, and some require asking the user to
confirm. **Never invent environment IDs or commit SHAs — look them up or ask.**

### Context fields used by this skill

These are the fields named in `alis.context.requires` (and the `read_mask`). The path-valued
fields live on `workstations` because they are absolute paths true on one machine only; use the
entry for the current workstation.

| Value | Context field | If absent, how to obtain it |
| ----- | ------------- | --------------------------- |
| Organisation | `organisation` (`organisations/*`) | MCP `GetLandingZone`; else ask the user |
| Product | `product` (`organisations/*/products/*`) | MCP `ViewProduct`; else ask the user |
| Focused neuron | `focus_neuron` (`.../neurons/*`) | MCP `ViewProduct`; else ask (confirm when several exist) |
| Environment | `environment` (`.../environments/*`) | MCP `ViewProduct`; **never invent** |
| Alis Build root | `workstations.root_directory` | Default `~/alis.build`; confirm with the user if unsure |
| Neuron define tree | `workstations.define_repos` (entry for `focus_neuron`) | `<root_directory>/<landing-zone>/define/<org>/<product>/<service>/<version>` |
| Neuron build root | `workstations.build_repos` (entry for `focus_neuron`) | Parent of the neuron's `infra/`; else derive from the filesystem |
| Playground test | `workstations.playground` | `<neuron build root>/.playground/main_test.go` |

**Ids** — available directly as fields, so do not parse resource names: `organisation_id` (the
landing-zone id), `product_id`, and `focus_neuron_id`. Only `environment id` is still derived
(the last segment of `environment`).

## Teaching Model

Use this framing first:

1. **Define** locks in the API and platform contract.
   - The developer edits protobuf files in the neuron's define tree (`workstations.define_repos`)
     inside the `define` repository.
   - Running Define turns those committed definitions into generated artifacts.
   - Behind the scenes, Alis Build pins a specific definition commit, generates language packages
     such as Go, JavaScript, Python, Dart, .NET, and public ECMAScript when configured, and may
     synchronize platform artifacts such as Spanner protobundles or Pub/Sub topics.
   - Teaching point: Define is the source-of-truth step. It makes the contract reviewable,
     repeatable, and consumable by other code.

2. **Build** implements the service and produces a deployable artifact.
   - The developer updates generated packages in the neuron's build root (`workstations.build_repos`) after Define.
   - The developer writes or edits the business logic, usually in Go.
   - The platform builds a container image from a product repo commit.
   - Docker build paths are relative to the neuron's build root (`workstations.build_repos`). For a
     neuron with a top-level Dockerfile, use `.` rather than `demo/v1`.
   - Teaching point: Build connects the locked contract to real behavior. Generated packages
     make the implementation line up with the protobuf contract.

3. **Deploy** provisions and updates the runtime environment.
   - The developer reviews Terraform in the neuron's `infra/` folder (under `workstations.build_repos`).
   - The platform deploys the selected build version to an environment such as DEV.
   - Teaching point: Deploy is where the service becomes reachable infrastructure, commonly
     Cloud Run plus supporting resources.

If the receiver is another coding agent, tell it to guide the user through DBD rather than
handing them a disconnected checklist.

## Onboarding Flow

Start by orienting the user:

- Explain that DBD is the foundational Alis Build workflow.
- Guide them through the Simple API quickstart — this is the point of the skill: get a new
  user from nothing to a deployed, working API by walking the full DBD loop.

Use the Build Kit Custom APIs flow as the mental model:

- Overview: DBD is the core workflow for custom APIs.
- Quick Start: create or select a service and install `blocks/simpleapi`.
- Define: review and edit `.proto`, commit, then run Define.
- Build: install/update generated packages, implement service logic, commit, then build.
- Deploy: review infrastructure, deploy, then validate through the playground.

## Simple API Quickstart

Guide every new user through these phases. Prefer values from the Runtime Context block; fall
back to the acquisition rules in the Context variables table.

### 1. Define

1. Confirm the organisation (landing zone) and product. Use `organisation` and `product` from
   context if present; otherwise ask the user to pick a landing zone and product.
2. Confirm `focus_neuron` from context, or ask for a new neuron ID or help them select an
   existing target service.
3. Create the neuron in that product.
4. Install the `simpleapi` block in the neuron.
5. Ask the user to open the focused neuron's define tree at `workstations.define_repos`:

```text
# from context: workstations.define_repos   (entry for focus_neuron)
# if absent:    ~/alis.build/<landing-zone>/define/<org>/<product>/<service>/<version>
```

6. Ask them to pull latest changes and merge the newly created block branch (git operations run
   against the enclosing define repo), review the generated proto file in that define tree, and
   commit/push the merge.
7. Ask them for the pushed definition commit SHA.
8. Run Define with that explicit commit SHA, then wait for generated artifacts.

Do not run Define with `HEAD`. Define should lock a reviewed, pushed definition commit.

Explain while guiding: the proto edit/review is part of Define because this is where the team
locks the service contract before implementation.

### 2. Build

1. Ask the user to open the focused neuron's build root at `workstations.build_repos`:

```text
# from context: workstations.build_repos   (entry for focus_neuron)
# if absent:    ~/alis.build/<landing-zone>/build/<product-id>/<neuron-path>
```

2. Ask them to pull latest changes, merge the newly created block branch, and review the generated
   service files.
3. Ask them to install or update generated packages after Define. In VS Code this may already be
   supported by the prepared environment; otherwise help them prepare local environment access.
4. Ask them to implement or inspect the service logic, then run the Go service locally if possible.
5. Ask them to commit and push changes such as `go.mod`, `go.sum`, and implementation files.
6. Ask for the product repo commit SHA. If the user explicitly says the current checked-out commit
   should be used, `HEAD` is acceptable for build.
7. Determine the Docker build path. Use the focused neuron's `workstations.build_repos` entry as
   the build root; if absent, inspect Dockerfiles under the selected neuron and derive build
   paths from the filesystem.
8. Run Build for the selected neuron and commit.

Explain while guiding: generated packages and service code are both part of Build because this
phase turns the locked contract into a runnable artifact.

### 3. Deploy

1. Use `environment` from context. If absent, get the product's known environments from MCP
   `ViewProduct`; do not invent an environment ID.
2. Ask the user which environment to deploy to, usually DEV for first onboarding.
3. Review the neuron's `infra/` files (under `workstations.build_repos`) with the user before
   applying.
4. Deploy the successful build version to the selected environment.
5. Show the user where to follow deploy logs.
6. After deploy succeeds, direct them to the generated playground at `workstations.playground`,
   usually:

```text
# from context: workstations.playground
# if absent:    <neuron build root>/.playground/main_test.go
```

7. Help them run the test or call the deployed service so they see the end-to-end result.

Explain while guiding: Deploy applies the runtime infrastructure and proves the built artifact
works in a real environment.

## Define Glass Mode Context

When explaining Define results, use these concepts:

- The definition is pinned to a specific commit in the organisation define repo.
- Generated artifacts have states such as queued, generating, ready, or failed.
- Language artifacts include package/import details and installation commands.
- Developer context and usage examples explain how generated artifacts should be consumed.
- Platform artifacts may include synchronized Spanner data schemas and Pub/Sub topics.

Use this to answer "what happened when I ran Define?" in practical terms: Alis Build took the
reviewed proto contract, locked it to a commit, generated consumable packages/artifacts, and
reported where those outputs live and how to use them.

## Verification

- [ ] The user understands DBD as the main platform workflow.
- [ ] Proto work is explained under Define.
- [ ] Generated packages and implementation code are explained under Build.
- [ ] Infrastructure review and environment rollout are explained under Deploy.
- [ ] If running the quickstart, Define uses an explicit pushed commit SHA.
- [ ] Build Docker paths use the focused neuron's `workstations.build_repos` entry from context,
      or are derived from the selected neuron's filesystem when context is absent.
- [ ] Deploy targets a real environment from the Runtime Context or product context.
- [ ] The user validates the deployed service through the playground or an equivalent call.
- [ ] If a Runtime Context block was provided, its exact paths/IDs were used and no redundant
      scanning, deriving, or asking occurred.
