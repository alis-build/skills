# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron folder shape

Version is in the neuron id (e.g. `agent-v1`), not a nested `v1/` folder:

```text
<neuron-id>/
  agent/          # go.mod, main.go, Dockerfile
  infra/          # Terraform; local.neuron = "<neuron-id>"
  .playground/    # post-deploy validation (when present)
```

## Canonical paths

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Define repo root | `~/alis.build/<landing-zone>/define/` |
| Neuron build tree | `~/alis.build/<lz>/build/<product>/<neuron>/` |
| Neuron protos | `~/alis.build/<lz>/define/<product>/<neuron>/` (e.g. `tools.proto`) |

Define paths include a `<product>/` segment; build paths do not repeat product inside the neuron folder.

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids, versions, environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
2. **Parse path** — If cwd or an open file is under `~/alis.build/...`, extract `<lz>`, `<product>`, `<neuron>` from path segments.
3. **Neuron anchors** — `agent/go.mod`, `infra/` → `local.neuron` / `var.neuron`, `tools.proto` → `package` line.
4. **Ask user** — Smallest missing piece only (landing zone, product, or neuron).

## Deriving the paired repo

When only one repo is checked out:

- From build `~/alis.build/<lz>/build/<product>/<neuron>/` → define at `~/alis.build/<lz>/define/<product>/<neuron>/`
- From define `~/alis.build/<lz>/define/<product>/<neuron>/` → build at `~/alis.build/<lz>/build/<product>/<neuron>/`
- If not under `~/alis.build` → MCP `CloneProduct` / `PullDefine`, or ask for landing zone + product

## Path discovery (within a neuron)

| Need | Where |
| ---- | ----- |
| Proto **package** (for code generation) | `package` line in the `tools.proto` you edit |
| **Service id** | `local.neuron` or `var.neuron` in `infra/` |
| Go **module** import path | `go.mod` in `agent/` |

After **any** proto change, follow **`define-stubs.md`** before Go or `go.mod` edits.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Edit proto + code for the **same** neuron | Edit protos or code for another neuron from memory or templates |
| Read `package` and `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Ask the user if pairing is unclear | Guess repo layout |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
