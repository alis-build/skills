---
name: adk-add-agent-skills
description: >
  Use this skill when the user wants embedded ADK runtime skills (SKILL.md under internal/skills),
  skilltoolset wiring, or load_skill toolsets on the agent — even if they do not say skilltoolset.
  Embeds markdown instruction packs via go:embed and llmagent.Config.Toolsets. Not for proto
  function tools (add-tool/add-lro) or neuron .agents/skills install skills.
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    focus_neuron_id workstations.build_repos
---

# Add agent skills (skill toolset)

Agent **skills** are markdown instruction packs the model loads on demand (`load_skill`, etc.). They live under `internal/skills/skills/<name>/SKILL.md`, are embedded into the binary, and exposed through ADK **`skilltoolset`** on `llmagent.Config.Toolsets` — separate from proto-backed **Tools** (`add-tool` / `add-lro`).

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when the working directory differs from the target neuron). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim. Do not re-derive or ask the user to confirm values already provided.
3. **MCP** — `ListLandingZones` → `GetLandingZone` → `ViewProduct(lz, product)` for neuron lists, versions, and environments. Use `CloneProduct` / `PullDefine` for canonical clone paths. Never invent environment IDs.
4. **Neuron anchors** — nearest `go.mod` under `workstations.build_repos`.
5. **Ask user** — Smallest missing piece only.

**Never invent environment IDs or commit SHAs.** Do not read infra Terraform files for neuron id or workstation paths.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent (after script + block) |
| ----- | ------------- | -------------------------------- |
| Neuron / service id | `focus_neuron_id` | Neuron scope for `internal/skills` and entrypoint wiring |
| Neuron build root | `workstations.build_repos` | Parent of `infra/` where the agent Go module and `main.go` live |

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.

**Before any edits**, run the workspace resolver to identify the neuron, paths, and service id:

```bash
bash scripts/resolve-alis-workspace.sh --json
```

Then read **`references/alis-workspace.md`** for path rules and tier 3+ discovery. Use `workstations.build_repos` for the agent module and entrypoint.

## When to use

See the skill **description** (primary trigger). In short: runtime `internal/skills/skills/*/SKILL.md` + `Toolsets`, not agent-tooling `.agents/skills/`, not proto tools.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO RPC tools | **add-tool**, **add-lro** |
| Agent-tooling install skills under `.agents/skills/` | Different system — this skill is **runtime** skills inside the Go agent |
| **define** / `tools.proto` | Not required |

## Architecture

```
internal/skills/skills/<skill-name>/SKILL.md
        ↓ go:embed
internal/skills/skills.go  →  skilltoolset.New + FileSystemSource
        ↓
main.go  →  llmagent.Config.Toolsets: []tool.Toolset{skillToolset}
```

Keep **Tools** (function tools) and **Toolsets** (skills) separate unless you intentionally merge toolsets via `add-tool`’s `NewToolSet`.

## Phase A — Bootstrap skill toolset (one-time)

| # | Action | Template |
|---|--------|----------|
| 1 | Create `internal/skills/skills.go` with `//go:embed skills` and `SkillToolset(ctx)` | `references/templates/skills.go.example` |
| 2 | Create `internal/skills/skills/` directory (can start empty or with one skill) | — |
| 3 | Wire entrypoint: import skills package, call `SkillToolset`, set `Toolsets` | `references/templates/agent-wiring.go.example` |
| 4 | `go build ./...` | — |

## Phase B — Add a skill (repeat per skill)

| # | Action |
|---|--------|
| 1 | Create folder `internal/skills/skills/<skill-name>/` (kebab-case directory name) |
| 2 | Add `SKILL.md` with YAML frontmatter `name` + `description`, then markdown instructions | `references/templates/SKILL.md.example` |
| 3 | Ensure frontmatter `name` matches how the model will call `load_skill` (usually same as folder name) |
| 4 | Rebuild — `go:embed` picks up new files on next `go build` |

Add as many skills as needed; each is one folder + one `SKILL.md`.

## SKILL.md requirements

- **Required frontmatter:** `name` (lowercase, hyphens), `description` (when to use — shown for skill discovery).
- **Body:** Instructions the model follows after `load_skill` loads the skill.
- **Optional subfolders** (ADK convention): `references/`, `assets/`, `scripts/` — loaded via skill resource tools, not by guessing paths.

## Verification

- [ ] `go build ./...` passes (embed includes all `skills/**` files)
- [ ] Entrypoint sets `Toolsets: []tool.Toolset{skillToolset}` (handle `SkillToolset` error)
- [ ] Each skill has valid `---` frontmatter with `name` and `description`
- [ ] Local ADK run lists skill tools; model can `load_skill` for the new skill name

## Pitfalls

- Putting runtime skills in `.agents/skills/` at the neuron root — that path is for **agent-tooling install** skills (via skills.sh); runtime skills belong in `agent/internal/skills/skills/`.
- Forgetting `//go:embed skills` path matches the directory name exactly.
- Only updating `Tools` but not `Toolsets` — skills will not appear.
- Duplicate `name` in frontmatter across two folders.
- Empty `description` — hurts automatic skill selection.

## Optional enhancements (out of scope for minimal wiring)

- Custom `SystemInstruction` on `skilltoolset.Config` (see richer agents that document `load_skill` usage explicitly).
- `skill.WithCompletePreloadSource` for preloading — only when you need that behavior.

## Templates

| File | Purpose |
|------|---------|
| `references/templates/skills.go.example` | Embed + `SkillToolset` |
| `references/templates/agent-wiring.go.example` | Entrypoint `Toolsets` |
| `references/templates/SKILL.md.example` | Starter skill markdown |
