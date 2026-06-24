---
name: dbd-add-tracing-grpc-go
description: >
  Use this skill when the user wants to add Google Cloud distributed tracing to an existing Go
  gRPC neuron or Go service that calls gRPC backends, especially on Cloud Run. It implements the
  Build-stage code changes for go.alis.build/trace, Cloud Trace export, gRPC server/client
  instrumentation, protobuf package naming, and explicit startup ordering. Go only. Not for
  authoring protos, non-Go services, or generic OpenTelemetry collector deployments.
metadata:
  alis.context.version: "1"
  # Context field paths this skill needs from the injected runtime context.
  alis.context.requires: >-
    workstations,
    focus_package_id
---

# Add tracing to a Go gRPC service

Add Google Cloud distributed tracing to an existing **Go** neuron in the **Build** stage of
Define-Build-Deploy (DBD). Use the shared Alis tracing helper:

```go
go.alis.build/trace
```

This package configures the Google Cloud Trace exporter, OpenTelemetry resource attributes,
sampling, and gRPC stats handlers. The service must start tracing before constructing any gRPC
server or client that should be instrumented.

## When to use

- An existing Go service/neuron makes or serves gRPC calls and should emit Cloud Trace spans.
- A Cloud Run service should propagate trace context into downstream Go gRPC calls.
- The user wants the standard Alis Build tracing setup rather than service-local OpenTelemetry
  exporter code.

## When not to use

| Need | Use instead |
| ---- | ----------- |
| Author or change proto contracts | **dbd-add-protos** |
| Scaffold a new Go gRPC server from protos | **dbd-add-grpc-go-server** |
| Non-Go tracing setup | Ask for the target runtime/framework |
| Generic OpenTelemetry Collector setup | Use a dedicated OTel workflow, not this one |

## Runtime Context

When `mcp.v1` loads this skill, it injects an `<alis-runtime-context>` block at the top of the
returned `SKILL.md` before the agent receives it. The loader reads `alis.context.requires` below to
decide which context fields to include; the block carries **only** those fields.
**When the block is present, its values are authoritative**: use the exact values verbatim, and do
**not** scan folders or ask the user to confirm a value that was already provided.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent, how to obtain it |
| ----- | ------------- | --------------------------- |
| Neuron build root | `workstations` | Use the focused workstation's `build_repos` entry for the existing Go service/neuron root containing `go.mod` and server/client startup code. Default to the current working directory if it looks like a neuron build folder; otherwise ask. |
| Focus package id | `focus_package_id` | Derive from the focused neuron id by replacing hyphens with dots, for example `alis-os-skills-v1` -> `alis.os.skills.v1`; otherwise inspect the generated protobuf package. |

---

## Workflow

### 1. Confirm the service shape

Inspect the build root before editing:

- `go.mod` exists and the service is Go.
- The service uses gRPC directly or through helper packages.
- Find where gRPC clients or servers are created. Common patterns:
  - `grpc.NewServer(...)`
  - `grpc.Dial(...)` / `grpc.NewClient(...)`
  - `go.alis.build/client/v2.NewConn(...)`
  - package-level `init()` functions that create global clients
- Find the generated protobuf package used by the service, usually imported as `pb`.
- If the injected `<alis-runtime-context>` block provides `focus_package_id`, use that exact value
  for `trace.Config.Package`.

If the service is not Go or has no gRPC surface, stop and explain that this skill does not apply.

### 2. Add the tracing dependency

Add the shared tracing module:

```bash
go get go.alis.build/trace@latest
```

Keep `google.golang.org/grpc` at the repo's current version unless the build requires otherwise.

### 3. Start tracing explicitly in main

Tracing must start before any gRPC server or client is constructed. Prefer explicit startup in
`main`, followed by server/client construction.

```go
import (
	"context"

	"go.alis.build/trace"
)

const traceSamplingRatio = 0.7

func main() {
	ctx := context.Background()
	packageID := "<focus_package_id from injected alis-runtime-context>"
	// Start the tracer provider before constructing any gRPC clients or servers.
	// The gRPC trace options below read the global OpenTelemetry provider that trace.Start installs.
	shutdownTracing, err := trace.Start(ctx, trace.Config{
		Package:     packageID,
		ProjectID:   projectID,
		SampleRatio: traceSamplingRatio,
	})
	if err != nil {
		alog.Fatalf(ctx, "failed to start tracing: %v", err)
	}
	defer func() {
		if err := shutdownTracing(context.Background()); err != nil {
			alog.Warnf(context.Background(), "shutting down tracer provider: %v", err)
		}
	}()

	// Construct traced gRPC servers and clients after trace.Start.
}
```

`Package` is the Alis focus package id implemented by the Cloud Run service, for example
`alis.os.skills.v1` or `alis.os.iam.v2`. The tracing package records this value as the OpenTelemetry
`service.name` resource attribute. This scales to Cloud Run servers that host multiple protobuf
services from one package; individual RPC spans still carry the full protobuf service and method
names.

