# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module and infra discovery without hardcoded paths.

This skill has **no proto or define step** — only build-repo discovery and neuron anchors for the Go module and entrypoint you are editing.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Agent code lives in the product **build** repo under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`).

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go code may live in a subfolder or at the neuron root — follow the neuron you are editing. If multiple `go.mod` files exist under one neuron, ask which service is the target.

## Canonical paths

| Artifact | Script key |
| -------- | ---------- |
| Alis Build root | `workstations.root_directory` |
| Neuron build root | `workstations.build_repos[]` |
| Neuron define tree | `workstations.define_repos[]` |
| Infra directory | `workstations.infra` |
| Playground | `workstations.playground` |

## Discovery tier order

1. **Resolve script** — Run the bundled resolver. It derives organisation, product, neuron id, and all workstation paths purely from the `~/alis.build/` directory structure. Pass `--cwd` when the user's working directory differs from the target neuron:

   ```bash
   bash scripts/resolve-alis-workspace.sh --json
   bash scripts/resolve-alis-workspace.sh --json --cwd <path>
   ```

   The JSON output provides `organisation_id`, `product_id`, `focus_neuron_id`, and `workstations` (build_repos, infra, playground). Use these values directly — do not re-derive them.

2. **`<alis-runtime-context>`** — When LoadSkill injected the block, use its values for any field not already set by the resolve script. Do not re-derive or re-ask for values present in the block.

3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists. Use `CloneProduct` for canonical clone paths.
4. **Neuron anchors** — nearest `go.mod` under the neuron build root for the service you are editing.
5. **Ask user** — Smallest missing piece only (which `go.mod` when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the resolve script.

2. **Go module** — nearest `go.mod` under that root. Console wiring is in the entrypoint (`console.NewLauncher` on the web launcher stack).

3. **Service id** — `focus_neuron_id` from the resolve script.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Run `bash scripts/resolve-alis-workspace.sh --json` first | Manually parse `~/alis.build` paths or read infra terraform files |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Use the resolve script output for build/infra paths | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of the script, runtime context, or MCP |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` at the path they give you.
