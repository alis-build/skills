# Derivation rules

This is the load-bearing reference. The Go templates under `templates/` are inert without the
values below — this is the authoritative spec for computing each template variable, by hand, from a
resource tree.

Render flow: for each output file, look up its template + variable-set in
[file-manifest.md](./file-manifest.md), compute the variables with the rules here, execute the
Go `text/template`, write the file, then **gofmt** (see §12). [worked-example.md](./worked-example.md)
shows the whole thing resolved for a real config.

---

## 1. Inputs

- **`package`** — e.g. `alis.os.processes.v1`. A leading `packages/` is stripped. This is the proto
  `package`, the `go.mod` module path, and the seed for all neuron/import derivation (§3).
- **`build_folder`** (a.k.a. `relativePath`) — where build files are rooted inside the neuron.
  Defaults to `"."`. Only a non-`.`/non-empty value changes Cloud Run / image naming (§10).
- **`BlockConfig`** — `language` (must be `LANGUAGE_GO`), `database` (must be `DATABASE_SPANNER`),
  and a recursive `resources` tree. Per-resource fields: `singular_name`, `plural_name`,
  `resource_id`, `collection_id`, `resource_id_regex`, `description`, `has_policies`,
  `user_provided_resource_id`, `enable_allow_missing_on_update`, `has_revisions`, `children`.

Refuse any config that is not Go + Spanner — no other combination is supported.

---

## 2. String helpers (reproduce exactly)

| Helper | Behaviour | Examples |
|---|---|---|
| `Title(s)` | Upper-case first byte only. | `author` → `Author` |
| `LowerTitle(s)` | Lower-case first byte only. | `Author` → `author` |
| `SnakeToCamel(s)` | Split on `_`; lower-case first segment's first rune, upper-case each later segment's first rune, keep the rest as-is; join. No `_` ⇒ just lower-cases the first rune. | `book` → `book`; `book_revision` → `bookRevision`; `Author` → `author` |
| `CamelToSnake(s)` | Insert `_` before each upper-case rune (except position 0 or right after `_`), then lower-case everything; existing `_` preserved. | `Authors` → `authors`; `bookChapters` → `book_chapters` |
| `PascalToUpperSnake(s)` | Upper-snake; keep acronyms unbroken — insert `_` when prev rune is lower-case, OR prev is upper-case and next is lower-case; preserve existing `_`. | `Author` → `AUTHOR`; `BookChapter` → `BOOK_CHAPTER`; `HTTPRequest` → `HTTP_REQUEST` |

Every `.go` output is gofmt'd (§12), so whitespace from your hand-render is normalized away — only
the *tokens* must be right.

---

## 3. Package → neuron + import path

Split the package (after stripping `packages/`) on `.`: `org . product . <neuron parts…>`.
For `marvel.sm.resources.v1`: org=`marvel`, product=`sm`, neuron parts=`[resources, v1]`.

| Variable | Rule | Example (`marvel.sm.resources.v1`, build_folder `.`) |
|---|---|---|
| `OrganisationId` | `parts[0]` | `marvel` |
| `ProductId` | `parts[1]` | `sm` |
| neuron parts | `parts[2:]` | `[resources, v1]` |
| `NeuronId` | neuron parts joined by `-` | `resources-v1` |
| `NeuronAlias` | `Title(neuronParts[0])` | `Resources` |
| `NeuronRelativeFilePath` | `org/product/<neuron parts joined by />` | `marvel/sm/resources/v1` |
| **`ImportPath`** (proto stubs) | `internal.<ProductId>.<PackagesDomain>/protobuf/<NeuronRelativeFilePath>` | `internal.sm.<PackagesDomain>/protobuf/marvel/sm/resources/v1` |

