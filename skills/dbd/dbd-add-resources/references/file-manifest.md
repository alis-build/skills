# File manifest

Every file this skill generates, its source template, what drives it, and its exact name. Several
filenames are **counter-intuitive** and are the top source of silent divergence (see ⚠️ notes).
Compute variables with [derivation-rules.md](./derivation-rules.md); render the `*.example`
template; write to the path.

## Three destinations

| Bucket | Goes to | Notes |
|---|---|---|
| **Proto** | the **define** tree (package folder under `workstations.define_repos`) | the API contract |
| **Build** | the **build** tree root (`session.working_directory`, ≈ `workstations.build_repos`) | Go service + `internal/*` |
| **Infra** | `<build>/infra/` | Terraform |

`R` = once per resource (recursive, incl. the synthetic revision resource). `S` = once per service
(= once per **root** resource). `1` = exactly once for the whole block.

## Proto files (→ define tree)

| Output path | Template | Scope | Condition | Key vars |
|---|---|---|---|---|
| `<root resource_id>.proto` ⚠️ singular root id (e.g. `author.proto`, `publisher.proto`) | `protos/service.proto.tmpl.example` | S | always | `Service`, `Package`, `Resources[]` (whole subtree, pre-order) |

## Build files (→ build tree)

| Output path | Template | Scope | Condition | Key vars |
|---|---|---|---|---|
| `go.mod` | — **not a template**; 3 hardcoded lines | 1 | always | `module <package>` / `` / `go 1.24.3` |
| `server.go` | `server.go.tmpl.example` | 1 | always | `Imports` (`pb`), `ImplementedServices[]` (one per root: `{Service, ImportAlias=pb}`) |
| `Dockerfile` | `Dockerfile.tmpl.example` | 1 | always | `BuildFolder`, `Regions`, `GoProxies`, `GoNoSumDbs` (sibling-derived, §11) |
| `iam.go` | `iam.go.tmpl.example` | 1 | always | `Package`, `Resources[]` (`ResourceName` only) |
| `<lower(PluralName)>.go` ⚠️ lowercased **plural** (e.g. `authors.go`, `publishers.go`) | `methods/service.go.tmpl.example` | S | always | `Service`, `ServiceName`, `ServiceImportAlias=pb`, `Imports[]` (pb + 5 internal pkgs), `Methods[]` |
| `<lower(PluralName)>_test.go` (e.g. `authors_test.go`) | `methods/service_test.go.tmpl.example` | S | always | per-service test data |
| `internal/database/database.go` | `internal/database/database.go.tmpl.example` | 1 | always | **static** — no vars; copy verbatim |
| `internal/database/stream.go` | `internal/database/stream.go.tmpl.example` | 1 | always | **static** — copy verbatim |
| `internal/database/utils.go` | `internal/database/utils.go.tmpl.example` | 1 | always | **static** — copy verbatim |
| `internal/db/db.go` | `internal/db/db.go.tmpl.example` | 1 | always | `Imports`, `Resources[]` (all: `ResourceName(Plural)`, `HasRevisions`, `ImportAlias=pb`), `NeuronId` |
| `internal/db/spanner.go` | `internal/db/spanner.go.tmpl.example` | 1 | always | `Imports` (pb + `database`) — `SpannerResourceRow` impl |
| `internal/db/<lower(SingularName)>.go` ⚠️ lowercased **singular**, not snake (e.g. `book.go`) | `internal/db/resource.go.tmpl.example` | R | always | `CollectionId`, `ResourceName`, `ResourceNamePlural`, `ImportAlias=pb`, `Imports` |
| `internal/db/<lower(SingularName)>_revision.go` | `internal/db/resource_revision.go.tmpl.example` | R | if `has_revisions` | as above |
| `internal/namers/<resource_id>_namer.go` (e.g. `book_namer.go`, `publisher_revision_namer.go`) | `internal/namers/namer.go.tmpl.example` | R (+ revision pseudo-resource) | always | full hierarchy data (§6): `RootResourceId`, `MinParts`, `Ancestors[]`, `AncestorIdIndex`, … |
| `internal/regex/regex.go` | `internal/regex/regex.go.tmpl.example` | 1 | always | `Resources[]` (pre-order, §8) |
| `internal/roles/roles.go` | `internal/roles/roles.go.tmpl.example` | 1 | always | `Imports` (pb), `Resources[]` (§9) |

## Infra files (→ `<build>/infra/`)

| Output path | Template | Scope | Condition | Key vars |
|---|---|---|---|---|
| `infra/main.tf` | `infra/main.tf.tmpl.example` | 1 | always | **static** — copy verbatim |
| `infra/variables.tf` | `infra/variables.tf.tmpl.example` | 1 | always | **static** — copy verbatim |
| `infra/cloudrun.tf` | `infra/cloudrun.tf.tmpl.example` | 1 | always | `CloudRunName`, `CloudRunRelativePath`, `ImageRelativePath`, `NeuronId` (§10) |
| `infra/spanner.tf` | `infra/spanner.tf.tmpl.example` | 1 | always | `Resources[]` with `ParentsCollectionIds` (§7), `NeuronId` |

## ⚠️ Naming pitfalls (memorise these)

- **proto = singular** root `resource_id` (`author.proto`); **service impl = lowercased plural**
  (`authors.go`); **db file = lowercased singular** (`book.go`). Three different conventions for
  the same resource.
- The db filename is the **lower-cased** `SingularName`, **not** snake_case — a `BookChapter`
  resource → `bookchapter.go`, not `book_chapter.go`.
- The namer filename uses `resource_id` (`book_namer.go`), but the struct inside is
  `SnakeToCamel(resource_id)` + `Namer` (`bookNamer`) — see derivation §6.1.
- Revisions add **both** `internal/db/<lower-singular>_revision.go` **and**
  `internal/namers/<resource_id>_revision_namer.go`, plus revision blocks in `regex.go`, `roles.go`,
  the `.proto`, and `spanner.tf`.

## File counts for a config with `n` resources (incl. revisions as resources)

Proto: one per root. Build: `go.mod` + `server.go` + `Dockerfile` + `iam.go` + 3×`internal/database`
+ `db.go` + `spanner.go` + `regex.go` + `roles.go` (= 11 fixed) + (impl+test) per root + one
`internal/db/<res>.go` per resource (+ `_revision.go`) + one `internal/namers/<res>_namer.go` per
resource (incl. revision pseudo). Infra: always 4.
