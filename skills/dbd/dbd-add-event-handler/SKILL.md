---
name: dbd-add-event-handler
description: >
  Use this skill when the user wants a neuron to react to Pub/Sub events — for example
  "add an events handler", "subscribe to <X>Event", "handle pubsub messages", or "react to
  domain events". It generates a dedicated Cloud Run service named `{neuron-id}-events`: an
  HTTP `/HandleEvent` endpoint that receives Pub/Sub **push** messages and fans out by
  subscription name, plus `infra/events.tf` with the push subscriptions and the Cloud Run
  service. This is the Build stage and is Go only; it assumes the event protos are already
  defined and published. Not for the main gRPC server (dbd-add-grpc-go-server), authoring proto
  contracts (dbd-add-protos), or ADK scheduler/cron (adk-add-scheduler).
metadata:
  alis.context.version: "1"
  # Context field paths this skill needs from the injected runtime context.
  alis.context.requires: >-
    focus_neuron_id focus_package_id
    workstations.build_repos workstations.define_repos
---

# Add a Pub/Sub events handler

Stand up a dedicated **events handler** for an existing neuron: a separate Cloud Run service
named `{neuron-id}-events` that receives Pub/Sub **push** messages on a single `/HandleEvent`
HTTP endpoint and fans out to per-event logic by **subscription name**. This is the **Build**
stage of Define-Build-Deploy (DBD) and is **Go only**.

The handler service lives **alongside** the main neuron server (its own `events/` folder and its
own `go.mod`) and is deployed as its **own** Cloud Run service — it does not change the main gRPC
server. It assumes the event message types (`*Event` protos) are already **defined and
published**; this skill only consumes existing topics, it does not author protos or emit events.

This skill generates `events/server.go`, `events/handler.go`, an optional
`events/internal/clients/`, `events/go.mod`, `events/Dockerfile`, and `infra/events.tf` — modeled
on a working reference neuron. **Discover product- and registry-specific values from a sibling
neuron rather than hardcoding them.**

## When to use

