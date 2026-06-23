---
name: dbd-add-grpc-go-server
description: >
  Use this skill when the user wants to stand up a new gRPC Go server (neuron) from protocol
  buffers that were already locked in during Define — generating server.go, one Go file per
  service with method stubs, go.mod, Dockerfile, and infra. Go only. Assumes Define is complete;
  if the protos/packages are missing, it stops and routes the user to Define. Not for other
  languages and not for editing the proto contract itself.
metadata:
  alis.context.version: "1"
  # Context field paths this skill needs from the injected runtime context.
  alis.context.requires: >-
    workstations session.working_directory
---

# Add a gRPC Go server

Scaffold a complete, buildable gRPC **Go** neuron from protocol buffers that were already locked in
during the **Define** step of the Define-Build-Deploy (DBD) workflow. The generated server is wired
to the published protobuf package and is ready for you to fill in business logic and run **Build**.

This skill generates `server.go`, one Go file per proto service, `go.mod`, a `Dockerfile`, and the
`infra/*.tf` Terraform — modeled on a working reference neuron. It is **Go only**.

## When to use

- After **Define** is complete (protos committed, Define run, Go protobuf package published) and the
  user wants to implement a new Go gRPC service.
- Adding a Go gRPC neuron to a product build repo from existing `.proto` service definitions.

## When not to use

- **Before Define.** If the protos/packages do not exist yet, stop and route the user to Define
  (see the `getting-started` / `review-define` skills). This skill does not edit the proto contract.
- **Non-Go languages.** This skill is Go only.

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads
`alis.context.requires` below to decide which context fields to include; the block carries
**only** those fields.
**When the block is present, its values are authoritative**: use the exact paths verbatim, and do
**not** scan folders or ask the user to confirm a value that was already provided.

### Context fields (`alis.context.requires`)

| Value                 | Context field                | If absent, how to obtain it                                                                                                          |
| --------------------- | ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Proto definitions dir | `workstations`  | Use the focused workstation's `define_repos` entry: the path where the `.proto` **definitions** for this service live (`<root>/<landing-zone>/define/<org>/<product>/<service>/<version>`). The server is generated from the services found here. |
| Implementation dir    | `session.working_directory`  | The directory where `server.go` and the rest of the neuron are written. Default to the current working directory; confirm with the user if it does not look like a `<neuron>/<version>` build folder. |

---

## Workflow

### 1. Precondition check — is Define done?

Before generating anything, verify both:

1. **Proto service definitions exist** under `workstations.define_repos`
   (e.g. `.../define/<org>/<product>/<service>/v1/*.proto`) and at least one of them declares a
   `service`.
2. **The generated Go protobuf package is available** — a published module such as
   `internal.<...>.build/protobuf`. Discover this; never guess it (see step 4).

If protos are missing, no `.proto` declares a `service`, or the protobuf package has not been
published, **stop** and tell the user:

> The protocol buffers for this service do not appear to be defined/published yet. Please run the
> **Define** step first (see the `getting-started` or `review-define` skill), then re-run this skill.

Do not generate any files in this case.

### 2. Confirm the source definitions with the user

State plainly, before generating anything, which definitions the server is built from:

> The Go server implementation will be based on the definitions at
> `<workstations.define_repos>`. The following service(s) were discovered: `<Service A>`,
> `<Service B>`, …

This makes explicit that the generated server is derived from those proto definitions.

### 3. Resolve the target location

Generate the neuron into `session.working_directory`.

Build neurons mirror the define path minus the org-domain prefix:

```
define/aibake/ge/hello/v1   →   build/ge/hello/v1
```

If `session.working_directory` is ambiguous or does not follow the `<neuron>/<version>` convention,
confirm the destination folder with the user before writing files.

### 4. Discover conventions from a sibling neuron (do not hardcode)

Read an existing neuron in the same build repo (for example a `demo/v1`) and copy the values that
are product- and registry-specific rather than inventing them:

