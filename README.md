<p align="center">
  <img src="assets/logo.svg" alt="Alis Build logo" width="96" height="96">
</p>

<h1 align="center">Alis Build Skills</h1>

<p align="center">
  Agent skills for building with Alis Build.
</p>

<p align="center">
  <a href="https://skills.sh/alis-build/skills"><img src="https://img.shields.io/badge/skills.sh-install-green" alt="Install via skills.sh"></a>
</p>

This repository contains workflow skills for Alis Build projects. The catalog currently focuses on ADK Go agent workflows, and will expand over time as more platform tasks are captured as reusable skills.

Skills are intended to be installed into a project or global agent environment, then invoked when a matching implementation task comes up.

## Plugin access

These skills are available through the Alis Build plugins for supported agent tools.

|                                                                               | Tool        | Plugin                                                                                |
| ----------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------- |
| <img src="assets/geminicli.svg" alt="Gemini CLI logo" width="28" height="28"> | Gemini CLI  | [alis-build/gemini-cli-extension](https://github.com/alis-build/gemini-cli-extension) |
| <img src="assets/claude.svg" alt="Claude Code logo" width="28" height="28">   | Claude Code | [alis-build/claude-plugin](https://github.com/alis-build/claude-plugin)               |
| <img src="assets/codex.svg" alt="Codex logo" width="28" height="28">          | Codex       | [alis-build/codex-plugin](https://github.com/alis-build/codex-plugin)                 |

Install the relevant plugin for your agent tool to access the skills.

## Manual installation

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
npx skills add alis-build/skills --skill add-console
npx skills add alis-build/skills --skill add-lro
npx skills add alis-build/skills --skill new-agent
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

> Use the new-agent skill to create a base ADK-Go agent service on Alis Build.

> Wire AG-UI for CopilotKit using the add-agui skill.

> Add a browser UI / frontend on top of AG-UI using the add-console skill.

## Available skills

Current ADK Go skills for building [go.alis.build/adk](https://go.alis.build/adk) agents.

| Skill                | Directory                                     | Description                                                                                                              |
| -------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **new-agent**        | `skills/engineering/adk-go/new-agent/`        | Guide creation of a base ADK-Go agent service with `blocks/agent`, define, build, deploy, and extension handoff          |
| **add-tool**         | `skills/engineering/adk-go/add-tool/`         | Add synchronous ADK tools from `tools.proto`, define-generated stubs, and `functiontool` wrappers                        |
| **add-lro**          | `skills/engineering/adk-go/add-lro/`          | Add long-running tools backed by `google.longrunning.Operation`, `alis.lro.v2` infra, and resumable chat sessions        |
| **add-agui**         | `skills/engineering/adk-go/add-agui/`         | Wire the AG-UI web sublauncher for CopilotKit and other AG-UI SSE clients alongside the existing web launcher            |
| **add-console**      | `skills/engineering/adk-go/add-console/`      | Wire the bundled Vue web UI sublauncher (chat shell, branding, `/auth/me`); requires **add-agui** and **add-scheduler**   |
| **add-scheduler**    | `skills/engineering/adk-go/add-scheduler/`    | Wire the A2A scheduler extension with Spanner-backed scheduling and Cloud Tasks delivery for recurring agent invocations |
| **add-agent-skills** | `skills/engineering/adk-go/add-agent-skills/` | Embed runtime `SKILL.md` packs under `internal/skills/` via `skilltoolset` and wire them into `llmagent.Config.Toolsets` |

### Which skill to use

| Need                                               | Skill                |
| -------------------------------------------------- | -------------------- |
| Create and understand a base ADK-Go agent service  | **new-agent**        |
| Immediate-return proto-backed RPC tool             | **add-tool**         |
| Async work that returns an Operation handle        | **add-lro**          |
| CopilotKit / AG-UI SSE frontend streaming          | **add-agui**         |
| Bundled Vue web UI in the browser (console launcher) | **add-console**    |
| Scheduled or recurring A2A agent invocations       | **add-scheduler**    |
| Embedded runtime skills inside the Go agent binary | **add-agent-skills** |

These skills are complementary but not interchangeable. Each `SKILL.md` includes a "When not to use" section pointing to the right alternative.

## Learn more

- [skills.sh/alis-build/skills](https://skills.sh/alis-build/skills) — skill catalog for this repository
- [vercel-labs/skills](https://github.com/vercel-labs/skills) — CLI, install paths, and supported agents
- [go.alis.build](https://pkg.go.dev/go.alis.build) — Alis Build Go packages

## License

Apache-2.0. See [LICENSE](LICENSE).