> **`PackagesDomain`, `ProductRegion`, `ProductGoogleProjectId` are NOT derivable from the package
> string** — they are product-specific. **Recover them from a sibling neuron** in the same build
> repo (see SKILL.md
> "Discover registry conventions"): read a sibling's `go.mod`/imports for
> `internal.<ProductId>.<PackagesDomain>/protobuf/...` and reuse `<ProductId>.<PackagesDomain>`,
> swapping in this neuron's `NeuronRelativeFilePath`. Read its `Dockerfile` for the registry values
> in §11. **Never invent `PackagesDomain`.**

The stubs package is always imported with alias **`pb`**.

---

## 4. Service mapping

- One gRPC service **per root resource**, named `<root PluralName>Service` (e.g. `AuthorsService`).
- **Every descendant** maps to its root's service — children never get their own service.
- Therefore: one `.proto` file, one service impl `.go`, and one `_test.go` **per root resource**;
  the file enumerates the whole subtree.
- `ServiceName` (used as a bare identifier) = `TrimSuffix(service, "Service")` = the root
  `PluralName` (e.g. `Authors`).

---

## 5. Per-resource scalars

These feed the proto template, the db/spanner files, etc. Compute for every resource in the tree
(and for each synthetic revision resource, §6.3):

| Variable | Rule | Author example |
|---|---|---|
| `ResourceName` | `singular_name` | `Author` |
| `ResourceNamePlural` | `plural_name` | `Authors` |
| `ResourceId` | `resource_id` | `author` |
| `CollectionId` | `collection_id` | `authors` |
| `CollectionIdSnakeCase` | `CamelToSnake(collection_id)` | `authors` |
| `ResourceNameUppercase` | `PascalToUpperSnake(singular_name)` | `AUTHOR` |
| `ResourceIdRegex` | `resource_id_regex` | `[a-z0-9-]{2,50}` |
| `HasParent` | resource has a parent (depth > 0) | `false` for roots |
| `ParentResourceName` / `ParentResourceId` / `ParentResourceNamePlural` / `ParentResourceNameUppercase` | the parent's singular / id / plural / `PascalToUpperSnake(parent singular)` | — |
| `HasPolicies` | `has_policies` | `true` |
| `UserProvidedId` | `user_provided_resource_id` | `false` |
| `AllowMissingOnUpdate` | `enable_allow_missing_on_update` | `false` |
| `HasRevisions` | `has_revisions` | `false` |

Resource flattening for the proto/methods/spanner files is **DFS pre-order**, passing the parent
down (so the parent fields are populated for children). The proto file for a service lists the
root then each descendant in pre-order.

---

## 5a. Service-file method assembly

The per-service file `<lower(plural)>.go` (`methods/service.go.tmpl.example`) renders a server
struct plus a flat list of method bodies. Each body is itself rendered from a template under
`methods/` and concatenated in this exact order:

1. **IAM methods — once per service, ONLY if ANY resource in the service has `has_policies`:**
   `get_iam_policy`, `set_iam_policy`, `test_iam_permissions`, `batch_test_iam_permissions`,
   `add_iam_bindings`, `remove_iam_bindings`.
2. **Per resource, DFS pre-order (root then descendants), the standard methods:**
   `create_resource`, `get_resource`, `update_resource`, `list_resources`, `delete_resource`,
   `undelete_resource`, `batch_create_resources`, `batch_get_resources`, `batch_update_resources`,
   `batch_delete_resources`, `batch_undelete_resources`, `stream_resources`.
3. **If the resource has `has_revisions`, after its standard methods:**
   `create_resource_revision`, `get_resource_revision`, `update_resource_revision`,
   `list_resource_revisions`, `delete_resource_revision`, `batch_create_resource_revisions`,
   `rollback_resource`.

Each method template consumes the per-resource scalars (§5) plus `Service` (e.g. `AuthorsService`),
`ImportAlias` (`pb`), and — for children — the parent fields. Within a method, the IAM/authorizer
blocks are gated by **that resource's own** `HasPolicies` (a no-policy resource still gets CRUD,
just without authorizer/policy code). The `service.go.tmpl` data is `{Service, ServiceName
(= plural), ServiceImportAlias=pb, Imports (pb + the 5 internal packages: database, db, namers,
regex, roles), Methods[]}`.

