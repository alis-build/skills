---
name: add-agent-skills
description: >
  Embeds ADK runtime agent skills (markdown SKILL.md under internal/skills/skills/) via skilltoolset
  and wires them into llmagent.Config.Toolsets so the model can load_skill. Use when bootstrapping
  internal/skills, adding one or more embedded skills (e.g. deep-research), wiring SkillToolset in
  main.go, or when the user mentions skill toolset, go:embed skills, load_skill, skill folders, or
  specialized agent instructions—even if they do not say skilltoolset or Toolsets. Do not use for
  Cursor/build skills under neuron .agents/skills/ (use those separately) or for proto function tools
  (add-tool / add-lro). No proto or define step.
disable-model-invocation: true
---

# Add agent skills (skill toolset)

Agent **skills** are markdown instruction packs the model loads on demand (`load_skill`, etc.). They live under `internal/skills/skills/<name>/SKILL.md`, are embedded into the binary, and exposed through ADK **`skilltoolset`** on `llmagent.Config.Toolsets` — separate from proto-backed **Tools** (`add-tool` / `add-lro`).

Read **`../../references/alis-workspace.md`** for neuron paths. If **`.alis/agents/AGENTS.md`** exists, read it first.

## When to use

See the skill **description** (primary trigger). In short: runtime `internal/skills/skills/*/SKILL.md` + `Toolsets`, not neuron `.agents/skills/`, not proto tools.

## When not to use

| Need | Use instead |
|------|-------------|
| Sync / LRO RPC tools | `../add-tool/SKILL.md`, `../add-lro/SKILL.md` |
| Cursor IDE skills under `.agents/skills/` | Different system — this skill is **runtime** skills inside the Go agent |
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

- Putting runtime skills in `.agents/skills/` at the neuron root — that path is for **Cursor/build** skills; runtime skills belong in `agent/internal/skills/skills/`.
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
