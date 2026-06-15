# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

Primary work is Go wiring in the build repo (`webagui.NewLauncher`). Optional proto edits for Spanner table provisioning are documented in **`SKILL.md`** → **Proto imports for Spanner tables** — not in this file.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`). The same trail appears under build and define.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go services may live in subfolders or at the neuron root — follow the neuron you are editing. `blocks/agent` often uses `agent/`; that is a convention, not a requirement. If multiple `go.mod` files exist, ask which service receives the AG-UI launcher.

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

   The JSON output provides `organisation_id`, `product_id`, `focus_neuron_id`, and `workstations` (build_repos, define_repos, infra, playground). Use these values directly — do not re-derive them.

2. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
3. **Neuron anchors** — nearest `go.mod` under the neuron build root for the service you are editing. For optional Spanner proto work, `tools.proto` under the matching define tree (`workstations.define_repos`).
4. **Ask user** — Smallest missing piece only (which `go.mod` when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the resolve script.

2. **Go module** — nearest `go.mod` under that root. AG-UI wiring is in that module's entrypoint.

3. **Service id** — `focus_neuron_id` from the resolve script. Passed to `webagui.NewLauncher` — not the proto package name and not necessarily `llmagent.Config.Name`.

4. **Optional proto (Spanner only)** — When threads/history tables are needed, edit `tools.proto` under the neuron define tree (`workstations.define_repos`) and follow **`SKILL.md`** → **Proto imports for Spanner tables** (ask user to run define). Skip proto work for launcher-only wiring.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Run `bash scripts/resolve-alis-workspace.sh --json` first | Manually parse `~/alis.build` paths or read infra terraform files |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Use the resolve script output for build/define/infra paths | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of the script or MCP |
| Use **`SKILL.md`** for proto/import/define steps | Follow `define-stubs.md` or add-tool proto workflows from another skill |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` at the path they give you.
