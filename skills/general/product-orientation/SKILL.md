---
name: product-orientation
description: >
  Use this skill when a developer wants to get orientated on an existing Alis Build product —
  "orientate me", "what is this product", "give me a tour", "what are all these neurons", "walk
  me through the services", "what does each microservice do", or "how is this product deployed".
  Use it before starting work on an unfamiliar product, when someone needs the lay of the land
  rather than a single answer. Produces a staged orientation: first a brief product summary,
  environment/deployment picture, compact neuron grouping, and a short "what matters next" prompt;
  then, only if requested, a fuller neuron table and selective deep dives. It is strictly
  read-only — it explores and explains, it never changes anything. Not for authoring or reviewing
  protos — use review-define. Not for the hands-on first-API onboarding walkthrough that creates
  a neuron and runs Define, Build, Deploy — use getting-started.
metadata:
  alis.context.version: "1"
  alis.context.requires: >-
    organisation organisation_id product product_id
    session.working_directory workstations focus_neuron_id
---
# Product Orientation

Help a developer who is new to an Alis Build **product** build an accurate mental model of it:
what the product is, what each **neuron** (microservice) is for, how the neurons relate, and how
the product is deployed. Keep an orienting tone — the goal is a map the developer can skim and
then dive into, not an exhaustive code read. Default to a **staged delivery**: first give a
high-level orientation that is quick to read, then ask whether the developer wants the detailed
overview or a deep dive into specific neurons.

This skill is **read-only**. Explore with the read-only MCP tools and the files on disk, then
**synthesise** a clear orientation. Never call a mutating tool (see Tools and sources). Never
edit, create, build, deploy, or push anything.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads this skill's
`alis.context.requires` manifest — a set of `Context` field paths (`alis.os.context.v1`) — so
the block carries exactly those resolved fields.
**When the block is present, its values are authoritative**: use the exact paths and resource
names verbatim, and do **not** scan folders, derive paths from the filesystem, or ask the user
to confirm a value that was already provided.

When the block is **absent or a value is missing** (for example, the skill was loaded outside
the Alis MCP), obtain each value using the "If absent" rule in the table below. The harness that
opens this flow runs **inside the product build repo**, so the working directory alone is enough
to recover the organisation and product. **Never invent environment IDs, project IDs, or commit
SHAs — read them from `ViewProduct` / the repo, or ask.**

### Context fields used by this skill

The path-valued fields live on `workstations` because they are absolute paths true on one machine
only; use the entry for the current workstation.

| Value | Context field | If absent, how to obtain it |
| ----- | ------------- | --------------------------- |
| Organisation (landing zone) | `organisation` / `organisation_id` | This is the `landing_zone_id` argument to `ViewProduct`. If absent, it is the `<landing-zone>` path segment of the build repo (`<root>/<landing-zone>/build/<product>`); else ask the user |
| Product | `product` / `product_id` | The `product_id` argument to `ViewProduct`. If absent, the last path segment of the build repo; else ask |
| Build repo root | `session.working_directory` / `workstations.build_repos` | The folder the harness is running in (the product build repo). Default `<root>/<landing-zone>/build/<product>`, root default `~/alis.build` |
| Define repo root | `workstations.define_repos` | The parent that holds this product's per-neuron define trees. Default `<root>/<landing-zone>/define/<org>/<product>`; confirm the folder before grepping |
| Default deep-dive neuron | `focus_neuron_id` | If present, offer this as the first deep-dive target unless the user explicitly asked for detail up front. If absent, pick a few likely key neurons yourself for follow-up suggestions or ask which ones interest the developer |

**Ids** are available directly as fields — do not parse resource names: `organisation_id` (the
landing-zone id) and `product_id` feed `ViewProduct(landing_zone_id, product_id)` straight in.

## Tools and sources

Use **only** read-only sources. The MCP tool names are `mcp__plugin_alis-build_api__*`.

**Read-only MCP tools (allowed):**

- `WhoAmI` — user id/email plus `build_profile` (harness / IDE / experience). Use it once to
  judge how much depth to give (a brand-new builder needs more explanation than an experienced one).
- `ViewProduct(landing_zone_id, product_id)` — **the central call.** Returns the product
  `display_name`, `description`, `project_id` (GCP project), `neurons[]` each
  `{id, version, status, logs_uri}`, and `environments[]` each
  `{id, display_name, project_id, status, deployments}` where `deployments` is a **map keyed by
  neuron id** of `{id, version, status, logs_uri}`. One call gives the full neuron list, the
  environments, and which neuron version is deployed where. Call it once and reuse the result.
