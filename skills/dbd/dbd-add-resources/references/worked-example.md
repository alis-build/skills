# Worked example (golden run)

A complete golden run that exercises every hard case in one config: 3-level nesting, two roots
(⇒ two services), policies, and revisions.

Use it to calibrate: confirm your resolved variables and your rendering of the four highest-risk
files (proto, namer, `spanner.tf`, db resource file) match these before trusting your output on a
different config.

## Input

- `package` = `packages/marvel.sm.resources.v1`  ·  `build_folder` = `""`
- `language` = `LANGUAGE_GO`  ·  `database` = `DATABASE_SPANNER`
- Resources:
  - **Author** (`author`/`authors`, has_policies) → **Book** (`book`/`books`, has_policies) →
    **Chapter** (`chapter`/`chapters`, has_policies)
  - **Publisher** (`publisher`/`publishers`, has_policies, **has_revisions**)
  - all `resource_id_regex` = `[a-z0-9-]{2,50}`, all `user_provided_resource_id` = false.

## Resolved neuron / import values (derivation §3)

| Value | Resolved |
|---|---|
| org / product | `marvel` / `sm` |
| `NeuronId` | `resources-v1` |
| `NeuronAlias` | `Resources` |
| `NeuronRelativeFilePath` | `marvel/sm/resources/v1` |
| `PackagesDomain` (⚠️ sibling-derived, not from package) | e.g. `marvel.build` |
| `ImportPath` (alias `pb`) | `internal.sm.marvel.build/protobuf/marvel/sm/resources/v1` |
| proto `package` / `go.mod` module | `marvel.sm.resources.v1` |

## Service map (derivation §4)

| Resource | Service |
|---|---|
| Author, Book, Chapter | `AuthorsService` |
| Publisher (+ revisions) | `PublishersService` |

⇒ two protos (`author.proto`, `publisher.proto`), two impls (`authors.go`, `publishers.go`),
two tests (`authors_test.go`, `publishers_test.go`).

## Full file list (31 files)

```
# define tree
author.proto                 publisher.proto
# build tree (root)
go.mod  server.go  Dockerfile  iam.go
authors.go  authors_test.go  publishers.go  publishers_test.go
internal/database/database.go  internal/database/stream.go  internal/database/utils.go
internal/db/db.go  internal/db/spanner.go
internal/db/author.go  internal/db/book.go  internal/db/chapter.go  internal/db/publisher.go
internal/db/publisher_revision.go          # note: lowercased singular + _revision
internal/namers/author_namer.go  internal/namers/book_namer.go  internal/namers/chapter_namer.go
internal/namers/publisher_namer.go  internal/namers/publisher_revision_namer.go
internal/regex/regex.go  internal/roles/roles.go
# infra
infra/main.tf  infra/variables.tf  infra/cloudrun.tf  infra/spanner.tf
```

## Per-resource scalars (derivation §5)

| | ResourceName | Plural | Id | Collection | Uppercase | HasParent | Parent(Name/Id) | HasRevisions |
|---|---|---|---|---|---|---|---|---|
| Author | Author | Authors | author | authors | AUTHOR | false | — | false |
| Book | Book | Books | book | books | BOOK | true | Author / author | false |
| Chapter | Chapter | Chapters | chapter | chapters | CHAPTER | true | Book / book | false |
| Publisher | Publisher | Publishers | publisher | publishers | PUBLISHER | false | — | **true** |

## Namer hierarchy (derivation §6)

| Namer file | Struct | Ctor / MinParts | Ancestors (MinParts, AncestorIdIndex) |
|---|---|---|---|
| `author_namer.go` | `authorNamer` | `Author` / 2 | — |
| `book_namer.go` | `bookNamer` | `Book` / 4 | Author (2, idx 1) |
| `chapter_namer.go` | `chapterNamer` | `Chapter` / 6 | Author (2, idx 1), Book (4, idx 3) |
| `publisher_namer.go` | `publisherNamer` | `Publisher` / 2 | — |
| `publisher_revision_namer.go` | `publisherRevisionNamer` | `PublisherRevision` / 4 | Publisher (2, idx 1) |

### Rendered `internal/namers/chapter_namer.go` (the hardest file — gofmt'd)

```go
package namers

import (
	"fmt"
	"strings"
)

type chapterNamer struct {
	name  string
	parts []string
}

// Returns new chapter namer with method to extract the names and ids of the chapter and its parents.
func Chapter(name string) (*chapterNamer, error) {
	parts := strings.Split(name, "/")
	if len(parts) < 6 {
		return nil, fmt.Errorf("invalid chapter name: %s", name)
	}
	return &chapterNamer{
		name:  name,
		parts: parts,
	}, nil
}

// Returns the full name of the chapter
func (n *chapterNamer) Chapter() string {
	return n.name
}

// Returns the id of the chapter
func (n *chapterNamer) Id() string {
	return n.parts[len(n.parts)-1]
}

// Returns the full name of the author
func (n *chapterNamer) Author() string {
	return strings.Join(n.parts[:2], "/")
}

// Returns the id of the author
func (n *chapterNamer) AuthorId() string {
	return n.parts[1]
}

// Returns the full name of the book
func (n *chapterNamer) Book() string {
	return strings.Join(n.parts[:4], "/")
}

// Returns the id of the book
func (n *chapterNamer) BookId() string {
	return n.parts[3]
}
```