- An existing neuron needs to react to domain events (its own or another service's) out of band
  from its request/response API.
- Adding one or more new event subscriptions to a neuron that does not yet have an events service.

## When not to use

| Need | Use instead |
| ---- | ----------- |
| Implement the main gRPC server / API | **dbd-add-grpc-go-server** |
| Author or change the event proto contract (`*Event` messages) | **dbd-add-protos** |
| Scheduled / recurring / cron-style runs for an ADK agent | **adk-add-scheduler** |
| Onboarding / running the full Define→Build→Deploy loop | **getting-started** |

## Runtime Context

This skill may be loaded with an `<alis-runtime-context>` block injected at the top of these
instructions by the Alis Build MCP `LoadSkill` handler. The handler reads
`alis.context.requires` below to decide which context fields to include; the block carries
**only** those fields.
**When the block is present, its values are authoritative**: use the exact paths and ids verbatim,
and do **not** scan folders or ask the user to confirm a value that was already provided.

### Context fields (`alis.context.requires`)

| Value | Context field | If absent, how to obtain it |
| ----- | ------------- | --------------------------- |
| Neuron / service id (**hyphenated**) | `focus_neuron_id` | Drives the Cloud Run service name `{neuron-id}-events`, the image name, and the push audience/endpoint host. E.g. `my-service-v1`. If absent, ask the user — do **not** derive it from `focus_package_id`. |
| Proto package (**dotted**) | `focus_package_id` | Drives the subscription-name prefix `{focus_package_id}.events_<EventType>` and the events module name. E.g. `alis.os.buildspecs.v1`. |
| Neuron build root | `workstations.build_repos` | Parent of the neuron's `events/` folder and `infra/`. The `events/` sub-module and `infra/events.tf` are written here. |
| Neuron define tree | `workstations.define_repos` | Used to discover which `*Event` message types exist to subscribe to (`<root>/<landing-zone>/define/<org>/<product>/<service>/<version>`). |

`focus_neuron_id` is **hyphenated** (`my-service-v1`); `focus_package_id` is **dotted**
(`alis.os.buildspecs.v1`). They are different values — use the hyphenated id for the Cloud Run
service/host and the dotted id for subscription names. Do not cross them.

---

## Workflow

### 1. Precondition check — are the event protos published?

Before generating anything, verify the event message types this handler will unmarshal **exist
and are published** — i.e. the internal protobuf package (e.g. `internal.<...>.services/protobuf`)
that contains the `*Event` types is importable. Discover the import path from a sibling neuron;
never guess it (see step 3).

If the event protos do not exist or have not been published, **stop** and tell the user:

> The event message types for these subscriptions do not appear to be defined/published yet.
> Please define and run **Define** for the event protos first (see the `dbd-add-protos` or
> `getting-started` skill), then re-run this skill.

Do not generate any files in this case. This skill does **not** edit the proto contract.

### 2. Interview the user

Ask — batched into one message — the two things that cannot be derived:

1. **Which events to subscribe to?** The fully-qualified, dotted event type names (these become
   `local.events` in Terraform and the `switch` cases in `handler.go`), e.g.
   `alis.os.buildspecs.v1.BuildSpecCreatedEvent`. Each must have an existing topic
   `projects/<project>/topics/<event-type>`.
2. **What should each handler do?** For each event: what side effect or downstream RPC the `case`
   should perform. If the handler calls back into the main neuron or other services, note which —
   that determines the `internal/clients/` gRPC clients (step 4, `internal/clients`).

### 3. Discover conventions from a sibling (do not hardcode)

Read an existing neuron in the same build repo — ideally an existing `events/` service — and copy
the product/registry-specific values rather than inventing them:

- The internal protobuf **module name and import path** for the event types (read from a sibling's
  `go.mod`/imports), e.g. `internal.os.alis.services/protobuf/alis/os/buildspecs/v1`.
- The `GOPROXY` / `GONOSUMDB` artifact-registry URLs and registry region in the `Dockerfile`.
- The Go version and dependency versions in `go.mod`.
- The infra **variable names** actually in use (`ALIS_OS_PROJECT`, `ALIS_RUN_HASH`,
  `ALIS_OS_PRODUCT_PROJECT`, `ALIS_OS_NEURON_VERSION_COMMIT_SHA`, `ALIS_REGION`, Spanner vars,
  `ALIS_OS_DOMAIN`, `ALIS_PRODUCT_CONFIG`) and the registry region used in image paths.

Never invent `ALIS_RUN_HASH`, commit SHAs, or variable names — read them from the sibling/infra.

### 4. Resolve target locations

- Handler service: `<workstations.build_repos>/events/` — its **own** Go module (separate
  `go.mod`), a sibling of the main server, not part of the main server module.
- Infra: `<workstations.build_repos>/infra/events.tf`.

If the build root is ambiguous or does not look like a `<neuron>/<version>` build folder, confirm
with the user before writing files.

### 5. Generate the files

Substitute the placeholders (see the table at the end).

#### `events/server.go` — HTTP push endpoint + envelope

The `prefix` string **must** match the subscription `name` prefix in `events.tf`
(`{focus_package_id}.events_`).

```go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"go.alis.build/alog"
)

// PubSubMessage is the payload of a Pub/Sub event.
// See https://cloud.google.com/pubsub/docs/reference/rest/v1/PubsubMessage
type PubSubMessage struct {
	Message struct {
		Data       []byte            `json:"data,omitempty"`
		ID         string            `json:"id"`
		Attributes map[string]string `json:"attributes,omitempty"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

func main() {
	http.HandleFunc("/HandleEvent", func(w http.ResponseWriter, r *http.Request) {
		// Convert the HTTP body to a Pub/Sub message.
		var m PubSubMessage
		body, err := io.ReadAll(r.Body)
		if err != nil {
			log.Printf("io.ReadAll: %v", err)
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		// Byte-slice unmarshalling handles base64 decoding of Message.Data.
		if err := json.Unmarshal(body, &m); err != nil {
			log.Printf("json.Unmarshal: %v", err)
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}

		// Subscription-name prefix — must match infra/events.tf subscription names.
		prefix := fmt.Sprintf("projects/%s/subscriptions/<focus_package_id>.events_",
			os.Getenv("ALIS_OS_PROJECT"))

		if err = handleEvent(r.Context(), m, prefix); err != nil {
			alog.Alertf(r.Context(), "handle event: %s", err.Error())
			return
		}
		alog.Debugf(r.Context(), "handled event: %s", m.Subscription)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
```

#### `events/handler.go` — fan-out by subscription

One `case` per chosen event. Each unmarshals `m.Message.Data` into its proto type then runs the
user's logic. Every entry in `local.events` (infra) must have a matching `case` here, and vice
versa.

```go
package main

import (
	"context"
	"fmt"

	"go.alis.build/alog"
	"google.golang.org/protobuf/proto"
	pb "<internal-protobuf-import-path>"
	// "<focus_package_id>/internal/clients" // only if calling back into services
)

// handleEvent receives and processes a Pub/Sub push message.
func handleEvent(ctx context.Context, m PubSubMessage, prefix string) error {
	switch m.Subscription {
	case prefix + "<EventType>":
		event := &pb.<EventMessage>{}
		if err := proto.Unmarshal(m.Message.Data, event); err != nil {
			return fmt.Errorf("unmarshal <EventMessage>: %w", err)
		}
		// TODO: handle <EventMessage> (call downstream RPCs / perform side effects).

	// ...one case per subscribed event type...

	default:
		return fmt.Errorf("subscription (%s) not handled", m.Subscription)
	}

	alog.Infof(ctx, "successfully handled subscription: %s", m.Subscription)
	return nil
}
```

#### `events/internal/clients/internal_clients.go` — only if calling back into services

Create this only when a handler calls the main neuron or other services. Discover service hosts
and the connection helper from the sibling (`go.alis.build/client`, `ALIS_RUN_HASH`).

```go
package clients

import (
	"context"
	"os"

	"go.alis.build/alog"
	"go.alis.build/client"
	"google.golang.org/grpc"
	pb "<internal-protobuf-import-path>"
)

const (
	maxSendSize = 2000000000
	maxRecvSize = 2000000000
)

var <ClientVar> pb.<ServiceClient>

func init() {
	if os.Getenv("ALIS_RUN_HASH") == "" {
		alog.Fatal(context.Background(), "ALIS_RUN_HASH is not set")
	}
	ctx := context.Background()
	opts := grpc.WithDefaultCallOptions(grpc.MaxCallSendMsgSize(maxSendSize), grpc.MaxCallRecvMsgSize(maxRecvSize))

	if conn, err := client.NewConnWithRetry(ctx, "<neuron-id>-"+os.Getenv("ALIS_RUN_HASH")+".run.app:443", false, opts); err != nil {
		alog.Fatal(ctx, err.Error())
	} else {
		<ClientVar> = pb.New<ServiceClient>(conn)
	}
}
```

#### `events/go.mod`

Module name is the dotted `focus_package_id` (matches the sibling events module). Copy Go and
dependency versions from the sibling.

```
module <focus_package_id>

go <go-version-from-sibling>

require (
	go.alis.build/alog <version>
	go.alis.build/client <version>
	google.golang.org/grpc <version>
	google.golang.org/protobuf <version>
	<internal-protobuf-module> <version>
)
```

#### `events/Dockerfile`

Multi-stage build; copy the `GOPROXY`/`GONOSUMDB` lines and registry region from the sibling.

```dockerfile
FROM golang:latest AS builder
WORKDIR /app

# Configure artifact registry auth.
ENV GOPROXY=proxy.golang.org
RUN go run github.com/GoogleCloudPlatform/artifact-registry-go-tools/cmd/auth@v0.1.0 add-locations --locations=<region-from-sibling>

COPY . ./

# Refresh auth token to authenticate with artifact registry.
RUN go run github.com/GoogleCloudPlatform/artifact-registry-go-tools/cmd/auth@v0.1.0 refresh

ENV GOPROXY=<goproxy-from-sibling>
ENV GONOSUMDB=<gonosumdb-from-sibling>

RUN go build -mod=readonly -v -o server

FROM debian:bookworm-slim
RUN set -x && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/server /app/server

CMD ["/app/server"]
```

#### `infra/events.tf` — subscriptions + Cloud Run service

The subscription `name` prefix must match the `prefix` in `server.go`. The Cloud Run service
name, the push `audience`, and the push `endpoint` host must all be `{neuron-id}-events`.

```hcl
locals {
  events = [
    "<EventType>",
    # ...one entry per subscribed event type (dotted)...
  ]
}

resource "google_pubsub_subscription" "events" {
  for_each                   = toset(local.events)
  name                       = "<focus_package_id>.events_${each.key}"
  topic                      = "projects/${var.ALIS_OS_PROJECT}/topics/${each.key}"
  message_retention_duration = "600s"
  ack_deadline_seconds       = 180

  retry_policy {
    maximum_backoff = "77s"
    minimum_backoff = "7s"
  }

  expiration_policy {
    ttl = ""
  }

  push_config {
    oidc_token {
      audience              = "https://<neuron-id>-events-${var.ALIS_RUN_HASH}.run.app"
      service_account_email = "alis-build@${var.ALIS_OS_PROJECT}.iam.gserviceaccount.com"
    }
    push_endpoint = "https://<neuron-id>-events-${var.ALIS_RUN_HASH}.run.app/HandleEvent"
  }
}

resource "google_cloud_run_v2_service" "events" {
  name                = "<neuron-id>-events"
  location            = var.ALIS_REGION
  description         = "This service is dedicated to handling Pub/Sub events."
  ingress             = "INGRESS_TRAFFIC_ALL"
  provider            = google
  deletion_protection = false

  template {
    scaling {
      max_instance_count = 10
    }
    containers {
      image = "<region>-docker.pkg.dev/${var.ALIS_OS_PRODUCT_PROJECT}/neurons/<neuron-id>/events:${var.ALIS_OS_NEURON_VERSION_COMMIT_SHA}"
      env {
        name  = "ALIS_OS_PROJECT"
        value = var.ALIS_OS_PROJECT
      }
      env {
        name  = "ALIS_RUN_HASH"
        value = var.ALIS_RUN_HASH
      }
      env {
        name  = "ALIS_PRODUCT_CONFIG"
        value = var.ALIS_PRODUCT_CONFIG
      }
      # Add Spanner / domain env vars only if the handler needs them — match the sibling.
      env {
        name  = "ALIS_OS_DOMAIN"
        value = var.ALIS_OS_DOMAIN
      }

      resources {
        limits = {
          cpu : "1000m"
          memory : "2Gi"
        }
        cpu_idle = true
      }
    }
    max_instance_request_concurrency = 77
    timeout                          = "240s"
    service_account                  = "alis-build@${var.ALIS_OS_PROJECT}.iam.gserviceaccount.com"
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}
```

### 6. Verify

In the events folder:

```sh
cd <workstations.build_repos>/events
go mod tidy
go build ./...
```

Resolve any compile errors (usually the protobuf import path or a missing dependency version — fix
by re-checking the sibling neuron). If a Terraform CLI is available, `terraform fmt` and validate
the infra directory.

Then tell the user:
- The handler is deployed as its **own** Cloud Run service, `{neuron-id}-events`, separate from the
  main neuron.
- The next DBD step is **Build/Deploy** once the handler bodies are filled in.

**This skill only scaffolds the events handler and its infra — it does not run Define, Build, or
Deploy, and it does not author proto contracts.**

---

## Placeholders reference

| Placeholder | Meaning | Example |
| ----------- | ------- | ------- |
| `<focus_neuron_id>` / `<neuron-id>` | Neuron id (hyphenated); Cloud Run service & host | `my-service-v1` |
| `<focus_package_id>` | Proto package (dotted); subscription prefix & events module name | `alis.os.buildspecs.v1` |
| `<EventType>` | Fully-qualified dotted event type (subscription/topic) | `alis.os.buildspecs.v1.BuildSpecCreatedEvent` |
| `<EventMessage>` | Go message type for the event | `BuildSpecCreatedEvent` |
| `<internal-protobuf-import-path>` | Published protobuf import path (from a sibling) | `internal.os.alis.services/protobuf/alis/os/buildspecs/v1` |
| `<internal-protobuf-module>` | Published protobuf module name (from a sibling) | `internal.os.alis.services/protobuf` |
| `<region>` | Artifact Registry region for the image (from a sibling) | `europe-west1` |

## Verification checklist

- [ ] Event protos exist/are published; if not, the skill stopped and routed to Define.
- [ ] `events/` is its own Go module (`module <focus_package_id>`), separate from the main server.
- [ ] `server.go` `prefix` (`{focus_package_id}.events_`) matches the `events.tf` subscription `name` prefix.
- [ ] Cloud Run service name, push `audience` host, and push `endpoint` host are all `{neuron-id}-events`.
- [ ] Every `local.events` entry has a matching `switch` case in `handler.go`, and vice versa.
- [ ] Hyphenated `focus_neuron_id` used for service/host; dotted `focus_package_id` used for subscription names — not crossed.
- [ ] Internal protobuf import path, `GOPROXY`/`GONOSUMDB`, region, and dependency versions copied from a sibling — nothing invented.
- [ ] `go mod tidy && go build ./...` passes in `events/`.

## Pitfalls

- Crossing the ids — hyphenated `focus_neuron_id` for the service/host, dotted `focus_package_id`
  for subscription names. Mixing them breaks delivery routing.
- `server.go` `prefix` not matching the `events.tf` subscription `name` prefix — the `switch`
  never matches and every message hits `default`.
- An entry in `local.events` with no matching `case` (or a `case` with no subscription) — silently
  unhandled or never delivered.
- Cloud Run name / push `audience` / push `endpoint` host disagreeing — OIDC auth or delivery fails.
- Treating `events/` as part of the main server module — it is its **own** Go module with its own
  `go.mod` and Dockerfile, deployed as a separate image (`.../neurons/{neuron-id}/events:...`).
- Inventing `ALIS_RUN_HASH`, commit SHAs, the protobuf import path, registry region, or variable
  names — always read them from a sibling neuron / existing infra.
- Adding Spanner or other env vars the handler does not use — include only what the sibling/handler
  needs.
- Authoring or editing protos here — that is `dbd-add-protos`; this skill assumes they are published.