- `ListDefines` — recent definition versions and per-language generated-package states
  (Go / JS / Python / Spanner protobundles). Use for the DBD-as-applied-here section.
- `ListBuilds(neuron)` / `ListDeploys(neuron, environment)` — recent build/deploy history, states,
  and log URLs. The `environment` id **must** come from `ViewProduct` — never invent one. Use only
  in the deep dive or on request, not for every neuron.
- `ListBlockInstalls` — which reusable **blocks** are installed in the product/neurons.
- `ViewBuildLogs` / `ViewDeployLogs` — drill into a specific build/deploy only when asked.

**Never call any mutating tool:** `CreateNeuron`, `PrepareLocalEnvironment`, `RunDefine` /
`RunBuild` / `RunDeploy`, `InstallBlock*`, the git tools (`CloneDefine/Product`,
`PullDefine/Product`, `PushDefine/Product`), `SpecIt`, or `RequestSkill`. Orientation observes;
it does not act.

**On-disk sources** (the harness runs inside the build repo `<root>/<landing-zone>/build/<product>/`):

- `.alis/agents/AGENTS.md` — the canonical explainer of the **two-repo model** (build repo =
  implementation, one git repo per product; define repo = protos, one repo per org). **Read this
  first.** It also names the build and define repo paths for this machine and links any attached
  product/build spec.
- Each neuron is a folder `<neuron-path>/<vN>/` — the version leaf is `v1`, `v2`, …, and the path
  is **one or more segments**: usually one (`cli/v1`, `iam/v2`), sometimes nested
  (`build/agent/v1`, `build/activity/v1`). It contains a Dockerfile (or several, in subfolders
  like `bff/` and `tui/`), a Go module, and an `infra/` Terraform folder. The neuron's **id** (as
  used by tooling, images, and `ViewProduct`) is that path with `/` → `-`: `cli/v1` → `cli-v1`,
  `build/agent/v1` → `build-agent-v1`. See Naming conventions for the full mapping.
- The authoritative one-line role of a neuron is the **leading comment on the `service` (or its
  `rpc`s) in its proto** at `<define-root>/<neuron-path>/<vN>/*.proto` (e.g. `// The alis cli
  backend for frontend`). Proto `import` lines reveal the neuron-to-neuron dependency graph.
- `infra/*.tf` reveal deployment: `cloudrun.tf` (the Cloud Run service — image path
  `…/neurons/<neuron-id>/<subpath>:<sha>`, container port, invoker IAM, service account),
  `variables.tf` (the injected `ALIS_*` vars naming project/region/Spanner), `spanner.tf`
  (Spanner tables with PROTO-typed columns linking back to a proto message), `pubsub.tf` (event
  topics/subscriptions), `loadbalancing.tf`, `storage.tf`, and so on.
- `.alis/.env` holds project IDs / region (`ALIS_OS_PROJECT`, `ALIS_PRODUCT_REGION`,
  `ALIS_MANAGED_SPANNER_*`, …) **but also live secrets/tokens** (`*_SK`, `*_TOKEN`, `*_SECRET`,
  `*_KEY`, `*APIKEY`, credentials). See "Surfacing project/region facts" — surface only non-secret
  identifiers and **never print a secret value**.

## Scale: a staged approach

A product can have **dozens** of neurons (the `os` product has ~50). Reading every proto and every
`infra/` folder in full is expensive and overwhelming, and it buries the developer. Work in stages
and be explicit about which is which:

1. **Stage 1: high-level orientation — default response.** Build a compact product map that is
   fast to produce and easy to skim: product purpose, environments, total neuron count, broad
   neuron groups/themes, notable deployment capabilities, and DBD shape. Do **not** include the
   full neuron table or deep dives in the first response unless the user explicitly asked for
   detail up front.
2. **Stage 2: detailed overview — only on request.** If the developer asks for more detail, build
   one **neuron overview table** covering **all** neurons. Get each neuron's role from a **single
   grep** across all proto files, its latest version + status from the one `ViewProduct` result,
   the environments it is deployed to from `ViewProduct` `environments[].deployments`, and its
   deployment capabilities from **which `.tf` files exist** (a single `find` — do not read them).
   This pass is **exhaustive**: every neuron gets a row.
3. **Stage 3: selective deep dive — only on request or clear intent.** Dive deep on just the key
   neurons — the `focus_neuron_id` if present and relevant, the few the developer names, or 3–5
   you judge central (e.g. a public-facing BFF, the data owners, the dependency hubs). For each,
   open its proto service, its `cloudrun.tf`, note Spanner/Pub/Sub presence and its proto `import`
   dependencies.