Sanity check against `authors/a1/books/b1/chapters/c1`: `parts[:2]`=`authors/a1` (Author),
`parts[1]`=`a1`, `parts[:4]`=`authors/a1/books/b1` (Book), `parts[3]`=`b1`, `parts[len-1]`=`c1`.

## Proto — key fragments (from `publisher.proto` + the parent/child delta)

The full file is produced by `protos/service.proto.tmpl.example`; these are the variable parts to
get right.

**Service RPC block** (`Service` = `PublishersService`; revision RPCs because `has_revisions`):

```proto
service PublishersService {
    rpc GetIamPolicy(google.iam.v1.GetIamPolicyRequest) returns (google.iam.v1.Policy) {}
    // … SetIamPolicy, TestIamPermissions, BatchTestIamPermissions, AddIamBindings, RemoveIamBindings …
    rpc CreatePublisher(CreatePublisherRequest) returns (Publisher) {}
    rpc GetPublisher(GetPublisherRequest) returns (Publisher) {}
    rpc UpdatePublisher(UpdatePublisherRequest) returns (Publisher) {}
    rpc ListPublishers(ListPublishersRequest) returns (ListPublishersResponse) {}
    rpc DeletePublisher(DeletePublisherRequest) returns (Publisher) {}
    rpc UndeletePublisher(UndeletePublisherRequest) returns (Publisher) {}
    rpc BatchCreatePublishers(BatchCreatePublishersRequest) returns (BatchCreatePublishersResponse) {}
    // … BatchGet/Update/Delete/Undelete, StreamPublishers …
    // because has_revisions:
    rpc CreatePublisherRevision(CreatePublisherRevisionRequest) returns (PublisherRevision) {}
    rpc GetPublisherRevision(GetPublisherRevisionRequest) returns (PublisherRevision) {}
    rpc UpdatePublisherRevision(UpdatePublisherRevisionRequest) returns (PublisherRevision) {}
    rpc ListPublisherRevisions(ListPublisherRevisionsRequest) returns (ListPublisherRevisionsResponse) {}
    rpc DeletePublisherRevision(DeletePublisherRevisionRequest) returns (google.protobuf.Empty) {}
    rpc BatchCreatePublisherRevisions(BatchCreatePublisherRevisionsRequest) returns (BatchCreatePublisherRevisionsResponse) {}
    rpc RollbackPublisher(RollbackPublisherRequest) returns (PublisherRevision) {}
}
```

**Resource + revision messages** (note the field numbers — `name=1`, `etag=97`, times `98/99/100`):

```proto
message Publisher {
    string name = 1;
    // TODO: Add more fields as needed.
    string etag = 97;
    google.protobuf.Timestamp create_time = 98;
    google.protobuf.Timestamp update_time = 99;
    google.protobuf.Timestamp delete_time = 100;
}
message PublisherRevision {            // because has_revisions
    string name = 1;
    Publisher snapshot = 2;
    google.protobuf.Timestamp create_time = 98;
    google.protobuf.Timestamp update_time = 99;
}
```

**Root vs child delta** — the `parent` field is the only structural difference. Root (`Publisher`,
no parent) **reserves** field 1; child (`Book`, in `author.proto`) uses it:

```proto
// CreatePublisherRequest (ROOT)            // CreateBookRequest (CHILD)
message CreatePublisherRequest {            message CreateBookRequest {
    reserved 1;                                 string parent = 1;       // parent author
    Publisher publisher = 2;                    Book book = 2;
}                                           }
// (if user_provided_resource_id: also `string <id>_id = 3;`)
```

**List response uses `CollectionIdSnakeCase`** for the repeated field name:

```proto
message ListPublishersResponse {
    repeated Publisher publishers = 1;     // = CamelToSnake(collection_id)
    string next_page_token = 2;
}
```

**View enum** uses `ResourceNameUppercase`:

```proto
enum PublisherView {
    PUBLISHER_VIEW_UNSPECIFIED = 0;
    PUBLISHER_VIEW_BASIC = 1;
    PUBLISHER_VIEW_FULL = 2;
}
// + PublisherRevisionView (…_REVISION_VIEW_*) because has_revisions
```

## `infra/spanner.tf` — Chapter table + Publisher revision (the gnarly bits)

