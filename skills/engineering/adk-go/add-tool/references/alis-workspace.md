# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — hyphen-separated platform identifier (e.g. `agents-users-v1`, `ai-v1`). Derived from the on-disk neuron path by replacing `/` with `-`.

**Neuron repo path** — multi-segment directory under the product (e.g. `agents/users/v1`, `ai/v1`). The same trail appears under both build and define repos.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed** on every neuron in the build repo. All other folders and files are up to the developer.

`infra/` holds Terraform configuration. Treat the **parent of `infra/`** as the neuron root on disk.

Go services, Dockerfiles, and entrypoints may live **anywhere under that neuron root**. Common patterns:

```text
# Services in named subfolders
<neuron-path>/
  infra/
  <service-a>/
    go.mod
    main.go
    Dockerfile
  <service-b>/
    go.mod
    Dockerfile

# Service at neuron root
<neuron-path>/
  infra/
  go.mod
  main.go
  Dockerfile
```

`blocks/agent` and many ADK scaffolds use an `agent/` subfolder — that is one convention, not a platform requirement. **Follow the layout of the neuron you are editing.** If a neuron has multiple `go.mod` files, ask which service is the target.

Derive Docker build paths from the filesystem (where each `Dockerfile` lives), not from a assumed folder name.

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
3. **Neuron anchors** — nearest `go.mod` under the neuron build root for the service you are editing; `tools.proto` at the matching define tree → `package` line.
4. **Ask user** — Smallest missing piece only (which service when multiple `go.mod` exist, or which neuron when several exist).

## Path discovery (within a neuron)

| Need | Where |
| ---- | ----- |
| **Neuron root** | `workstations.build_repos` from the resolve script |
| **Neuron id** | `focus_neuron_id` from the resolve script |
| **Infra** | `workstations.infra` from the resolve script |
| Go **module** | Nearest `go.mod` under the neuron root for the service you are editing |
| Entrypoint | `main.go` (or project entrypoint) in the same module directory |
| Proto **package** | `package` line in `tools.proto` under the neuron define tree (`workstations.define_repos`) |
| Docker build context | Directory containing the target `Dockerfile` (inspect filesystem) |

After **any** proto change, follow **`define-stubs.md`** before Go or `go.mod` edits.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Run `bash scripts/resolve-alis-workspace.sh --json` first | Manually parse `~/alis.build` paths or read infra terraform files |
| Edit proto + code for the **same** neuron id and neuron root | Edit another neuron's files from memory or templates |
| Use the resolve script output for build/define/infra paths | Assume every neuron uses an `agent/` subfolder |
| Read `package`, `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of the script or MCP |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals a single folder name |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