> **Proto vs Go asymmetry:** the proto service block declares the six IAM RPCs **unconditionally**
> for every service, but the Go impl only *implements* them when some resource has policies (the
> embedded `Unimplemented…Server` covers the rest). Replicate both behaviours.

## 6. Hierarchy for namers — the trickiest part

One namer file per resource: `internal/namers/<resource_id>_namer.go`. Each file defines **one
struct** that can extract this resource's name/id **and** every ancestor's name/id. Consumed by
`templates/internal/namers/namer.go.tmpl.example`.

### 6.1 The `RootResourceId` field is a misnomer — read carefully

For the namer of resource *R*, the template variable **`RootResourceId = SnakeToCamel(R's own
resource_id)`** — NOT the tree root. It is the **struct-name prefix**: the file for `book` defines
`bookNamer`; for `chapter`, `chapterNamer`; for `publisher_revision`, `publisherRevisionNamer`.
All ancestor entries inside that same file are overwritten to this same value, so every method
shares the one receiver type `*<RootResourceId>Namer`.

### 6.2 Algorithm (pseudocode)

```
processResource(res, ancestors, level):
    R = {
      ResourceName, ResourceNamePlural, ResourceId, ResourceIdRegex, CollectionId : from res
      MinParts        = 2 * (len(ancestors) + 1)         # collection+id per level
      HasParents      = len(ancestors) > 0
      RootResourceId  = SnakeToCamel(res.resource_id)    # struct prefix (see 6.1)
      Ancestors       = copy(ancestors)                  # ordered root → immediate parent
      IsAncestor      = false
    }
    for a in R.Ancestors: a.RootResourceId = SnakeToCamel(res.resource_id)   # share receiver type
    emit R   # one namer file

    parentEntry = {                       # how res appears AS an ancestor of its children
      (res scalars), Ancestors=nil, IsAncestor=true,
      MinParts        = R.MinParts,
      AncestorIdIndex = (R.MinParts / 2) + level,
    }
    for child in res.children:
        processResource(child, ancestors + [parentEntry], level+1)
    if res.has_revisions:
        processResource(<synthetic revision, §6.3>, ancestors + [parentEntry], level+1)
```

