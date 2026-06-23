---
name: dbd-add-tracing-grpc-go
description: >
  Use this skill when the user wants to add Google Cloud distributed tracing to an existing Go
  gRPC neuron or Go service that calls gRPC backends, especially behind a Google Cloud External
  Application Load Balancer or Cloud Run. It implements the Build-stage code and infra changes for
  google.golang.org/grpc/gcp/observability, Cloud Trace sampling config, Terraform Cloud Run env
  wiring, and optional HTTP ingress to gRPC trace-context bridging. Go only. Not for authoring
  protos, non-Go services, or OpenTelemetry exporter implementations.
metadata:
  alis.context.version: "1"
  # Context field paths this skill needs from the injected runtime context.
  alis.context.requires: >-
    workstations.build_repos
---

# Add tracing to a Go gRPC service

Add Google Cloud distributed tracing to an existing **Go** neuron in the **Build** stage of
Define-Build-Deploy (DBD). Prefer the native gRPC observability plugin:

```go
google.golang.org/grpc/gcp/observability
```

This skill wires Cloud Trace/Monitoring export through Terraform configuration and starts
observability before any gRPC client or server is created.

## When to use

- An existing Go service/neuron makes or serves gRPC calls and should emit Cloud Trace spans.
- A service is behind a Google Cloud Application Load Balancer or Cloud Run and should preserve
  trace context into downstream Go gRPC calls.
- The user asks for the recommended/native gRPC observability route rather than a custom
  OpenTelemetry exporter.

## When not to use

| Need | Use instead |
| ---- | ----------- |
| Author or change proto contracts | **dbd-add-protos** |
| Scaffold a new Go gRPC server from protos | **dbd-add-grpc-go-server** |
| Non-Go tracing setup | Ask for the target runtime/framework |
| Vendor-neutral OpenTelemetry exporter setup | Use a dedicated OTel skill/workflow, not this one |

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads
`alis.context.requires` below to decide which context fields to include; the block carries
**only** those fields.
**When the block is present, its values are authoritative**: use the exact paths verbatim, and do
**not** scan folders or ask the user to confirm a value that was already provided.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent, how to obtain it |
| ----- | ------------- | --------------------------- |
| Neuron build root | `workstations.build_repos` | The existing Go service/neuron root containing `go.mod`, server/client startup code, and `infra/`. Default to the current working directory if it looks like a neuron build folder; otherwise ask. |

---

## Workflow

### 1. Confirm the service shape

Inspect the build root before editing:

- `go.mod` exists and the service is Go.
- The service uses gRPC directly or through helper packages.
- Find where gRPC clients or servers are created. Common patterns:
  - `grpc.NewServer(...)`
  - `grpc.Dial(...)` / `grpc.NewClient(...)`
  - product helpers such as `client.NewConnWithRetry(...)`
  - package-level `init()` functions that create global clients
- Find Terraform under `infra/`, especially Cloud Run env vars and any `tfvars.tf`/variable file.

If the service is not Go or has no gRPC surface, stop and explain that this skill does not apply.

### 2. Add the native gRPC observability dependency

Add the split gRPC observability module explicitly:

```bash
go get google.golang.org/grpc/gcp/observability@v1.0.1
```

Keep `google.golang.org/grpc` at the repo's current version unless the build requires otherwise.
Do not replace this with a custom OpenTelemetry Cloud Trace exporter.

### 3. Start observability before any gRPC clients or servers

Add:

```go
import "google.golang.org/grpc/gcp/observability"
```

Call `observability.Start(ctx)` before creating any gRPC clients or servers, and call
`observability.End()` during shutdown.

For services that create global gRPC clients in a package `init()`, start observability at the top
of that same `init()` before the first connection is created:

```go
func init() {
	ctx := context.Background()
	// Start gRPC observability before creating any clients; the plugin installs
	// global dial options that only apply to connections created after Start.
	if err := observability.Start(ctx); err != nil {
		alog.Fatalf(ctx, "failed to start gRPC observability: %v", err)
	}

	// Create gRPC clients after observability.Start.
}
```

In the main binary, flush/cleanup on exit:

```go
func main() {
	defer observability.End()

	// Start serving.
}
```

Do not hide this in an unnecessary helper unless the codebase already centralizes startup hooks.
The ordering is the important part.

### 4. Configure observability from Terraform

Prefer setting `GRPC_GCP_OBSERVABILITY_CONFIG` as a Cloud Run environment variable from Terraform,
not baking a JSON file into the Docker image and not branching over both config env names in Go.