When the injected `<alis-runtime-context>` block provides `focus_package_id`, use that exact value
for `trace.Config.Package`. For example, `focus_package_id = "alis.os.skills.v1"` means
`Package: "alis.os.skills.v1"`. Treat the injected Context value as authoritative unless the
repository's generated protobuf package clearly contradicts it.

Use the repo's existing project id configuration for `ProjectID`, such as `utils.ProjectID` or
`trace.ProjectIDFromEnv()`.

Do not hide tracing startup in `init()`. If the service currently creates gRPC clients or servers
in package-level variables or `init()` functions, refactor those constructors so `main` can run:

1. `trace.Start(...)`
2. route/client/server setup
3. listen/serve

The order matters because `trace.Start(...)` installs the OpenTelemetry tracer provider and Cloud
Trace exporter used by `trace.GRPCServerOption()` and `trace.GRPCDialOption()`. If a gRPC server or
client is created before tracing starts, that server/client can bind to the wrong tracer provider
and miss spans or propagation. A common shape is:

```go
func main() {
	ctx := context.Background()
	shutdownTracing, err := trace.Start(ctx, trace.Config{
		Package:     "alis.os.dbd.v1",
		ProjectID:   trace.ProjectIDFromEnv(),
		SampleRatio: traceSamplingRatio,
	})
	if err != nil {
		alog.Fatalf(ctx, "failed to start tracing: %v", err)
	}
	defer func() {
		if err := shutdownTracing(context.Background()); err != nil {
			alog.Warnf(context.Background(), "shutting down tracer provider: %v", err)
		}
	}()

	// Build outbound clients after trace.Start so their dial options attach tracing.
	if err := clients.Init(ctx); err != nil {
		alog.Fatalf(ctx, "failed to initialise clients: %v", err)
	}

	// Build the gRPC server after trace.Start so inbound RPCs create server spans.
	grpcServer := grpc.NewServer(
		trace.GRPCServerOption(),
		grpc.UnaryInterceptor(unaryInterceptor),
	)
}
```

### 4. Instrument gRPC servers

Add `trace.GRPCServerOption()` when constructing the gRPC server:

```go
grpcServer := grpc.NewServer(
	// Installs the OpenTelemetry gRPC stats handler for inbound RPCs.
	// This creates server spans and extracts propagated trace context from callers.
	trace.GRPCServerOption(),
	grpc.UnaryInterceptor(unaryInterceptor),
	grpc.StreamInterceptor(streamInterceptor),
)
```

If the codebase currently has a package-level `var Server = grpc.NewServer(...)`, prefer replacing
it with a constructor:

```go
func NewServer() *grpc.Server {
	return grpc.NewServer(
		// Keep this option on every constructed gRPC server that should emit Cloud Trace spans.
		trace.GRPCServerOption(),
		grpc.UnaryInterceptor(unaryInterceptor),
		grpc.StreamInterceptor(streamInterceptor),
	)
}
```

Call this constructor only after `trace.Start(...)`.

### 5. Instrument gRPC clients

Add `trace.GRPCDialOption()` to outbound gRPC connections.

For `go.alis.build/client/v2`:

```go
conn, err := client.NewConn(ctx, host, false,
	// Adds the OpenTelemetry gRPC stats handler to the underlying dial.
	// This creates client spans and injects trace context into outbound RPCs.
	client.WithDialOptions(trace.GRPCDialOption()),
)
```

For direct gRPC:

```go
conn, err := grpc.NewClient(host,
	// Creates client spans for outbound RPCs and propagates trace context downstream.
	trace.GRPCDialOption(),
	// existing dial options...
)
```

Create these clients only after `trace.Start(...)`.

### 6. Validate

Run module tidy and targeted compile/tests:

```bash
go mod tidy
go test ./... -run '^$'
```

Run focused unit tests that do not require live Cloud Run or Vertex credentials.

Some Alis services initialize live Cloud Run gRPC clients during setup. A full local `go test ./...`
may fail with local ADC such as:

```text
idtoken: unsupported credentials type: "authorized_user"
```

or with external-service errors from placeholder test projects. When that happens, still verify
packages that compile without live Cloud Run credentials, and report the full-suite credential or
integration limitation clearly. Do not treat it as a tracing compile failure.

## Verification checklist

- [ ] `go.alis.build/trace` is required in `go.mod`.
- [ ] `trace.Start(ctx, trace.Config{Package: ...})` runs in `main` before gRPC clients/servers are created.
- [ ] `Package` is the focus package id, such as `alis.os.skills.v1`, preferably taken directly from injected `focus_package_id` when present.
- [ ] The shutdown function returned by `trace.Start` is deferred.
- [ ] gRPC servers include `trace.GRPCServerOption()`.
- [ ] Outbound gRPC clients include `trace.GRPCDialOption()`.
- [ ] Package-level gRPC client/server initialization was refactored when needed to preserve startup order.
- [ ] Tests or targeted compile checks were run and any credential/integration limitations were reported.
