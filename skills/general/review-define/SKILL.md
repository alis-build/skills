---
name: review-define
description: >
  Use this skill when the user wants to review, audit, or lint the protocol buffer definitions
  in a neuron's define tree — for example "review my protos", "check my define", "are my .proto
  files AIP-compliant", "review the API contract before I run Define", or any request to verify
  proto consistency, naming, structure, or documentation quality. Reviews every `.proto` file in
  the focused neuron's define repo for consistency with the Google API Improvement Proposals
  (https://google.aip.dev/general) and ensures every message and service carries clear,
  well-worded comments, asking the user for clarification where intent is unclear.
metadata:
  alis.context.version: "1"
  alis.context.requires: workstations.define_repos
---

# Review Define

Review the protocol buffer contract for the focused neuron **before** it is locked by Define.
The goal is a contract that is consistent with the Google API Improvement Proposals (AIPs,
https://google.aip.dev/general) and that documents itself clearly — every service, method,
message, field, enum, and enum value carries a comment that another developer (or a code
generator turning comments into SDK docs) can rely on.

This is a **review**, not a rewrite. Report findings, propose concrete fixes, and — for the
comment-quality work — **ask the user** when intent is genuinely unclear rather than inventing
behaviour. Only edit `.proto` files when the user asks you to apply a fix.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads this skill's
`alis.context.requires` manifest — a set of `Context` field paths (`alis.os.context.v1`) — and
uses it as the `read_mask` on `GetContext`, so the block carries exactly those resolved fields.
**When the block is present, its values are authoritative**: use the exact paths and resource
names verbatim, and do **not** scan folders, derive paths from the filesystem, or ask the user
to confirm a value that was already provided.

When the block is **absent or the value is missing** (for example, the skill was loaded outside
the Alis MCP), obtain it using the "If absent" rule in the table below. **Never invent a path —
look it up or ask.**

### Context field used by this skill

This skill needs exactly one value: the path to the focused neuron's define tree. It lives on
`workstations` because it is an absolute path true on one machine only; use the entry for the
current workstation.

| Value                  | Context field                                          | If absent, how to obtain it                                                                                                            |
| ---------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| **Neuron define tree** | `workstations.define_repos` (entry for `focus_neuron`) | Default root `~/alis.build`, then `<root>/<landing-zone>/define/<org>/<product>/<service>/<version>`; confirm the folder with the user |

**`workstations.define_repos` is the field that scopes this review.** It points at the focused
neuron's define tree. **Review every `.proto` file in that folder (recursively).** If the entry
is absent, derive the tree from the convention above or ask the user, then confirm the folder
before reading.

## Scope

1. Resolve the define tree from `workstations.define_repos` (entry for `focus_neuron`).
2. Enumerate **all** `.proto` files under that folder, recursively. Do not review protos from
   other neurons, other products, or from memory.
3. Read each file in full before reporting — comments, options, imports, and message/service
   bodies all factor into the review.

If the folder contains no `.proto` files, say so and stop; there is nothing to review.

## Review process

Work in two passes, then report.

### Pass 1 — AIP consistency

Check each `.proto` against the General AIPs and the design AIPs they reference. Use the
checklist below; cite the specific AIP for each finding so the user can verify.

| Area                      | What to check                                                                                                                                                                                                                                                                   | AIP                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Comments present**      | Every service, method, message, field, enum, and enum value has a leading comment.                                                                                                                                                                                              | [192](https://google.aip.dev/192)                                   |
| **Comment style**         | American English, CommonMark only (no headings, tables, raw HTML, ASCII art); backticks around field/method names and literals; method/field comments omit the subject and use third-person present ("Creates a book…", not "This creates…").                                   | [192](https://google.aip.dev/192)                                   |
| **Resource names**        | Resources annotated with `google.api.resource`; `name` field is `string` and used **only** for the resource name; collection IDs are lowerCamel/plural, lower-cased, ASCII; ID segments fit RFC-1034 (`^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$`).                                     | [122](https://google.aip.dev/122)                                   |
| **Standard methods**      | `Get`/`List`/`Create`/`Update`/`Delete` use the standard request/response shapes; RPC name = verb + singular resource; request message = RPC name + `Request`; `Get`/`Delete` return the resource / `Empty`; method signatures and `google.api.method_signature` set correctly. | [131](https://google.aip.dev/131)–[135](https://google.aip.dev/135) |
| **Custom methods**        | Non-standard RPCs follow the custom-method noun/verb pattern and are justified (a standard method would not fit).                                                                                                                                                               | [136](https://google.aip.dev/136)                                   |
| **Field behaviour**       | Required/optional/output-only/immutable expressed via `google.api.field_behavior`; presence handled per AIP.                                                                                                                                                                    | [203](https://google.aip.dev/203)                                   |
| **Enums**                 | First value is a sensible `*_UNSPECIFIED = 0`; values are `UPPER_SNAKE_CASE`.                                                                                                                                                                                                   | [126](https://google.aip.dev/126)                                   |
| **Versioning & packages** | Package ends in a version (`…v1`); file/package/option naming is consistent across the tree.                                                                                                                                                                                    | [215](https://google.aip.dev/215)                                   |
| **Deprecations**          | Deprecated elements set the `deprecated` option `true` and begin their comment with `Deprecated:` plus the replacement.                                                                                                                                                         | [192](https://google.aip.dev/192)                                   |
| **Errors & pagination**   | List methods paginate (`page_size`, `page_token`, `next_page_token`); error model is consistent.                                                                                                                                                                                | [158](https://google.aip.dev/158)                                   |

Browse https://google.aip.dev/general and the linked design AIPs when a case is not covered
above — treat the AIP site as the source of truth, and cite the AIP number in every finding.

### Pass 2 — Comment quality (clarity)

AIP-192 requires comments to exist; this pass checks they are actually **useful**. For every
**service** and **message** (and their methods/fields), judge whether the comment clearly
conveys:

- **What** the component is or does.
- **How** it is used — and where relevant: success/failure behaviour, idempotency, units, valid
  input formats and value ranges, default values, and presence conditions.

Flag a comment when it is **missing, empty, a restatement of the name** ("// The Book message"
on `Book`), or **too vague to act on**.

**When intent is unclear, ask the user — do not invent it.** Batch your questions: collect the
unclear items across all files and ask them together, grouped by file, e.g.:

> A few definitions need clarification before I can write good comments:
>
> - `BookService.ArchiveBook` — what does archiving do, and is it idempotent? What happens if the book is already archived?
> - `Book.shelf_code` — what format is this, and is it caller-supplied or system-generated?

Use the user's answers to draft clear, AIP-192-compliant comments. Propose the wording; apply it
only if the user agrees.

## Report

Produce a single review report:

1. **Summary** — files reviewed (with the define tree path), counts of findings by severity.
2. **Findings** — grouped by file, each with: location (`file:line` + element name), the issue, the
   AIP cited, severity (blocker / should-fix / nit), and a concrete suggested fix.
3. **Open questions** — the clarification questions from Pass 2, grouped by file.
4. **Next step** — once comments are clarified and findings addressed, the user reviews, commits,
   and runs Define against the pushed commit (proto review is the Define stage of DBD).

Reference `file:line` so the user can jump straight to each item.

## When not to use

| Need                                                   | Use instead                   |
| ------------------------------------------------------ | ----------------------------- |
| Onboarding / running the full Define→Build→Deploy loop | **getting-started**           |
| Adding a tool / LRO / agent feature to an ADK service  | the relevant **adk-go** skill |
| Implementing Go service logic against the contract     | Build stage, not this review  |

## Verification

- [ ] The define tree was resolved from `workstations.define_repos` (entry for `focus_neuron`),
      not guessed; the folder was confirmed before reading.
- [ ] **Every** `.proto` file under that folder was read in full and reviewed.
- [ ] Each AIP finding cites a specific AIP number and gives a concrete suggested fix.
- [ ] Every service and message was checked for a clear, useful comment (not just present).
- [ ] Where intent was unclear, the user was **asked** — nothing about behaviour was invented.
- [ ] Findings and open questions are reported per file with `file:line` references.
- [ ] No `.proto` file was edited unless the user asked for the fix to be applied.
