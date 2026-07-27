# Go per-neuron proto migration

Follow [`SKILL.md`](../SKILL.md) for when to use this skill, migration root rules, the
mapping rule, and the public-stubs invariant. This document is the **Go procedure**.

## Go procedure

1. **Inventory the legacy imports** under the migration root:

   ```bash
   pwd
   rg -n 'internal\.[a-z0-9]+\.[a-z.]+/protobuf/' -g '*.go' .
   ```

   Collect the distinct `<org>/<product>/<neuron-path>/<vN>` suffixes.

2. **Rewrite every import** using the mapping rule in [`SKILL.md`](../SKILL.md), keeping
   aliases. E.g.

   ```go
   pb "internal.os.alis.services/protobuf/alis/os/mcp/v1"
   ```

   becomes

   ```go
   pb "alis.build/alis/os/mcp"
   ```

3. **Update every Dockerfile under the migration root**, including Dockerfiles in nested components:

   ```bash
   rg --files -g 'Dockerfile*' .
   ```

   For each Dockerfile that configures Go module access:
   - Replace the complete `GONOSUMDB` value with `alis.build`.
   - Replace each product registry repository suffix `protobuf-go-internal` with `define-go`,
     preserving the registry host, location, GCP project, and product order.
   - Remove the `openprotos-go` registry entry. Open protos now resolve through their public Go
     modules and no longer need the legacy Artifact Registry proxy.
   - Preserve `https://proxy.golang.org,direct` at the end of `GOPROXY`.

   Example:

   ```dockerfile
   ENV GOPROXY=https://europe-west1-go.pkg.dev/alis-os-product-w4apgtd/protobuf-go-internal,https://europe-west1-go.pkg.dev/alis-bl-product-r4e/protobuf-go-internal,https://europe-west1-go.pkg.dev/alis-org-777777/openprotos-go,https://proxy.golang.org,direct
   ENV GONOSUMDB=internal.bl.alis.services/protobuf,internal.os.alis.services/protobuf,open.alis.services/protobuf
   ```

   becomes:

   ```dockerfile
   ENV GOPROXY=https://europe-west1-go.pkg.dev/alis-os-product-w4apgtd/define-go,https://europe-west1-go.pkg.dev/alis-bl-product-r4e/define-go,https://proxy.golang.org,direct
   ENV GONOSUMDB=alis.build
   ```

4. **Install the new packages after the import and Dockerfile changes**. Run the CLI from the
   migration root; it resolves the selected neuron from the current directory, installs all
   required per-neuron modules, supplies the correct
   `GOPROXY`/`GONOSUMDB`, and runs `go mod tidy`:

   ```bash
   alis packages install --json
   ```

   Compare any product `define-go` registry list reported by the command with the Dockerfiles and
   align them if it differs from the mechanical replacement; the CLI accounts for every migrated
   cross-product dependency.

   Raw alternative (use only when the CLI is unavailable; take the environment values from the
   `install_packages` command the CLI previously printed):

   ```bash
   GOPROXY="<proxy>" GONOSUMDB="<nosumdb>" go get alis.build/<org>/<product>/<neuron>@latest
   ```

5. **Confirm the legacy requires were dropped**. Once no
   `internal.<product>.<domain>/protobuf/...` imports remain, the `go mod tidy` performed by
   `alis packages install` removes the legacy requires. If another product's legacy module is
   still imported elsewhere in the service, migrate those imports and run the install command
   again. Complete this migration with no legacy protobuf module roots remaining.

## Verify

1. Confirm no migrated legacy module plumbing remains in Go files or Dockerfiles:

   ```bash
   rg -n 'internal\.[a-z0-9]+\.[a-z.]+/protobuf|protobuf-go-internal|openprotos-go' \
     -g '*.go' -g 'go.mod' -g 'Dockerfile*' .
   ```

   The command should return no matches. If it finds one, finish that migration before building.
   A Docker image build is not required to complete this migration.

