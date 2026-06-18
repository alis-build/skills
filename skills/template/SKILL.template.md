---
name: template-skill
description: A clear description of what this skill does and when an agent should use it.
metadata:
  alis.context.version: "1"
  # Read mask for GetContext — list only the Context field paths this skill needs.
  alis.context.requires: >-
    organisation organisation_id product product_id
    focus_neuron focus_neuron_id environment session.ide
    workstations.root_directory workstations.define_repos
    workstations.build_repos workstations.playground
---

# Template Skill

Instructions, checklists, and links to references/ go here.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads `alis.context.requires`
below and uses it as the `read_mask` on `GetContext` — the block carries **only** those fields.
**When the block is present, its values are authoritative**: use the exact paths and resource
names verbatim, and do **not** scan folders, derive paths from the filesystem, or ask the user
to confirm a value that was already provided.

**Resolution order** — when discovering workspace values before edits:

1. **Resolve script** — `bash scripts/resolve-alis-workspace.sh --json` (pass `--cwd` when needed). Prefer script output when a field is present.
2. **`<alis-runtime-context>`** — for any **read-mask** field still missing after the script, use the block verbatim.
3. **Everything else** — MCP, path conventions, neuron anchors, then ask the user.

**Never invent environment IDs or commit SHAs — look them up or ask.**

### Context fields (`alis.context.requires`)

Trim the manifest above to the fields this skill actually needs. The table below must match it
exactly — do not document fields that are not in the read mask.

| Value              | Context field                                              | If absent, how to obtain it                                                                                                                                                                            |
| ------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Organisation       | `organisation` (`organisations/*`)                         | MCP `GetLandingZone`; else ask the user                                                                                                                                                                |
| Product            | `product` (`organisations/*/products/*`)                   | MCP `ViewProduct`; else ask the user                                                                                                                                                                   |
| Focused neuron     | `focus_neuron` (`.../neurons/*`)                           | This skill **always creates a new neuron** for the quickstart, so `focus_neuron` is **not** the target — treat it (or any existing service) as off-limits and ask the user for a new neuron ID instead |
| Environment        | `environment` (`.../environments/*`)                       | MCP `ViewProduct`; **never invent**                                                                                                                                                                    |
| Alis Build root    | `workstations.root_directory`                              | Default `~/alis.build`; confirm with the user if unsure                                                                                                                                                |
| Neuron define tree | `workstations.define_repos` (entry for the **new** neuron) | `<root_directory>/<landing-zone>/define/<org>/<product>/<service>/<version>`                                                                                                                           |
| Neuron build root  | `workstations.build_repos` (entry for the **new** neuron)  | Parent of the neuron's `infra/`; else derive from the filesystem                                                                                                                                       |
| Playground test    | `workstations.playground`                                  | `<neuron build root>/.playground/main_test.go`                                                                                                                                                         |
| Host editor        | `session.ide`                                              | If absent or unknown, drive the flow through MCP tools / manual steps as today and do **not** use the deep-link commands. See **IDE Guided Mode**.                                                     |

**Ids** — available directly as fields, so do not parse resource names: `organisation_id` (the
landing-zone id), `product_id`, and `focus_neuron_id`. Only `environment id` is still derived
(the last segment of `environment`).

## When to use

Describe the triggers and scope.

## When not to use

Point to sibling skills or alternatives.

## Available scripts

- **`scripts/resolve-alis-workspace.sh`** — Resolves Alis Build workspace context (organisation, product, neuron, paths) from the current working directory. Run with `--json` for structured output, `--help` for usage.
