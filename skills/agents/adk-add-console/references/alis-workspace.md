# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module and infra discovery without hardcoded paths.

This skill has **no proto or define step** — only build-repo discovery, `InstallBlock`, and neuron anchors for the agent module and console BFF you are editing.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Agent code lives in the product **build** repo under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`).

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go code may live in subfolders or at the neuron root — follow the neuron you are editing. If multiple `go.mod` files exist under one neuron, ask which service is the target.

After **`InstallBlock(agentsui)`**, expect:

```text
<neuron>/
├── agent/          # ADK agent (blocks/agent convention — path may vary)
├── console/        # agentsui CodeBlock — BFF + Vue SPA
└── infra/          # agent + console Cloud Run, LB (block merges console snippets here)
```

The `console/` directory is **not** present before install. Do not assume an `agent/` subfolder — discover `go.mod` locations.

## Console mode discovery

| Signal | Mode |
|--------|------|
| `console/server.go` exists | Custom BFF (agentsui) — default |
| `google_cloud_run_v2_service.console` in `infra/` | BFF infra merged |
| `console.NewLauncher` in agent entrypoint | Bundled ADK console (fallback) |
| `"console"` in agent Cloud Run args | Bundled launcher active |

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

   The JSON output provides `organisation_id`, `product_id`, `focus_neuron_id`, and `workstations` (build_repos, infra, playground). Use these values directly — do not re-derive them. `organisation_id` and `product_id` are required for MCP `InstallBlock`.

2. **`<alis-runtime-context>`** — When LoadSkill injected the block, use its values for any field not already set by the resolve script. Do not re-derive or re-ask for values present in the block.

3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists. Use `InstallBlock` with `landing_zone_id` (= `organisation_id`), `product_id`, `neuron_id` (= `focus_neuron_id`), `block_id: "agentsui"`. Use `CloneProduct` for canonical clone paths.
4. **Neuron anchors** — nearest `go.mod` under the neuron build root for the agent service; `console/go.mod` for the BFF.
5. **Ask user** — Smallest missing piece only (which `go.mod` when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the resolve script.

2. **Console mode** — grep for `console/server.go` (BFF) vs `console.NewLauncher` in agent entrypoint (bundled).

3. **Go modules** — agent: nearest `go.mod` under neuron root (often `agent/go.mod`). Console: `console/go.mod` after block install.

4. **Service id** — `focus_neuron_id` from the resolve script; ADK app name uses periods (`my.agent.v1`), not hyphens.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Run `bash scripts/resolve-alis-workspace.sh --json` first | Manually parse `~/alis.build` paths or read infra terraform files for neuron id |
| Use `InstallBlock(agentsui)` to add console — do not hand-author `console/` | Copy BFF source from another neuron |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Use the resolve script output for build/infra paths and InstallBlock ids | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of the script, runtime context, or MCP |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` at the path they give you.