**No silent truncation.** In Stage 1, state that the first response is intentionally high-level and
ask whether the developer wants the full neuron table, a deep dive into selected neurons, or both.
In Stage 2, state the total neuron count and confirm the overview covers all of them. In Stage 3,
say plainly which neurons you deep-dived and which you did not (e.g. "Deep dive: cli, accounts,
build (3 of 48); the rest are summarised in the table above — ask to drill into any of them").

## Efficiency rules

- **One grep for all roles.** Extract every service's leading comment in a single pass instead of
  reading ~50 files:

  ```bash
  grep -rn -B2 --include='*.proto' -E '^service ' <define-root>/
  ```

  Recurse the whole define subtree — do **not** hard-code `*/v1/`, because neurons nest and
  versions vary. For each match, the neuron is the matched file's directory **relative to
  `<define-root>`** — i.e. `<neuron-path>/<vN>` (`build/agent/v1`), whose id is that path with
  `/` → `-` (`build-agent-v1`). Its role is the contiguous `//` comment line(s) immediately above
  the `service` (take the first sentence). A neuron may declare
  several services across several proto files — pick the primary one (the proto named after the
  neuron, else the first) for the table and note "N services" if there are more. If a neuron has no
  proto (define repo not cloned, or an infra-only neuron), fall back to the folder name and mark
  the role as "(no proto — folder name)".
- **Detect capabilities by file existence, not by reading.** One pass over the build repo:

  ```bash
  find <build-root> -type f -path '*/infra/*.tf'
  ```

  Match `infra/` at **any depth** — `*/v1/infra` would miss nested neurons (`build/agent/v1`) and
  non-`v1` versions (`iam/v2`). The neuron for each hit is the path between `<build-root>` and
  `/infra/`. Map filenames to capability tags (presence only):

  | File | Capability |
  | ---- | ---------- |
  | `cloudrun.tf` | Cloud Run service (HTTP) |
  | `jobs.tf` | Cloud Run job (batch) |
  | `spanner.tf` / `lro_spanner.tf` | Spanner tables (proto-typed columns) |
  | `pubsub.tf` | Pub/Sub topics/subscriptions |
  | `events.tf` | Eventarc triggers |
  | `tasks.tf` | Cloud Tasks queues |
  | `scheduler.tf` | Cloud Scheduler (cron) |
  | `storage.tf` | Cloud Storage buckets |
  | `bigquery.tf` / `bigtable.tf` | Analytics / wide-column storage |
  | `loadbalancing.tf` | External load balancer (public ingress / custom domain) |
  | `iap.tf` | Identity-Aware Proxy |
  | `firebase.tf` | Firebase |

  `main.tf` and `variables.tf` are present almost everywhere (module wiring + injected `ALIS_*`
  vars) — they are not capabilities, don't tag them.
- **Reuse the single `ViewProduct` result** for every version/status/deployment lookup; do not call
  `ListBuilds`/`ListDeploys` per neuron in the fast pass.

## Procedure

1. **Read `.alis/agents/AGENTS.md` first.** It establishes the two-repo model and gives the exact
   build-repo and define-repo paths for this machine. Use those as `<build-root>` and
   `<define-root>` (prefer the runtime-context `workstations` values when present).
2. **`WhoAmI`** once — note the build profile so you can pitch the depth (more teaching for a
   first-timer, terser for an experienced builder).
3. **`ViewProduct(landing_zone_id = organisation_id, product_id = product_id)`** once. Capture
   `display_name`, `description`, `project_id`, the `neurons[]` list (id, version, status), and
   `environments[]` (id, display_name, project_id, status, and the `deployments` map). This is the
   spine of the orientation.
4. **Stage 1 high-level orientation.** Use the `ViewProduct` result, `.alis/agents/AGENTS.md`,
   and lightweight filesystem facts to produce the first response:
   - Product name, description, project, and environment count/status.
   - Total neuron count and a compact grouping by clear prefixes/themes if visible from IDs and
     folders (for example `build-*`, `iam-*`, `billing-*`); do not force themes if the IDs are
     already clearer alphabetically.
   - A short deployment picture: which environments exist, whether deployments are broad or sparse,
     and any obvious production-only/no-DEV shape.
   - A short DBD map: where Define, Build, and Deploy live for this product.
   - A concise prompt asking what detail the developer wants next.
5. **Only when the developer asks for a detailed overview: build the full neuron table** (every
   neuron). For each neuron in `neurons[]`:
   - **Role** — from the single proto grep (step in Efficiency rules).
   - **Latest version · status** — from `ViewProduct` `neurons[]`.
   - **Deployed in** — the `environments[].display_name`s whose `deployments` map contains this
     neuron id; note the deployed version when it differs from the latest.
   - **Capabilities** — tags from the single infra `find`.
6. **Only when the developer asks for a deep dive: deep dive** on the selected handful only (see
   Scale). For each: open the proto service for the real role and method surface; read `import`
   lines for neuron-to-neuron dependencies (imports of other
   `alis/<product>/<neuron-path>/<vN>/*.proto`); open `cloudrun.tf` for the image path
   (`…/neurons/<neuron-id>/<subpath>:<sha>`), `container_port`, invoker IAM (`member = "allUsers"`
   ⇒ public; otherwise private/internal), and `service_account`; note Spanner tables / PROTO-typed
   columns from `spanner.tf` and topics from `pubsub.tf`; note multiple Dockerfiles (e.g. `bff/`,
   `tui/`) as separate containers the neuron ships.
7. **Deployment & environments.** Summarise `environments[]` (id, display_name, GCP project_id,
   status) and, from the `deployments` maps, which neurons run where and at what version. Flag a
   product with **no DEV environment** (Production-only) if that is the case. In Stage 1, keep this
   short; expand it in Stage 2 only if the developer asks for the detailed deployment picture.
8. **DBD as applied here.** In one short section, tie it to this product: protos live in
   `<define-root>` (Define), implementation + Dockerfiles + `infra/` live in `<build-root>` (Build,
   Deploy). Use `ListDefines` to mention the latest definition version and which language packages
   this product generates, and `ListBlockInstalls` to mention installed blocks when producing the
   detailed overview. In Stage 1, keep it to the shape of the loop, not a how-to (point at
   **getting-started** for the hands-on walkthrough).
9. **Surfacing project/region facts.** Prefer `ViewProduct` for `project_id` and per-environment
   projects. You may additionally read `<build-root>/.alis/.env` to surface **region** and
   **Spanner** identifiers, but surface **only** non-secret identifier keys — e.g. `ALIS_OS_PROJECT`,
   `ALIS_OS_PRODUCT_PROJECT`, `ALIS_OS_ORG_PROJECT`, `ALIS_PRODUCT_REGION`, `ALIS_REGION`,
   `ALIS_MANAGED_SPANNER_INSTANCE`, `ALIS_MANAGED_SPANNER_DB`, `ALIS_PROJECT_NR`. **Never print** the
   value of any key whose name contains or ends with `KEY`, `TOKEN`, `SECRET`, `_SK`, `_PK`,
   `PASSWORD`, `APIKEY`, or `CREDENTIALS` (e.g. `STRIPE_SK`, `NPM_TOKEN`, `GITHUB_CLIENT_SECRET`,
   `SG_API_KEY`, `LINEAR_API_KEY`). If unsure whether a key is sensitive, omit it.

## Naming conventions (state these for the developer)

A neuron is identified by its **path inside the product**, from the product folder down to the
version leaf (`vN`). That path is **one or more segments** — most neurons are a single segment
(`cli/v1`, `iam/v2`), but some nest (`build/agent/v1`, `build/activity/v1`). The **same path**
drives every other identifier — given any one form you can derive the rest:

| Form | Rule | `cli/v1` | `build/agent/v1` | `iam/v2` |
| ---- | ---- | -------- | ---------------- | -------- |
| Build folder | `<build-root>/<neuron-path>/<vN>` | `…/build/<product>/cli/v1` | `…/build/<product>/build/agent/v1` | `…/build/<product>/iam/v2` |
| Define folder | `<define-root>/<neuron-path>/<vN>` | `…/define/<org>/<product>/cli/v1` | `…/define/<org>/<product>/build/agent/v1` | `…/define/<org>/<product>/iam/v2` |
| Neuron **id** (tooling, images, `ViewProduct`) | path, `/` → `-` | `cli-v1` | `build-agent-v1` | `iam-v2` |
| Proto **package** | `<org>.<product>.` + path, `/` → `.` | `alis.os.cli.v1` | `alis.os.build.agent.v1` | `alis.os.iam.v2` |
| Generated **Go module** | `internal.<product>.alis.services/protobuf/<org>/<product>/<neuron-path>/<vN>` | `internal.os.alis.services/protobuf/alis/os/cli/v1` | …`/alis/os/build/agent/v1` | …`/alis/os/iam/v2` |
| Container **image** | `<region>-docker.pkg.dev/<project>/neurons/<neuron-id>/<subpath>:<sha>` | `…/neurons/cli-v1/<subpath>:<sha>` | `…/neurons/build-agent-v1/…` | `…/neurons/iam-v2/…` |

Two asymmetries to remember:

- The **build repo is per product** — `<build-root> = <root>/<org>/build/<product>` — but the
  **define repo is per org with a nested `<org>` segment** — `<define-root> =
  <root>/<org>/define/<org>/<product>`. Below each root the neuron path is identical.
- A **`ViewProduct` neuron id** maps back to its folder by replacing every `-` with `/` (segment
  names never contain hyphens): `build-agent-v1` → `build/agent/v1`. The version is the `vN` leaf
  — never assume `v1`.

## Output — staged orientation

For the first response, end with a short, skimmable orientation the developer can read quickly:

1. **Product summary** — `display_name`, `description`, GCP `project_id`, and the environments
   (id, display_name, project, status).
2. **High-level neuron map** — total neuron count and grouped themes/prefixes, with a few examples
   per group. Do not include the exhaustive table in the first response unless explicitly requested.
3. **Deployment picture** — environments and broad deployment shape, plus any important caveat
   such as no DEV environment.
4. **How DBD works here** — the short, product-specific loop from step 8.
5. **What to look at next** — 2–4 concrete next options, phrased as choices the developer can make:
   full neuron table, detailed deployment overview, deep dive into named neurons, or hands-on
   **getting-started** / proto **review-define**.
6. **Ask before detail** — close with one concise question asking whether they want more detail.
   Good shape: "Want the detailed overview next: full neuron table, deployment details, or a deep
   dive into specific neurons?"

When the developer asks for the **detailed overview**, produce:

1. **Neuron overview (all N neurons)** — the table from the fast pass, **grouped sensibly** (by a
   discernible theme/prefix if one exists, e.g. accounts/billing vs build/deploy vs ai; otherwise
   alphabetical). Columns: **Neuron | Role | Version · status | Deployed in | Capabilities**. State
   the total count and that the table is complete.
2. **Expanded deployment & DBD details** — environment deployment versions, latest definition
   version/package states, and installed blocks if available.
3. **Follow-up question** — ask whether they want a deep dive into specific neurons.

When the developer asks for a **deep dive**, produce:

1. **Deep dive** — the selected handful, each with its real role, key dependencies, deployment
   shape (public/private, port, image), and data (Spanner/Pub/Sub).
2. **Coverage note** — state explicitly which neurons were deep-dived vs only summarised; no silent
   truncation.

## Verification

- [ ] `.alis/agents/AGENTS.md` was read first; the two-repo model is reflected and the real
      build/define repo paths were used.
- [ ] `ViewProduct` was called once with `landing_zone_id`/`product_id` from context (or recovered
      from the build-repo path), and the product summary came from it — no invented IDs.
- [ ] The first response was high-level by default: product summary, total neuron count/grouping,
      environment picture, DBD map, and a clear question asking whether more detail is wanted.
- [ ] The exhaustive neuron overview table was produced only when requested; when produced, it
      covers **all** neurons (count stated), built from a **single** proto grep and a **single**
      infra `find` — not per-neuron full reads.
- [ ] When a detailed table was produced, each neuron's role came from its proto service leading
      comment (folder-name fallback noted where no proto was available).
- [ ] "Deployed in" / versions came from `ViewProduct` `environments[].deployments` — not invented.
- [ ] Capabilities came from which `infra/*.tf` files exist; those `.tf` files were not all read.
- [ ] The deep dive was produced only when requested or clearly intended, limited to a handful
      (count stated); what was sampled vs skipped was stated explicitly — nothing was silently
      truncated.
- [ ] Only non-secret `ALIS_*` project/region/Spanner identifiers were surfaced; no token, key, or
      secret value was printed; project/environment facts were preferred from `ViewProduct`.
- [ ] No mutating tool was called (no Create/Prepare/Run*/Install*/Clone*/Pull*/Push*/SpecIt/
      RequestSkill); the whole session was read-only.
- [ ] The output ends with a staged, skimmable orientation: first a high-level summary and request
      for the developer's preferred next level of detail; later responses add the full table or
      deep dives only when requested.
- [ ] If a runtime-context block was present, its org/product/paths were used verbatim and nothing
      was re-derived or re-asked.
