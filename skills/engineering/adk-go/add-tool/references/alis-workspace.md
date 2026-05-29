# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project. Use this file for module and infra discovery without hardcoded paths.

## Project structure

A typical ADK agent project has this layout:

```text
{agent-name}/{version}/
  agent/              # go.mod, ADK entrypoint, internal/*
  infra/              # Terraform or equivalent; service identifier config
```

Some projects separate **build** (Go code, infra, deployable artifacts) and **define** (`.proto` API contracts) into different repositories. If only one repo is open, ask the user for the pair or search the workspace.

## Path discovery

| Need | Where |
|------|--------|
| Proto **package** (for code generation) | `package` line in the `tools.proto` you edit |
| **Service id** | Infrastructure config (Terraform `locals`, variables), or ask the user |
| Go **module** import path | `go.mod` in the active agent folder |

## Hard rules

| Do | Do not |
|----|--------|
| Edit proto + code for the **same** agent/version | Edit protos/code for another agent from templates or old chats |
| Read `package` and `go.mod` from the open project | Invent paths from another product |

After **any** proto change, follow **`define-stubs.md`** before Go or `go.mod` edits.

### Alis Build projects

In Alis Build neuron layout:
- **Build repo** contains Go, `infra/`, `agent/`, deployable code.
- **Define repo** contains `*.proto` API contracts.
- Same `{neuron}/{version}/` path under each repo root.
- Service id is `local.neuron` (or `variables.neuron`) in `infra/`.
- If **`.alis/agents/AGENTS.md`** exists, read it for this product's build/define repo roots, solution specs, and CodeBlocks.
