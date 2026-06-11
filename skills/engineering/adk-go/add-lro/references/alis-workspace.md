# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

Two related concepts — do not conflate them.

**Neuron id** (platform identifier):

- From `ViewProduct`, `CreateNeuron`, or `local.neuron` / `var.neuron` in `infra/`.
- Hyphen-separated; often encodes several logical segments and a version suffix (`…-v1`, `…-v2`, `…-admin-v1`, etc.).
- A product can host many neuron ids at once — confirm the target id when several exist.

**Neuron repo path** (on disk):

- Multi-segment directory under the product, commonly ending in a version folder (`v1/`, `v2/`, …).
- Usually **not** a single folder whose name equals the neuron id.
- The same `<neuron-path>/` trail appears under both build and define repos.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed** on every neuron in the build repo. All other folders and files are up to the developer.

`infra/` holds Terraform and `local.neuron` / `var.neuron` for the neuron id. Treat the **parent of `infra/`** as the neuron root on disk.

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

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Define repo root | `~/alis.build/<landing-zone>/define/` |
| Neuron build root | `~/alis.build/<lz>/build/<product>/<neuron-path>/` (parent of `infra/`) |
| Neuron define tree | `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/` |

- `<neuron-path>` — multi-segment trail from the product folder to the version leaf (e.g. `…/v1/`). Same trail in build and define.
- `<define-product-path>` — product location under define; may be nested when the product id contains dots (`example.product` → `example/product/`). Confirm from MCP or the define repo layout — do not assume it matches the build `<product>` folder name.

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids, versions, environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
2. **Parse path** — Under `~/alis.build/...`, locate `infra/` with `local.neuron` (or walk up from open files until you find it). Its parent is the neuron root; walk up to the product folder to capture `<neuron-path>`.
3. **Neuron anchors** — `infra/` → `local.neuron` / `var.neuron`; nearest `go.mod` under that neuron root for the service you are editing; `tools.proto` at the matching define tree → `package` line.
4. **Ask user** — Smallest missing piece only (landing zone, product, neuron id, which service when multiple `go.mod` exist, or which neuron when several exist).

## Deriving the paired repo

When only one repo is checked out:

1. Record `<neuron-path>/` — trail from the product folder to the neuron root (parent of `infra/`).
2. **Build → define** — `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/`
3. **Define → build** — `~/alis.build/<lz>/build/<product>/<neuron-path>/`
4. If `<define-product-path>` is unknown, inspect the define repo under `~/alis.build/<lz>/define/` or ask the user.
5. If not under `~/alis.build` → MCP `CloneProduct` / `PullDefine`, or ask for landing zone + product.

## Path discovery (within a neuron)

| Need | Where |
| ---- | ----- |
| **Neuron root** | Parent directory of `infra/` |
| **Neuron id** / service id | `local.neuron` or `var.neuron` in `infra/` |
| Go **module** | Nearest `go.mod` under the neuron root for the service you are editing |
| Entrypoint | `main.go` (or project entrypoint) in the same module directory |
| Proto **package** | `package` line in `tools.proto` under the neuron define tree |
| Docker build context | Directory containing the target `Dockerfile` (inspect filesystem) |

After **any** proto change, follow **`define-stubs.md`** before Go or `go.mod` edits.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Edit proto + code for the **same** neuron id and neuron root | Edit another neuron's files from memory or templates |
| Anchor on `infra/` + `local.neuron`, then find the correct `go.mod` | Assume every neuron uses an `agent/` subfolder |
| Read `package`, `go.mod`, and `local.neuron` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals a single folder name |

User corrections override everything — re-read `package`, `go.mod`, and `local.neuron` at the path they give you.
