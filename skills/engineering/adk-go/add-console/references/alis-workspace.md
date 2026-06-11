# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module and infra discovery without hardcoded paths.

This skill has **no proto or define step** — only build-repo discovery and neuron anchors for the Go module and entrypoint you are editing.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Agent code lives in the product **build** repo under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — platform identifier from `ViewProduct` or `local.neuron` / `var.neuron` in `infra/`. Hyphen-separated; may encode several segments and a version (`…-v1`, `…-v2`, etc.). A product can host many neuron ids — pick the target explicitly.

**Neuron repo path** — multi-segment directory under the product (often ending in `v1/`, `v2/`, …), usually **not** a single folder named like the neuron id.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go code may live in a subfolder or at the neuron root — follow the neuron you are editing. If multiple `go.mod` files exist under one neuron, ask which service is the target.

## Canonical paths

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Neuron build root | `~/alis.build/<lz>/build/<product>/<neuron-path>/` (parent of `infra/`) |

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids. Use `CloneProduct` for canonical clone paths.
2. **Parse path** — Locate `infra/` with `local.neuron` (or walk up from open files). Its parent is the neuron root; capture `<neuron-path>` up to the product folder.
3. **Neuron anchors** — `infra/local.neuron`; nearest `go.mod` under the neuron root for the service you are editing.
4. **Ask user** — Smallest missing piece only (landing zone, product, neuron id, which `go.mod` when several exist).

## Quick discovery (before any edit)

1. **Neuron root** — parent of `infra/` under `~/alis.build/<lz>/build/<product>/<neuron-path>/`.

2. **Go module** — nearest `go.mod` under that root. Console wiring is in the entrypoint (`console.NewLauncher` on the web launcher stack).

3. **Service id** — `local.neuron` in `infra/` when deployment or sibling sublaunchers need alignment.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Anchor on `infra/` + `local.neuron`, then find the correct `go.mod` | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` and `local.neuron` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` at the path they give you.
