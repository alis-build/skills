<p align="center">
  <img src="assets/logo.svg" alt="Alis Build logo" width="96" height="96">
</p>

<h1 align="center">Alis Build Skills</h1>

<p align="center">
  Agent skills for building <a href="https://go.alis.build/adk">ADK Go</a> agents on the Alis platform.
</p>

<p align="center">
  <a href="https://skills.sh/alis-build/skills"><img src="https://skills.sh/alis-build/skills" alt="Install via skills.sh"></a>
</p>

> **Note:** For the cross-agent Agent Skills standard, see [agentskills.io](https://agentskills.io).

## What are skills?

Skills are self-contained folders of instructions, references, and templates that agents load when a task matches the skill's `description`. They teach agents how to complete specialized tasks in a repeatable way — proto-backed tool wiring, long-running operations, launcher setup, and more — instead of relying on one-off prompts.

Each skill is a directory with a `SKILL.md` file containing YAML frontmatter and markdown instructions. Agents discover skills via the [skills CLI](https://github.com/vercel-labs/skills) and apply them when the user's request fits the skill's scope.

## About this repository

This repository contains workflow skills for **ADK Go agent development** on the Alis platform. They guide agents through concrete tasks such as adding synchronous tools, wiring LRO infrastructure, enabling AG-UI clients, and embedding runtime skills inside the Go binary.

Each installable skill is self-contained under `skills/<category>/<domain>/<skill-name>/` with:

- **`SKILL.md`** — agent-readable instructions and metadata
- **`references/`** — checklists, workspace guides, and code or infra templates
- **`evals/`** — eval cases for testing skill behavior

These skills assume work inside an Alis ADK neuron workspace. Agents should discover paths from open folders and `.alis/agents/AGENTS.md` when present — not from hard-coded product names.

## Installation

List available skills:

```bash
npx skills add alis-build/skills --list
```

Install all skills from this repository:

```bash
npx skills add alis-build/skills
```

Install a specific skill:

```bash
npx skills add alis-build/skills --skill add-agent-skills
npx skills add alis-build/skills --skill add-agui
npx skills add alis-build/skills --skill add-lro
npx skills add alis-build/skills --skill add-scheduler
npx skills add alis-build/skills --skill add-tool
```

### Scope

| Scope   | Flag      | Location                                  | Use case                     |
| ------- | --------- | ----------------------------------------- | ---------------------------- |
| Project | (default) | `./.agents/skills/` or agent-specific dir | Share with the whole team    |
| Global  | `-g`      | `~/.cursor/skills/` etc.                  | Use across all your projects |

Supported agents include **Cursor**, **Codex**, **Claude Code**, **OpenCode**, **Windsurf**, and [others](https://github.com/vercel-labs/skills#supported-agents).

### Usage

After installing, mention the skill in your prompt:

> Use the add-tool skill to add a synchronous ToolsService RPC for listing widgets.

> Wire AG-UI for CopilotKit using the add-agui skill.

## Available skills

ADK Go skills for building [go.alis.build/adk](https://go.alis.build/adk) agents.

| Skill                | Directory                                     | Description                                                                                                              |
| -------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **add-tool**         | `skills/engineering/adk-go/add-tool/`         | Add synchronous ADK tools from `tools.proto`, define-generated stubs, and `functiontool` wrappers                        |
| **add-lro**          | `skills/engineering/adk-go/add-lro/`          | Add long-running tools backed by `google.longrunning.Operation`, `alis.lro.v2` infra, and resumable chat sessions        |
| **add-agui**         | `skills/engineering/adk-go/add-agui/`         | Wire the AG-UI web sublauncher for CopilotKit and other AG-UI SSE clients alongside the existing web launcher            |
| **add-scheduler**    | `skills/engineering/adk-go/add-scheduler/`    | Wire the A2A scheduler extension with Spanner-backed scheduling and Cloud Tasks delivery for recurring agent invocations |
| **add-agent-skills** | `skills/engineering/adk-go/add-agent-skills/` | Embed runtime `SKILL.md` packs under `internal/skills/` via `skilltoolset` and wire them into `llmagent.Config.Toolsets` |

### Which skill to use

| Need                                               | Skill                |
| -------------------------------------------------- | -------------------- |
| Immediate-return proto-backed RPC tool             | **add-tool**         |
| Async work that returns an Operation handle        | **add-lro**          |
| CopilotKit / AG-UI SSE frontend streaming          | **add-agui**         |
| Scheduled or recurring A2A agent invocations       | **add-scheduler**    |
| Embedded runtime skills inside the Go agent binary | **add-agent-skills** |

These skills are complementary but not interchangeable. Each `SKILL.md` includes a "When not to use" section pointing to the right alternative.

## Creating a skill

Copy [`skills/template/SKILL.template.md`](skills/template/SKILL.template.md) to `skills/<category>/<domain>/<skill-name>/SKILL.md` and fill in the frontmatter and instructions. The template is not installed by the CLI (only files named `SKILL.md` are discovered).

```markdown
---
name: my-adk-skill
description: A clear description of what this skill does and when an agent should use it.
---

# My ADK Skill

Instructions, checklists, and links to references/ go here.

## When to use

Describe the triggers and scope.

## When not to use

Point to sibling skills or alternatives.
```

Required frontmatter fields:

- **`name`** — unique identifier (lowercase, hyphens for spaces)
- **`description`** — complete description of what the skill does and when to use it; this is the primary trigger for agent discovery

Optional frontmatter:

- **`disable-model-invocation`** — set to `true` when the skill should only be invoked explicitly, not auto-selected by the model

Place supporting material alongside `SKILL.md`:

- **`references/`** — detailed guides, checklists, and `.example` templates
- **`evals/evals.json`** — test cases for validating skill behavior

## Contributing

Contributors can use Anthropic's [**skill-creator**](https://www.skills.sh/anthropics/skills/skill-creator) skill to draft new skills, write evals, iterate on instructions, and improve triggering accuracy. Install it alongside this repository's skills:

```bash
npx skills add https://github.com/anthropics/skills --skill skill-creator
```

Then ask your agent to use skill-creator — for example, to add a new ADK Go skill from [`skills/template/SKILL.template.md`](skills/template/SKILL.template.md), or to refine an existing skill's `description` and eval cases under `skills/engineering/adk-go/`.

## Repository structure

Installable skills live under `skills/` so the [skills CLI](https://github.com/vercel-labs/skills) can discover them. Use `SKILL.template.md` for the starter template (not `SKILL.md`) so nested paths like `skills/engineering/adk-go/<skill-name>/` are included when the CLI scans the repo.

```
.
├── README.md
├── LICENSE
├── assets/
│   └── logo.svg
└── skills/
    ├── template/
    │   └── SKILL.template.md   # copy to SKILL.md when authoring; not installed by CLI
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
            ├── add-scheduler/
            │   ├── SKILL.md
            │   ├── evals/
            │   └── references/
            └── add-agent-skills/
                ├── SKILL.md
                ├── evals/
                └── references/
```

Skills are grouped by category under `skills/engineering/`. Browse existing skills for patterns before authoring a new one.

## Learn more

- [agentskills.io](https://agentskills.io) — Agent Skills standard
- [skills.sh/alis-build/skills](https://skills.sh/alis-build/skills) — skill catalog for this repository
- [skill-creator](https://www.skills.sh/anthropics/skills/skill-creator) — create, test, and iteratively improve skills
- [vercel-labs/skills](https://github.com/vercel-labs/skills) — CLI, install paths, and supported agents
- [go.alis.build](https://pkg.go.dev/go.alis.build) — Alis Build Golang packages

## License

Apache-2.0. See [LICENSE](LICENSE).
