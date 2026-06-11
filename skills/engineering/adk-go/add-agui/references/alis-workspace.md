# Agent workspace layout

Portable path and repo rules for agents working in an ADK agent project on Alis Build. Use this file for module, infra, and repo discovery without hardcoded paths.

Primary work is Go wiring in the build repo (`webagui.NewLauncher`). Optional proto edits for Spanner table provisioning are documented in **`SKILL.md`** → **Proto imports for Spanner tables** — not in this file.

## Platform hierarchy

Landing zone (organisation) → product → neuron (deployable service). Build and define live in separate repos under `~/alis.build/`.

## Neuron id vs repo path

**Neuron id** — platform identifier from `ViewProduct` or `local.neuron` / `var.neuron` in `infra/`. Hyphen-separated; may encode several segments and a version (`…-v1`, `…-v2`, etc.). A product can host many neuron ids — pick the target explicitly.

**Neuron repo path** — multi-segment directory under the product (often ending in `v1/`, `v2/`, …), usually **not** a single folder named like the neuron id. The same `<neuron-path>/` appears under build and define.

## Build repo layout (under `<neuron-path>/`)

**Only `infra/` is guaranteed.** The parent of `infra/` is the neuron root. Go services may live in subfolders or at the neuron root — follow the neuron you are editing. `blocks/agent` often uses `agent/`; that is a convention, not a requirement. If multiple `go.mod` files exist, ask which service receives the AG-UI launcher.

## Canonical paths

| Artifact | Path |
| -------- | ---- |
| Build repo root | `~/alis.build/<landing-zone>/build/<product>/` |
| Define repo root | `~/alis.build/<landing-zone>/define/` |
| Neuron build root | `~/alis.build/<lz>/build/<product>/<neuron-path>/` (parent of `infra/`) |
| Neuron define tree | `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/` |

- `<define-product-path>` may be nested when the product id contains dots — confirm from MCP or the define repo.

## Discovery tier order

1. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron ids, versions, environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
2. **Parse path** — Locate `infra/` with `local.neuron` (or walk up from open files). Its parent is the neuron root; capture `<neuron-path>` up to the product folder.
3. **Neuron anchors** — `infra/local.neuron`; nearest `go.mod` under the neuron root for the service you are editing. For optional Spanner proto work, `tools.proto` under the matching define tree.
4. **Ask user** — Smallest missing piece only (landing zone, product, neuron id, which `go.mod` when several exist).

## Deriving the paired repo

1. Record `<neuron-path>/` to the neuron root (parent of `infra/`).
2. **Build → define** — `~/alis.build/<lz>/define/<define-product-path>/<neuron-path>/`
3. **Define → build** — `~/alis.build/<lz>/build/<product>/<neuron-path>/`

## Quick discovery (before any edit)

1. **Neuron root** — parent of `infra/` under the build tree.

2. **Go module** — nearest `go.mod` under that root. AG-UI wiring is in that module's entrypoint.

3. **Service id** — `local.neuron` in `infra/`. Passed to `webagui.NewLauncher` — not the proto package name and not necessarily `llmagent.Config.Name`.

4. **Optional proto (Spanner only)** — When threads/history tables are needed, edit `tools.proto` under the neuron define tree and follow **`SKILL.md`** → **Proto imports for Spanner tables** (ask user to run define). Skip proto work for launcher-only wiring.

## Hard rules

| Do | Do not |
| ---- | ------ |
| Keep Go edits on the **same** neuron id and neuron root | Edit another neuron's code from memory or templates |
| Anchor on `infra/` + `local.neuron`, then find the correct `go.mod` | Assume every neuron uses an `agent/` subfolder |
| Read `go.mod` and `infra/local.neuron` from the open project | Invent paths from another product or chat |
| Follow discovery tier order above | Rely on ad-hoc metadata files instead of MCP or `~/alis.build` path rules |
| Use **`SKILL.md`** for proto/import/define steps | Follow `define-stubs.md` or add-tool proto workflows from another skill |
| Ask the user if pairing is unclear | Guess repo layout or assume neuron id equals one folder name |

User corrections override everything — re-read `go.mod` and infra config at the path they give you.
