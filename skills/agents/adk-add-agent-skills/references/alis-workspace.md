# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module and infra discovery without hardcoded paths.

This skill has **no proto or define step** — only build-repo discovery and neuron anchors for the Go module and entrypoint you are editing.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Agent code lives in the product **build** repo under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`).

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go code may live in a subfolder (e.g. `agent/`) or at the neuron root — follow the neuron you are editing. `blocks/agent` often uses `agent/`; that is a convention, not a requirement.

If multiple `go.mod` files exist under one neuron, ask which service is the target.

## Canonical paths

| Artifact | Context field |
| -------- | ---------- |
| Alis Build root | `workstations.root_directory` |
| Neuron build root | `workstations.build_repos[]` |
| Neuron define tree | `workstations.define_repos[]` |
| Infra directory | Derive as `<workstations.build_repos[]>/infra` |
| Playground | `workstations.playground` |

## Discovery tier order

1. **`<alis-runtime-context>`** — Use injected values for organisation, product, focused neuron, and workstation paths. Do not re-derive or re-ask for values present in the block.

2. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists. Use `CloneProduct` for canonical clone paths.
3. **Neuron anchors** — nearest `go.mod` under the neuron build root for the service you are editing; entrypoint in that module (runtime skills: `internal/skills/skills/` relative to that module).
4. **Ask user** — Smallest missing piece only (which `go.mod` when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the runtime context.

2. **Go module** — nearest `go.mod` under that root for the ADK service you are wiring.

3. **Entrypoint** — in the same module (file that sets `llmagent.Config.Toolsets`).

## Hard rules

| Do | Do not |
| ---- | ------ |
| Use `<alis-runtime-context>` values first | Manually parse `~/alis.build` paths or read infra terraform files |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Use the runtime context for build/infra paths | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of runtime context or MCP |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` at the path they give you.
