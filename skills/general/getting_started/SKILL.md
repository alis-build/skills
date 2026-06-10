---
name: getting-started
description: >
  Orients new builders on the Alis Build platform through the core Define, Build, Deploy
  (DBD) workflow and optionally guides a first Simple API quickstart. Use when the user is
  new to Alis Build, asks how the platform works, wants onboarding, wants to understand DBD,
  or wants to create and deploy a first custom API with blocks/simpleapi.
---
# Getting Started

Help new developers understand how work moves through Alis Build. Keep an educational tone:
explain why each step exists, what the platform is doing behind the scenes, and what the user
should look for before moving on.

The core concept is **Define, Build, Deploy (DBD)**. Present every getting-started path through
these three steps.

## Teaching Model

Use this framing first:

1. **Define** locks in the API and platform contract.
   - The developer edits protobuf files in the `define` repository.
   - Running Define turns those committed definitions into generated artifacts.
   - Behind the scenes, Alis Build pins a specific definition commit, generates language packages
     such as Go, JavaScript, Python, Dart, .NET, and public ECMAScript when configured, and may
     synchronize platform artifacts such as Spanner protobundles or Pub/Sub topics.
   - Teaching point: Define is the source-of-truth step. It makes the contract reviewable,
     repeatable, and consumable by other code.

2. **Build** implements the service and produces a deployable artifact.
   - The developer updates generated packages in the `build` repository after Define.
   - The developer writes or edits the business logic, usually in Go.
   - The platform builds a container image from a product repo commit.
   - Docker build paths are relative to the neuron's folder. For a neuron with a top-level
     Dockerfile, use `.` rather than `demo/v1`.
   - Teaching point: Build connects the locked contract to real behavior. Generated packages
     make the implementation line up with the protobuf contract.

3. **Deploy** provisions and updates the runtime environment.
   - The developer reviews Terraform in the neuron's `infra/` folder.
   - The platform deploys the selected build version to an environment such as DEV.
   - Teaching point: Deploy is where the service becomes reachable infrastructure, commonly
     Cloud Run plus supporting resources.

If the receiver is another coding agent, tell it to guide the user through DBD rather than
handing them a disconnected checklist.

## Onboarding Flow

Start by orienting the user:

- Explain that DBD is the foundational Alis Build workflow.
- Ask whether they want the guided Simple API quickstart.
- If they do not want the quickstart, offer to help with any part of Define, Build, or Deploy.

Use the Build Kit Custom APIs flow as the mental model:

- Overview: DBD is the core workflow for custom APIs.
- Quick Start: create or select a service and install `blocks/simpleapi`.
- Define: review and edit `.proto`, commit, then run Define.
- Build: install/update generated packages, implement service logic, commit, then build.
- Deploy: review infrastructure, deploy, then validate through the playground.

## Simple API Quickstart

When the user wants the quickstart, guide them through these phases.

### 1. Define

1. Ask the user to pick a landing zone and product if they have not already.
2. Ask for a new neuron ID, or help them select an existing target service.
3. Create the neuron in that product.
4. Install the `simpleapi` block in the neuron.
5. Ask the user to open the landing zone define repo:

```text
~/alis.build/<landing-zone-id>/define
```

6. Ask them to pull latest changes, merge the newly created block branch, review the generated
   proto file, and commit/push the merge.
7. Ask them for the pushed definition commit SHA.
8. Run Define with that explicit commit SHA, then wait for generated artifacts.

Do not run Define with `HEAD`. Define should lock a reviewed, pushed definition commit.

Explain while guiding: the proto edit/review is part of Define because this is where the team
locks the service contract before implementation.

### 2. Build

1. Ask the user to open the product build repo:

```text
~/alis.build/<landing-zone-id>/build/<product-id>
```

2. Ask them to pull latest changes, merge the newly created block branch, and review the generated
   service files.
3. Ask them to install or update generated packages after Define. In VS Code this may already be
   supported by the prepared environment; otherwise help them prepare local environment access.
4. Ask them to implement or inspect the service logic, then run the Go service locally if possible.
5. Ask them to commit and push changes such as `go.mod`, `go.sum`, and implementation files.
6. Ask for the product repo commit SHA. If the user explicitly says the current checked-out commit
   should be used, `HEAD` is acceptable for build.
7. Inspect Dockerfiles under the selected neuron and derive Docker build paths from the filesystem.
8. Run Build for the selected neuron and commit.

Explain while guiding: generated packages and service code are both part of Build because this
phase turns the locked contract into a runnable artifact.

### 3. Deploy

1. Use the product's known environments; do not invent an environment ID.
2. Ask the user which environment to deploy to, usually DEV for first onboarding.
3. Review the neuron's `infra/` files with the user before applying.
4. Deploy the successful build version to the selected environment.
5. Show the user where to follow deploy logs.
6. After deploy succeeds, direct them to the generated playground, usually:

```text
<neuron>/.playground/main_test.go
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
- [ ] Build Docker paths are derived from the selected neuron's filesystem.
- [ ] Deploy targets a real environment from the product context.
- [ ] The user validates the deployed service through the playground or an equivalent call.
