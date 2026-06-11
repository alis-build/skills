# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

Primary work is Go wiring in the build repo (`webagui.NewLauncher`). Optional proto edits for Spanner table provisioning are documented in **`SKILL.md`** → **Proto imports for Spanner tables** — not in this file.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron folder shape

Version is in the neuron id (e.g. `agent-v1`), not a nested `v1/` folder:

```text
<neuron-id>/
  agent/          # go.mod, main.go, Dockerfile
  infra/          # Terraform; local.neuron = "<neuron-id>"
```

## Canonical paths

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Define repo root | `~/alis.build/<landing-zone>/define/` |
| Neuron build tree | `~/alis.build/<lz>/build/<product>/<neuron>/` |
| Neuron protos (optional) | `~/alis.build/<lz>/define/<product>/<neuron>/` (e.g. `tools.proto`) |

Define paths include a `<product>/` segment; build paths do not repeat product inside the neuron folder.

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids, versions, environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
2. **Parse path** — If cwd or an open file is under `~/alis.build/...`, extract `<lz>`, `<product>`, `<neuron>` from path segments.
3. **Neuron anchors** — `agent/go.mod`, `infra/` → `local.neuron` / `var.neuron`. For optional Spanner proto work, `tools.proto` at the define path above.
4. **Ask user** — Smallest missing piece only (landing zone, product, or neuron).

## Deriving the paired repo

When only one repo is checked out:

- From build `~/alis.build/<lz>/build/<product>/<neuron>/` → define at `~/alis.build/<lz>/define/<product>/<neuron>/`
- From define `~/alis.build/<lz>/define/<product>/<neuron>/` → build at `~/alis.build/<lz>/build/<product>/<neuron>/`
- If not under `~/alis.build` → MCP `CloneProduct` / `PullDefine`, or ask for landing zone + product

## Quick discovery (before any edit)

1. **Agent module** — `go.mod` under `~/alis.build/<lz>/build/<product>/<neuron>/agent/`. AG-UI wiring is in the entrypoint.

2. **Service id** — `local.neuron` (or `var.neuron`) in `infra/`. Passed to `webagui.NewLauncher` — not the proto package name and not necessarily `llmagent.Config.Name`.

3. **Optional proto (Spanner only)** — When threads/history tables are needed, edit `tools.proto` at the define path and follow **`SKILL.md`** → **Proto imports for Spanner tables** (ask user to run define). Skip proto work for launcher-only wiring.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep Go edits on the **same** neuron you discovered | Edit another neuron's code from memory or templates |
| Read `go.mod` and `infra/local.neuron` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Use **`SKILL.md`** for proto/import/define steps | Follow `define-stubs.md` or add-tool proto workflows from another skill |
| Ask the user if pairing is unclear | Guess repo layout |

User corrections override everything — re-read `go.mod` and infra config at the path they give you.