- The internal protobuf **module name and import path**, e.g.
  `internal.ge.aibake.build/protobuf/<proto/pkg/path>` (the module name reorders the proto package,
  so always read it from a sibling's `go.mod`/imports).
- The `GOPROXY` / `GONOSUMDB` artifact-registry URLs in the `Dockerfile`.
- The Go version and dependency versions in `go.mod`.

If no sibling neuron exists, derive the import path from the Define output or the proto
`option go_package`, and use the module versions from the Define-published package.

### 5. Parse the proto service(s)

Discover **all** `.proto` files under the define path for this neuron and process **every** service
found across them. For each service extract:

- the **service name** (e.g. `HelloService`, `Demo`), and
- for each RPC: its **name** and its **request** / **response** message types.

### 6. Generate the files

Write the following into `session.working_directory`, substituting the placeholders (see the table
at the end).

#### `server.go` — single entrypoint, registers every service

```go
package main

import (
	"context"
	"net"

	"go.alis.build/alog"
	"google.golang.org/grpc"
	pb "<internal-protobuf-import-path>"
)

func main() {
	ctx := context.Background()
	alog.Notice(ctx, "starting server...")

	// Create a listener which will listen to incoming gRPC calls.
	listener, err := net.Listen("tcp", ":8080")
	if err != nil {
		alog.Fatalf(ctx, "net.Listen: %v", err.Error())
	}

	grpcServer := grpc.NewServer()

	// Register every service discovered in the protos.
	pb.Register<Service>Server(grpcServer, &<service_camel>Server{})
	// ...one Register call per service...

	if err = grpcServer.Serve(listener); err != nil {
		alog.Fatal(ctx, err.Error())
	}
}
```

#### One Go file per service

For **every** service, create a file named after the service in **snake_case**. This keeps the Go
server structure consistent with the definitions (see the gRPC Go basics guide:
https://grpc.io/docs/languages/go/basics/).

| Proto service          | Go file            | Struct type          |
| ---------------------- | ------------------ | -------------------- |
| `service Demo`         | `demo.go`          | `demoServer`         |
| `service HelloService` | `hello_service.go` | `helloServiceServer` |

Each per-service file embeds the generated `Unimplemented...Server` (for forward compatibility) and
declares one method **stub** per RPC:

```go
package main

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	pb "<internal-protobuf-import-path>"
)

// <service_camel>Server implements pb.<Service>Server.
type <service_camel>Server struct {
	pb.Unimplemented<Service>Server
}

// <Rpc> implements pb.<Service>Server.
func (s *<service_camel>Server) <Rpc>(ctx context.Context, req *pb.<RequestType>) (*pb.<ResponseType>, error) {
	// TODO: implement <Rpc>.
	return nil, status.Errorf(codes.Unimplemented, "<Rpc> not implemented")
}

// ...one method per RPC...
```

#### `go.mod`

```
module <proto.package>

go <go-version-from-sibling>

require (
	go.alis.build/alog <version>
	google.golang.org/grpc <version>
	internal.<...>.build/protobuf <version>
)
```

`<proto.package>` is the proto package with dots, e.g. `aibake.ge.hello.v1`. Copy versions from the
sibling neuron's `go.mod`.

#### `Dockerfile`

Use the multi-stage template below, copying the `GOPROXY` / `GONOSUMDB` lines and registry regions
from the sibling neuron:

```dockerfile
FROM golang:latest AS builder
WORKDIR /app

# Configure artifact registry auth
ENV GOPROXY=proxy.golang.org
RUN go run github.com/GoogleCloudPlatform/artifact-registry-go-tools/cmd/auth@v0.1.0 add-locations --locations=<regions-from-sibling>

# Copy local code to the container image.
COPY . ./

# Refresh auth token to authenticate with artifact registry
RUN go run github.com/GoogleCloudPlatform/artifact-registry-go-tools/cmd/auth@v0.1.0 refresh

# Setup GOPROXY & GONOSUMDB based on the internal and consumer stubs used in this go module
ENV GOPROXY=<goproxy-from-sibling>
ENV GONOSUMDB=<gonosumdb-from-sibling>

# Build the binary.
RUN go build -mod=readonly -v -o server

FROM debian:bookworm-slim
RUN set -x && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/server /app/server

CMD ["/app/server"]
```

#### `infra/` Terraform

Copy `infra/main.tf`, `infra/variables.tf`, `infra/apis.tf`, and `infra/cloudrun.tf` from the sibling
neuron. In `cloudrun.tf` set the Cloud Run service name and image name to `<neuron>-<version>`:

```hcl
resource "google_cloud_run_v2_service" "default" {
  name     = "<neuron>-<version>"
  location = var.ALIS_REGION
  # ...
  image = "${var.ALIS_REGION}-docker.pkg.dev/${var.ALIS_OS_PRODUCT_PROJECT}/neurons/<neuron>-<version>:${var.ALIS_OS_NEURON_VERSION_COMMIT_SHA}"
  # ...
}
```

### 7. Verify

In the neuron folder (`session.working_directory`):

```sh
go mod tidy
go build ./...
```

Resolve any compile errors (usually the protobuf import path or a missing dependency version — fix
by re-checking the sibling neuron). Optionally exercise the service via `.playground/main_test.go`
after it is deployed.

Then tell the user the next DBD step is **Build** once the method bodies are filled in.
**This skill only scaffolds the server — it does not run Define, Build, or Deploy.**

---

## Placeholders reference

| Placeholder                       | Meaning                                                | Example                                                |
| --------------------------------- | ------------------------------------------------------ | ------------------------------------------------------ |
| `<Service>`                       | Proto service name, as-is                              | `HelloService`                                         |
| `<service_camel>`                 | Service name, lower camelCase (used for the struct)    | `helloService` → `helloServiceServer`                  |
| `<service_snake>`                 | Service name, snake_case (used for the file name)      | `hello_service` → `hello_service.go`                   |
| `<Rpc>`                           | RPC method name                                        | `CalculateRandomNumber`                                |
| `<RequestType>` / `<ResponseType>`| RPC request / response message types                   | `CalculateRandomNumberRequest`                         |
| `<proto.package>`                 | Proto package (dotted), used as the Go module name     | `aibake.ge.hello.v1`                                   |
| `<internal-protobuf-import-path>` | Published protobuf import path (read from a sibling)   | `internal.ge.aibake.build/protobuf/aibake/ge/hello/v1` |
| `<neuron>` / `<version>`          | Neuron folder name and version segment                 | `hello` / `v1`                                         |