2. Validate each regular service module with:

   ```bash
   go vet ./...
   go build ./...
   ```

   Treat a test-only playground module separately. If it contains `main_test.go` but no
   non-test `main` function, `go build` is not an applicable validation and may correctly report
   that no `main` function exists. Vet it and compile its test binary without running tests:

   ```bash
   go vet ./...
   go test -c -o /tmp/<service>-playground.test
   ```

   Do not use `go test -run '^$' ./...` as a compile-only check: package initialization or
   `TestMain` can still run and may fail while acquiring credentials or contacting DEV.

3. From the same migration root, run `alis packages upgrade --json` and verify that it upgrades only the scoped
   `alis.build/<org>/<product>/<neuron>` package in each applicable module, including the
   playground, without printing the legacy-package migration hint.
4. After the scoped upgrade completes, repeat the legacy scan and the module checks above. The
   migration is complete only when the scan is still empty, regular service modules build and
   vet, and test-only playground modules compile and vet.
5. Treat running a playground against DEV as a separate end-to-end check. Run it only with the
   required application credentials or identity-token support available; an `Unauthenticated`
   token-source failure is an environment/authentication failure, not a compile failure.

## Public stubs migration (Go)

The public-stubs **invariant**, path table, and symptom list live in
[`SKILL.md`](../SKILL.md). This section is the Go fix procedure. Order matters.

### Procedure

1. **Re-define stale generated packages first.** List every `alis.build/...` module in the
   graph and check its module-cache source for old-path imports:

   ```bash
   go list -deps -f '{{if .Module}}{{.Module.Path}} {{.Module.Version}}{{end}}' ./... \
     | sort -u | grep '^alis.build/'
   rg -l 'github.com/alis-build/public-go/' ~/go/pkg/mod/<module>@<version>/
   ```

   For each stale one, run `alis define <package-id>` (no proto edits needed — regeneration
   picks up the vanity paths). One re-define can expose the next stale dependency — iterate
   until the scan is clean. If the stale set includes _common_ packages themselves, define
   leaves before dependents (e.g. `validation`/`options` before `iam`), or the dependent's
   fresh stubs will still reference an old-path leaf.

2. **Upgrade before hand-editing.** `alis packages upgrade --all` and `alis packages install`
   re-sync `go.mod` server-side and will silently revert hand edits — run the CLI first,
   edit after. An upgrade run immediately after a define can resolve a stale "latest";
   re-run it.

3. **Rewrite the service's own imports**, keeping aliases:

   ```bash
   rg -l 'github.com/alis-build/public-go/' -g '*.go' -g go.mod . \
     | xargs sed -i '' 's|github.com/alis-build/public-go/|go.alis.build/common/|g'
   ```

   Pin the rewritten requires to post-rename versions (`go list -m -versions <module>`, or
   `@latest`). Pre-rename versions fail under the new path — their go.mod declares the old one.

4. **Bump any remaining stale `alis.build/...` pins.** If a direct `go get` cannot reach the
   private registry, resolve from the module cache; generated modules have an empty
   `require ()`, so `go get` their vanity requirements (step 3) before the cache-only bump:

   ```bash
   GOPRIVATE='alis.build/*' GOFLAGS=-mod=mod GOPROXY=off go get alis.build/<...>@<version>
   ```

5. **Verify the whole graph, including tests** — stale pins hide in test-only dependencies:

   ```bash
   go list -deps ./...       | grep github.com/alis-build/public-go   # must be empty
   go list -test -deps ./... | grep github.com/alis-build/public-go   # must be empty
   go build ./...
   ```

   If `go mod tidy` fails on an unrelated `google.golang.org/genproto` split error from a
   dependency's tests, skip tidy and rely on explicit `go get` plus the checks above.

### Known legacy lineage

A third copy of the same protos exists under `open.alis.services/protobuf/...` (the old
artifact pipeline). Some shared libraries — at the time of writing `go.alis.build/authz`,
pulled in by `go.alis.build/testing` — still import it. When those enter only through test
helpers, the deployed binary is unaffected but `go test` panics with the registration
conflict; that library must migrate before such tests pass. Do not try to fix it from the
consuming service.
