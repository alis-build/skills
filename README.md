# skills

A collection of [Agent Skills](https://skills.sh/) for AI coding agents.

[![skills.sh](https://skills.sh/alis-build/skills)](https://skills.sh/alis-build/skills)

## Install

```bash
npx skills add alis-build/skills
```

Install a specific skill:

```bash
npx skills add alis-build/skills --skill add-agent-skills
npx skills add alis-build/skills --skill add-agui
npx skills add alis-build/skills --skill add-lro
npx skills add alis-build/skills --skill add-tool
```

### Scope

| Scope   | Flag      | Location                                  | Use case                     |
| ------- | --------- | ----------------------------------------- | ---------------------------- |
| Project | (default) | `./.agents/skills/` or agent-specific dir | Share with the whole team    |
| Global  | `-g`      | `~/.cursor/skills/` etc.                  | Use across all your projects |

Supported agents include **Cursor**, **Codex**, **Claude Code**, **OpenCode**, **Windsurf**, and [others](https://github.com/vercel-labs/skills#supported-agents).

## Skills

ADK Go skills for building [go.alis.build/adk](https://go.alis.build/adk) agents — wiring tools, launchers, and embedded runtime skills.

| Skill                 | Directory                                         | Description                                                                                                              |
| --------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **add-tool**          | `skills/engineering/adk-go/add-tool/`             | Add synchronous ADK tools from `tools.proto`, define-generated stubs, and `functiontool` wrappers                      |
| **add-lro**           | `skills/engineering/adk-go/add-lro/`              | Add long-running tools backed by `google.longrunning.Operation`, `alis.lro.v2` infra, and resumable chat sessions      |
| **add-agui**          | `skills/engineering/adk-go/add-agui/`             | Wire the AG-UI web sublauncher for CopilotKit and other AG-UI SSE clients alongside the existing web launcher          |
| **add-agent-skills**  | `skills/engineering/adk-go/add-agent-skills/`     | Embed runtime `SKILL.md` packs under `internal/skills/` via `skilltoolset` and wire them into `llmagent.Config.Toolsets` |

## Repository structure

```
skills/
├── README.md
├── LICENSE
└── skills/
    └── engineering/
        └── adk-go/
            ├── add-tool/
            │   ├── SKILL.md
            │   ├── evals/
            │   └── references/
            ├── add-lro/
            │   ├── SKILL.md
            │   ├── evals/
            │   └── references/
            ├── add-agui/
            │   ├── SKILL.md
            │   ├── evals/
            │   └── references/
            └── add-agent-skills/
                ├── SKILL.md
                ├── evals/
                └── references/
```

Skills are grouped by category under `skills/`. Each skill directory contains a `SKILL.md` (the agent-readable skill definition) and optional reference files, evals, and templates.

## License

Apache-2.0. See [LICENSE](LICENSE).