Useful identities (let `d` = a resource's depth, root = 0):
- `MinParts = 2*(d+1)` → root 2, child 4, grandchild 6.
- For an ancestor entry: `AncestorIdIndex = MinParts − 1` (equivalently `2d+1`).
- Namer method bodies (see the template): for the **leaf** (`IsAncestor=false`) `X()` returns
  `n.name` and `XId()` returns `n.parts[len(n.parts)-1]`; for an **ancestor**, `X()` returns
  `strings.Join(n.parts[:MinParts], "/")` and `XId()` returns `n.parts[AncestorIdIndex]`.

### 6.3 Synthetic revision resource

When `has_revisions`, a synthetic child-like resource is injected, processed at `level+1`:

| Field | Value |
|---|---|
| `singular_name` | `<Singular>Revision` (e.g. `PublisherRevision`) |
| `plural_name` | `<Plural>Revisions` (e.g. `PublisherRevisions`) |
| `resource_id` | `<resource_id>_revision` (e.g. `publisher_revision`) |
| `collection_id` | `revisions` |
| `resource_id_regex` | inherited from the parent |
| `has_policies` | `false` |

It produces its own namer file (`internal/namers/publisher_revision_namer.go`) and db file
(§ file-manifest). It does **not** itself have revisions or children.

---

## 7. `ParentsCollectionIds` (spanner only)

For `spanner.tf`, each resource also carries `ParentsCollectionIds` = the **ordered list of
`collection_id`s of all ancestors** (root → immediate parent), used to build the
`REGEXP_EXTRACT` that computes the foreign-key column. Roots get `nil`.

Trace for Author→Book→Chapter:
- Author: `ParentsCollectionIds = nil`
- Book: `["authors"]`
- Chapter: `["authors", "books"]`

The template renders the DDL as `r'^(<c0>/[^/]+)/(<c1>/[^/]+)…'` over that list (see
`templates/infra/spanner.tf.tmpl.example` lines using `.ParentsCollectionIds`). Each resource's
extra spanner data: `ResourceName`, `ResourceNamePlural`, `ResourceId`, `CollectionId`,
`HasParent`, `ParentResourceId`, `ParentResourceNamePlural`, `HasRevisions`, `Package` (= package),
`NeuronId`.

---

## 8. `regex.go` resource list

Flatten all resources DFS pre-order (parent-before-child, so the parent's Go regex var is defined
first). Each entry: `HasParent`, `ParentResourceName` (parent **singular**, used as the Go var name
of the parent regex), `ResourceName`, `CollectionId`, `ResourceId`, `ResourceIdRegex`,
`HasRevisions`. The template composes `join(<ParentResourceName or "">, "<CollectionId>",
<ResourceName>Id)` and adds `<ResourceName>Revision = join(<ResourceName>, "revisions", …)` when
`HasRevisions`.

---

## 9. `roles.go` resource list

Flatten all resources DFS pre-order. Each entry: `ImportAlias` (`pb`), `Package`, `Service`
(= the resource's service from §4), `ResourceName`, `ResourceNamePlural`,
`ResourceIdCamelCase` (= `resource_id`), `ResourceId`, `CollectionId`, `HasRevisions`. Imports the
stubs as `pb`. Produces `Open` (all create/list/stream/batch across every resource) plus
`<Resource>Admin/Owner/User/Viewer` per resource (revision RPCs added when `HasRevisions`).

---

## 10. Cloud Run naming

| Variable | `build_folder` is `""`/`.` | otherwise (`rel`) |
|---|---|---|
| `CloudRunName` | `NeuronAlias` (e.g. `Resources`) | `rel` with `/`→`_` |
| `CloudRunRelativePath` | `""` | `"-" + rel` with `/`→`-` |
| `ImageRelativePath` | `""` | `"/" + rel` |
| `NeuronId` | `resources-v1` | same |

The Cloud Run service `name` = `<NeuronId><CloudRunRelativePath>`; the image suffix uses
`<NeuronId><ImageRelativePath>`. Everything else in `cloudrun.tf` is fixed `var.ALIS_*` references.

---

## 11. Dockerfile registry values

`Dockerfile` needs three sibling-derived values (see §3 — recover from a sibling neuron's Dockerfile):

- `Regions` = `[<ProductRegion>]` → used in the `add-locations` line.
- `GoProxies` = `["https://<ProductRegion>-go.pkg.dev/<ProductGoogleProjectId>/protobuf-go-internal"]`
  → prepended to `ENV GOPROXY=…`.
- `GoNoSumDbs` = `["internal.<ProductId>.<PackagesDomain>/protobuf"]` → prepended to `ENV GONOSUMDB=…`.
- `BuildFolder` = `build_folder`.

The simplest faithful move is to copy the sibling's `Dockerfile` `GOPROXY`/`GONOSUMDB`/`add-locations`
lines verbatim (they already encode this product's region/project/domain) and only adjust
`BuildFolder` if relevant.

---

## 12. Formatting & ordering

- **gofmt is mandatory.** Run `gofmt -w` on every generated `.go` file (this absorbs hand-render
  whitespace differences and keeps output canonical). `go.mod`, `.proto`, and `.tf` are written
  as-is (proto is later normalized by buf/Define).
- **`go.mod` is not a template** — write exactly three lines: `module <package>`, an empty line,
  `go 1.24.3`.
- The static files in §file-manifest (`internal/database/*`, `infra/main.tf`, `infra/variables.tf`)
  have **no** template variables — copy them verbatim from the corresponding `*.example`.
- Internal package imports in service/db files use the package as module root, e.g.
  `<package>/internal/db`, `<package>/internal/namers`, etc.