In the repo's Terraform variable file, add:

```hcl
variable "GRPC_GCP_OBSERVABILITY_CONFIG" {
  default = <<-EOT
  {
    "cloud_trace": {
      "sampling_rate": 0.5
    },
    "cloud_monitoring": {}
  }
  EOT
}
```

In the Cloud Run service container env, add:

```hcl
env {
  name  = "GOOGLE_CLOUD_PROJECT"
  value = var.ALIS_OS_PROJECT
}

env {
  name  = "GRPC_GCP_OBSERVABILITY_CONFIG"
  value = var.GRPC_GCP_OBSERVABILITY_CONFIG
}
```

Use the project's existing variable names. If it uses a different project variable than
`ALIS_OS_PROJECT`, follow the repo's convention.

### 5. Bridge HTTP ingress to gRPC only when needed

Standard gRPC servers do **not** need an HTTP bridge: `grpc/gcp/observability` installs gRPC
StatsHandlers that extract and propagate gRPC trace metadata directly.

Add an HTTP-to-OpenCensus bridge only for services that receive HTTP ingress and then make outbound
gRPC calls, such as an MCP server. Without the bridge, the outbound gRPC spans can start a separate
trace from the ALB/HTTP request.

Imports:

```go
import (
	"net/http"

	stackdriverpropagation "contrib.go.opencensus.io/exporter/stackdriver/propagation"
	w3cpropagation "go.opencensus.io/plugin/ochttp/propagation/tracecontext"
	octrace "go.opencensus.io/trace"
)
```

Bridge helper:

```go
// openCensusTraceContext bridges ALB HTTP trace headers into the OpenCensus
// context used by gRPC observability. This server receives HTTP requests and
// then makes outbound gRPC calls, so without this bridge the outbound gRPC
// spans would start a separate trace.
//
// Standard gRPC servers do not need this helper: grpc/gcp/observability installs
// gRPC StatsHandlers that extract and propagate gRPC trace metadata directly.
func openCensusTraceContext(r *http.Request) (context.Context, func()) {
	sc, ok := (&stackdriverpropagation.HTTPFormat{}).SpanContextFromRequest(r)
	if !ok {
		sc, ok = (&w3cpropagation.HTTPFormat{}).SpanContextFromRequest(r)
	}
	if !ok {
		return r.Context(), func() {}
	}
	ctx, span := octrace.StartSpanWithRemoteParent(r.Context(), "request", sc)
	return ctx, span.End
}
```

Use it at the HTTP handler boundary before creating downstream contexts or making gRPC calls:

```go
ctx, endTrace := openCensusTraceContext(r)
defer endTrace()
r = r.WithContext(ctx)
```

If the service also uses structured logging correlation, preserve the existing logging trace
context helper if present, for example:

```go
ctx = alog.WithCloudTraceContext(ctx, r.Header.Get("X-Cloud-Trace-Context"))
```

### 6. Validate

Run targeted compile/tests with the same env var Terraform will set:

```bash
GRPC_GCP_OBSERVABILITY_CONFIG='{"cloud_trace":{"sampling_rate":0.5},"cloud_monitoring":{}}' \
GOOGLE_CLOUD_PROJECT=<test-project> \
go test ./...
```

If the repo requires private Alis protobuf modules, use the product's existing `GOPROXY` and
`GONOSUMDB` values from its Dockerfile or local environment.

Some Alis services initialize live Cloud Run gRPC clients during package init. A full local
`go test ./...` may fail with local ADC such as:

```text
idtoken: unsupported credentials type: "authorized_user"
```

When that happens, still verify packages that compile without live Cloud Run credentials, and
report the full-suite credential limitation clearly. Do not treat it as a tracing compile failure.

## Verification checklist

- [ ] `observability.Start(ctx)` runs before any gRPC client/server is created.
- [ ] `observability.End()` is deferred in the main binary.
- [ ] `GRPC_GCP_OBSERVABILITY_CONFIG` is set from Terraform/Cloud Run env, not by Docker file copy.
- [ ] `GOOGLE_CLOUD_PROJECT` is set for the runtime project.
- [ ] HTTP-to-OpenCensus bridge was added only if the service has HTTP ingress followed by gRPC calls.
- [ ] Comments explain the ordering requirement and any HTTP bridge rationale.
- [ ] Tests or targeted compile checks were run with observability config env set.
