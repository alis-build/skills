# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module and infra discovery without hardcoded paths.

This skill has **no proto or define step** — only build-repo discovery and neuron anchors for `agent/go.mod` and the entrypoint.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Agent code lives in the product **build** repo under `~/alis.build/`.

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
| Neuron build tree | `~/alis.build/<lz>/build/<product>/<neuron>/` |
| Agent module | `~/alis.build/<lz>/build/<product>/<neuron>/agent/` |

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids and versions. Use `CloneProduct` for canonical clone paths.
2. **Parse path** — If cwd or an open file is under `~/alis.build/<lz>/build/<product>/<neuron>/...`, extract `<lz>`, `<product>`, `<neuron>` from path segments.
3. **Neuron anchors** — `agent/go.mod`, entrypoint under `agent/`, `infra/` → `local.neuron` / `var.neuron` when infra context is needed.
4. **Ask user** — Smallest missing piece only (landing zone, product, or neuron).

## Quick discovery (before any edit)

1. **Agent module** — `go.mod` under `~/alis.build/<lz>/build/<product>/<neuron>/agent/`. Console wiring is in the entrypoint (`console.NewLauncher` on the web launcher stack).

2. **Service id** — `local.neuron` (or `var.neuron`) in `infra/` when deployment or sibling sublaunchers need alignment.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep Go edits on the **same** neuron you discovered | Edit another neuron's code from memory or templates |
| Read `go.mod` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Ask the user if pairing is unclear | Guess repo layout |

User corrections override everything — re-read `go.mod` at the path they give you.
