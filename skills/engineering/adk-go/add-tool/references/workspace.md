# Find the correct agent and proto paths

Read **`../../../references/alis-workspace.md`** and **`../../../references/define-stubs.md`**. If **`.alis/agents/AGENTS.md`** exists, read it first for this product’s repo roots — then use the steps below for sync tool work.

## Quick discovery (before any edit)

1. **Which neuron/version?** — From workspace folders, open files, or the user. It is the `{neuron}/{version}/` directory you are changing (build repo side).

2. **`tools.proto` (define repo)** — Same `{neuron}/{version}/` path in the **define** repository. Read the `package` line → use for **run a define on the package**.

3. **Agent module (build repo)** — `go.mod` + entrypoint (`main.go`), usually under `agent/` in that neuron. All Go tool code goes here.

4. **Neuron id (define CLI)** — `locals.neuron` (or equivalent) in `infra/` → use for **run a define on the neuron**, or ask the user.

## Hard rules

| Do | Do not |
|----|--------|
| Keep define and build edits on the **same** neuron/version | Edit protos or code for a different neuron from memory or templates |
| Use `package` from the `tools.proto` you edited | Substitute package or import paths from another agent |
| Ask the user if build/define pairing or neuron path is unclear | Guess repo layout |

User corrections override everything — re-read `package` and `go.mod` at the path they give you.
