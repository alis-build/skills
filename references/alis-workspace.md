# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

Primary work is Go wiring in the build repo (`webagui.NewLauncher`). Proto and Terraform steps are documented in **`SKILL.md`** and **`references/infra-agui-history.md`**.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`. Stored as `info.NeuronId` in the central identity package.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`). The same trail appears under build and define.

## Central identity

`AppName` and `NeuronId` must live in **one editable place**. The exact package does not matter as long as there is exactly one source and all consumers import from it.

| Constant | Form | Example |
|----------|------|---------|
| `NeuronId` | hyphenated (`focus_neuron_id`) | `agents-users-v1` |
| `AppName` | same id, `-` → `.` | `agents.users.v1` |

**Before wiring AG-UI:** search the module for existing identity constants. If found in one place, use it. If scattered, consolidate (with user permission). If absent, create from `references/templates/central-identity.go.example` (greenfield default: `internal/info/info.go`).

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go services may live in subfolders or at the neuron root — follow the neuron you are editing. `blocks/agent` often uses `agent/`; that is a convention, not a requirement. If multiple `go.mod` files exist, ask which service receives the AG-UI launcher.

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
2. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
3. **Neuron anchors** — nearest `go.mod` under the neuron build root for the service you are editing. For Spanner proto work, `tools.proto` under the matching define tree (`workstations.define_repos`).
4. **Ask user** — Smallest missing piece only (which `go.mod` when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — `workstations.build_repos` from the runtime context.

2. **Go module** — nearest `go.mod` under that root. AG-UI wiring is in that module's entrypoint.

3. **Identity** — `focus_neuron_id` from runtime context → `NeuronId`; derive `AppName` with `-` → `.`. Check for existing `internal/info` before creating.

4. **Infra** — derive from the neuron build root as `<workstations.build_repos entry>/infra` for Terraform (`alis.agui.history.v1` module).

5. **Define** — `workstations.define_repos` for `tools.proto` orphan imports. Follow **`SKILL.md`** → **Proto imports**.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Use `<alis-runtime-context>` values first | Manually parse `~/alis.build` paths or read infra terraform files for neuron id |
| Consolidate identity to one central package before wiring | Add duplicate neuron id consts in `history.go` or `main.go` |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Use the runtime context for build/define/infra paths | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of runtime context or MCP |
| Use **`SKILL.md`** and **`references/infra-agui-history.md`** for proto/infra steps | Follow define-stubs.md or add-tool proto workflows from another skill |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` at the path they give you.