Chapter has two ancestors, so `ParentsCollectionIds = ["authors","books"]` ⇒ a two-group regex; the
FK column is named after `ParentResourceId` (`book`) and references the parent's plural table:

```hcl
resource "alis_google_spanner_table" "Chapters" {
  project         = var.ALIS_MANAGED_SPANNER_PROJECT
  instance        = var.ALIS_MANAGED_SPANNER_INSTANCE
  database        = var.ALIS_MANAGED_SPANNER_DB
  name            = "${replace(var.ALIS_OS_PROJECT, "-", "_")}_${replace("resources-v1", "-", "_")}_Chapters"
  prevent_destroy = true
  schema = {
    columns = [
      { name = "key", type = "STRING", is_primary_key = true, required = true },
      { name = "Chapter", type = "PROTO", proto_package = "marvel.sm.resources.v1.Chapter", required = true },
      { name = "Policy", type = "PROTO", proto_package = "google.iam.v1.Policy", required = false },
      {
        name            = "book",          # = ParentResourceId
        type            = "STRING",
        is_computed     = true,
        computation_ddl = "REGEXP_EXTRACT(Chapter.name, r'^(authors/[^/]+)/(books/[^/]+)')",
        is_stored       = true
      },
      { name = "update_time", type = "TIMESTAMP", is_computed = true, /* …TIMESTAMP_ADD(... Chapter.update_time …) */ is_stored = true },
      { name = "delete_time", type = "TIMESTAMP", is_computed = true, /* …Chapter.delete_time… */ is_stored = true },
    ]
  }
}
resource "alis_google_spanner_table_ttl_policy" "Chapters_ttl" { /* column delete_time, ttl 90 */ }
resource "alis_google_spanner_table_foreign_key" "book_chapter" {
  table             = alis_google_spanner_table.Chapters.name
  name              = "FK_${replace(var.ALIS_OS_PROJECT, "-", "_")}_${replace("resources-v1", "-", "_")}_book_key"
  column            = "book"
  referenced_table  = alis_google_spanner_table.Books.name
  referenced_column = "key"
  on_delete         = "CASCADE"
}
```

Publisher (root, `has_revisions`) emits its own table **plus** a revision table + FK. The revision
computed column has no parent collections, so its regex is a single group on its own collection:

```hcl
resource "alis_google_spanner_table" "PublisherRevisions" {
  # …name … _PublisherRevisions, columns: key, PublisherRevision (PROTO marvel.sm.resources.v1.PublisherRevision),
  {
    name            = "publisher",         # = ResourceId
    computation_ddl = "REGEXP_EXTRACT(PublisherRevision.name, r'^(publishers/[^/]+)')",
    is_computed = true, is_stored = true, type = "STRING"
  }
  # … create_time, update_time computed …
}
resource "alis_google_spanner_table_foreign_key" "publisher_publisher_revision" {
  table = alis_google_spanner_table.PublisherRevisions.name
  column = "publisher"
  referenced_table = alis_google_spanner_table.Publishers.name
  referenced_column = "key"
  on_delete = "CASCADE"
}
```

## `internal/db/book.go` — header (anchors the 700-line `resource.go.tmpl`)

Only five substitutions vary across the whole file: `CollectionId` (→ `booksTable`),
`ResourceName` (→ `Book`, column + filter fields), `ResourceNamePlural` (→ `NewBooksTable`),
`ImportAlias` (`pb`), and `Imports`. Header (the rest of the methods substitute the same tokens):

```go
package db

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"

	"cloud.google.com/go/iam/apiv1/iampb"
	"cloud.google.com/go/spanner"
	"go.alis.build/sproto/filtering"
	"go.alis.build/sproto/ordering"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	pb "internal.sm.marvel.build/protobuf/marvel/sm/resources/v1"
	"marvel.sm.resources.v1/internal/database"
)

var (
	_ database.ResourceTable[*pb.Book] = (*booksTable[*pb.Book])(nil)
)

type booksTable[R proto.Message] struct {
	tableName    string
	client       *spanner.Client
	filterParser *filtering.Parser
}

func NewBooksTable(ctx context.Context, spannerProject, spannerInstance, spannerDatabase, tableName string) (database.ResourceTable[*pb.Book], error) {
	// …
	parser, err := filtering.NewParser(
		filtering.Timestamp("Book.create_time"),
		filtering.Timestamp("Book.update_time"),
		filtering.Timestamp("Book.delete_time"),
	)
	// …
	return &booksTable[*pb.Book]{tableName: tableName, client: spannerClient, filterParser: parser}, nil
}
// Create/BatchCreate/Read/BatchRead/Write/List/Stream/Query/Delete/BatchDelete/WritePolicy/BatchWritePolicies
// all follow, substituting the same five values.
```
