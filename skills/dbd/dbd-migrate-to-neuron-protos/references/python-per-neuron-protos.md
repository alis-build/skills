# Python per-neuron proto migration

Follow [`SKILL.md`](../SKILL.md) for when to use this skill, migration root rules, the
mapping rule, and the public-stubs invariant. This document is the **Python procedure**.

Python migration is **manual** — there is no `alis packages install` automation yet. The steps
mirror Go: swap requirements, update registry URLs, rewrite imports, and drop legacy monolith
packages.

---

## Legacy generations

Python services may sit in any of these states. Inventory both **requirements** and **imports**
before migrating.

| Generation                | Artifact Registry repo          | Typical pip packages                                                                                                                | Typical import prefix                                                      |
| ------------------------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Org monolith              | `protobuf-python` (org project) | `alis-services-protobuf`                                                                                                            | `alis_services_protobuf.<proto-package>`                                   |
| Product internal monolith | `protobuf-python-internal`      | `alis-services-protobuf-internal-<product>`, `alis_services_protobuf_internal_<product>`, `<org>-build-protobuf-internal-<product>` | `alis_services_protobuf.<proto-package>` **or** `<proto-package>` directly |
| Per-neuron (target)       | `define-python`                 | `<focus_package_id>` verbatim (e.g. `<org>.<product>.<neuron>.v1`)                                                                  | `<focus_package_id>` (same as proto `package`)                             |

**Signals you are still on a legacy generation:**

```bash
pwd
rg -n 'alis_services_protobuf\.|alis-services-protobuf|alis_services_protobuf_internal|build-protobuf-internal' \
  -g '*.py' -g 'requirements*.txt' -g 'alis_requirements.txt' -g 'pyproject.toml' -g 'Dockerfile*' .
rg -n 'protobuf-python-internal|protobuf-python/simple' \
  -g 'requirements*.txt' -g 'alis_requirements.txt' -g 'pyproject.toml' -g 'Dockerfile*' .
```

---

## Per-neuron package naming

Target pip package: **`<focus_package_id>` verbatim** (dots kept). Pip normalizes the name to
hyphens on install (`<org>.<product>.<neuron>.v1` → `<org>-<product>-<neuron>-v1`), but declare
it with dots in `alis_requirements.txt` / `pyproject.toml` to match the proto `package`.

Served from the product's **`define-python`** Artifact Registry repository:

```
https://<region>-python.pkg.dev/<product-project>/define-python/simple/
```

**Import root = proto `package` = pip package name.** There is no monolith prefix and no extra
subpath — generated modules live directly under the proto package:

```python
from <org>.<product>.<neuron>.v1 import <file>_pb2 as pb
from <org>.<product>.<neuron>.v1 import <file>_pb2_grpc as pb_grpc
```

### Mapping rule (product packages)

Strip the legacy monolith prefix and map each distinct neuron to its own pip package.

| Legacy import prefix                                            | New import prefix                   | Pip package                         |
| --------------------------------------------------------------- | ----------------------------------- | ----------------------------------- |
| `alis_services_protobuf.internal.<org>.<product>.<neuron>.v2`   | `<org>.<product>.<neuron>.v2`       | `<org>.<product>.<neuron>.v2`       |
| `alis_services_protobuf.<org>.<other-product>.<neuron>.v1`      | `<org>.<other-product>.<neuron>.v1` | `<org>.<other-product>.<neuron>.v1` |
| `alis_services_protobuf.internal.<org>.<product>.<resource>.v1` | `<org>.<product>.<resource>.v1`     | `<org>.<product>.<resource>.v1`     |

When the service already imports at the proto root (common with product internal monoliths), only
the **pip requirement** changes — imports stay the same:

```python
# Already correct after dropping the monolith requirement:
from <org>.<product>.<neuron>.v1 import <file>_pb2 as pb
```

Cross-product neurons each get their own pip package and `--extra-index-url` for the owning
product's `define-python` repo (same pattern as Go's multi-entry `GOPROXY`).

---

## Procedure

### Step 1 — Inventory

Under the migration root, collect:

1. Every legacy import (`alis_services_protobuf.*` or imports that depend on a monolith pip
   package).
2. Every legacy pip package in `alis_requirements.txt`, `requirements.txt`, or `pyproject.toml`.
3. Every `--extra-index-url` pointing at `protobuf-python-internal` or org-level
   `protobuf-python`.
4. Every cross-product neuron imported (each becomes its own pip package + registry URL).
5. Every open/common stub import (`alis_services_protobuf.<org>.open.*`, `google-common-protos`).

Map each distinct neuron path to its `focus_package_id` pip package using the table in
[`SKILL.md`](../SKILL.md).

### Step 2 — Rewrite `alis_requirements.txt`

Replace product registry suffixes:

| Before                               | After                                                        |
| ------------------------------------ | ------------------------------------------------------------ |
| `protobuf-python-internal`           | `define-python`                                              |
| org `protobuf-python` monolith index | per-neuron `define-python` indexes for each imported product |

Drop monolith pip packages. Add one line per neuron package:

```text
# Internal definitions
--extra-index-url https://<region>-python.pkg.dev/<product-project>/define-python/simple/
<focus_package_id>==<version>

# Cross-product example (repeat per owning product):
--extra-index-url https://<region>-python.pkg.dev/<other-product-project>/define-python/simple/
<other-focus-package-id>==<version>
```

Pin versions explicitly during migration; use `@latest` / unpinned only after the graph is clean.

**Remove** legacy entries such as:

- `alis-services-protobuf`
- `alis-services-protobuf-internal-<product>`
- `alis_services_protobuf_internal_<product>`
- `<org>-build-protobuf-internal-<product>`

### Step 3 — Rewrite imports

For monolith-prefixed imports, drop the prefix:

```python
# Before
from alis_services_protobuf.internal.<org>.<product>.<neuron>.v2 import <file>_pb2 as pb

# After
from <org>.<product>.<neuron>.v2 import <file>_pb2 as pb
```

Keep existing aliases (`as pb`, `as pb_grpc`) — generated type names are unchanged.

Run a bulk replace only after confirming the inventory; some services mix prefixed and
already-correct imports.

### Step 4 — Update Dockerfiles

Find every Dockerfile under the migration root:

```bash
rg --files -g 'Dockerfile*' .
```

Legacy Python Dockerfiles fall into **three shapes**. Inspect the file before editing — do not
assume it already installs `alis_requirements.txt`.

| Legacy shape                       | Typical install order                                                                                     | Migration action                                                                                                                                                                |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inline monolith**                | `requirements.txt` → keyring → `pip install --index-url …/protobuf-python/simple/ alis-services-protobuf` | Remove the inline monolith `RUN`. Add keyring (if missing) then `alis_requirements.txt` **before** `requirements.txt`.                                                          |
| **`alis_requirements.txt`**        | keyring → `alis_requirements.txt` → `requirements.txt`                                                    | Keep the order; update `alis_requirements.txt` contents (`define-python` indexes, per-neuron packages). Remove any leftover inline monolith `RUN`.                              |
| **Embedded in `requirements.txt`** | keyring → `requirements.txt` (file contains `--extra-index-url` + monolith packages)                      | Move Alis index lines and packages into `alis_requirements.txt`; leave PyPI deps in `requirements.txt`. Adopt the keyring → `alis_requirements.txt` → `requirements.txt` order. |

**Target install order** (all shapes converge here):

1. `COPY` application source.
2. Optionally upgrade `setuptools` / `pip` (common but not required).
3. Install **`keyring`** and **`keyrings.google-artifactregistry-auth`** from PyPI — required so
   pip can authenticate to private Artifact Registry indexes.
4. `pip install -r alis_requirements.txt` — private indexes and per-neuron packages live here
   (`--extra-index-url` lines are in the file, not duplicated as Dockerfile `RUN`s).
5. `pip install -r requirements.txt` — public PyPI dependencies only.

Registry URL changes (`protobuf-python-internal` → `define-python`, dropping org
`protobuf-python` / `openprotos-python` indexes) belong in **`alis_requirements.txt`**, not as
separate `RUN pip install --index-url …` lines in the Dockerfile.

**Remove** legacy Dockerfile lines such as:

```dockerfile
# Inline org monolith — delete after migration
RUN pip3 install --index-url https://<region>-python.pkg.dev/<org-project>/protobuf-python/simple/ alis-services-protobuf
```

**Before → after** (placeholders: `<region>`, `<org-project>`, `<product-project>`):

```dockerfile
# Before — inline monolith shape
RUN pip3 install -r requirements.txt --no-cache
RUN pip3 install keyring
RUN pip3 install keyrings.google-artifactregistry-auth
RUN pip3 install --index-url https://<region>-python.pkg.dev/<org-project>/protobuf-python/simple/ alis-services-protobuf
```

```dockerfile
# After — per-neuron shape
RUN pip3 install keyring keyrings.google-artifactregistry-auth
RUN pip3 install -r alis_requirements.txt --no-cache
RUN pip3 install -r requirements.txt --no-cache
```

When the Dockerfile already uses `alis_requirements.txt`, the install block often needs **no
structural change** — only the file contents and removal of any stray inline monolith install.

**Protobuf runtime version:** newer `define-python` packages may require a newer `protobuf`
major than your existing `requirements.txt` pins. After installing both requirement files,
check for version conflicts. Some services add an explicit pin, e.g.
`pip install --upgrade --no-deps protobuf==<version>`, once the dependency tree resolves. Only
add this when the build or an import-time check fails — do not pin preemptively.

**Optional build-time import check** (recommended when migrating a gRPC server):

```dockerfile
RUN python -c "import <server-module>"   # e.g. import methods, import server
```

### Step 5 — Install locally

There is no CLI installer for Python yet. From the migration root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install keyring keyrings.google-artifactregistry-auth
pip install -r alis_requirements.txt
pip install -r requirements.txt
```

For Poetry projects, replace the legacy `[[tool.poetry.source]]` pointing at
`protobuf-python` with an explicit source for `define-python` and declare each neuron package
under `[tool.poetry.dependencies]` using the dotted `focus_package_id`.

### Step 6 — Drop legacy dependencies

Once no Python file imports through a monolith prefix and requirements no longer reference
monolith packages, remove:

- `--extra-index-url .../protobuf-python-internal/...`
- `--extra-index-url .../protobuf-python/simple/` (org monolith)
- `--extra-index-url .../openprotos-python/simple/` (after public stubs are migrated — see below)
- Legacy pip packages (`alis-services-protobuf*`, `alis_services_protobuf*`, `*-protobuf-internal-*`)

---

## Public stubs migration (Python)

The public-stubs **invariant** and symptom list live in [`SKILL.md`](../SKILL.md). Python has
three legacy sources for common/open protos:

| Legacy source              | Typical pip / registry                   | Typical import                                                       |
| -------------------------- | ---------------------------------------- | -------------------------------------------------------------------- |
| Alis google monolith       | `google-common-protos`                   | `from google.type import date_pb2`                                   |
| Open monolith              | `openprotos-python` registry + org index | `from alis_services_protobuf.<org>.open.<area>.v1 import <file>_pb2` |
| Product monolith re-export | via `alis-services-protobuf`             | `from alis_services_protobuf.<org>.open.<area>.v1 import <file>_pb2` |

**Target:** one pip package per proto `package`, named **`<proto-package>` verbatim** (same
rule as per-neuron packages):

| Proto package          | Pip package            | Import                                        |
| ---------------------- | ---------------------- | --------------------------------------------- |
| `google.type`          | `google.type`          | `from google.type import date_pb2`            |
| `google.rpc`           | `google.rpc`           | `from google.rpc import code_pb2`             |
| `google.longrunning`   | `google.longrunning`   | `import google.longrunning.operations_pb2`    |
| `<org>.open.<area>.v1` | `<org>.open.<area>.v1` | `from <org>.open.<area>.v1 import <file>_pb2` |

Split public packages publish to **`define-python`** (org/common project) or their owning
registry — check where the package was defined. Declare each one explicitly in
`alis_requirements.txt` until pip dependency metadata on all generated packages pulls them in
transitively.

**Import rewrite** — drop the monolith prefix for open stubs:

```python
# Before
from alis_services_protobuf.<org>.open.<area>.v1 import <file>_pb2

# After
from <org>.open.<area>.v1 import <file>_pb2
```

**`google-common-protos`:** this Alis-managed monolith overlaps the split `google.*`
packages. Do not install it alongside split packages — same registration conflict as Go/JS.
Replace it with the individual split packages your imports need (`google.type`, `google.rpc`,
`google.longrunning`, …). Keep **`googleapis-common-protos`** (PyPI) only when you also need
standard Google API client protos it provides; it does not replace Alis split packages.

**Known gap:** per-neuron packages may declare dependencies on split public packages that are
not yet published or not yet wired into pip metadata. If imports fail with `ModuleNotFoundError`
for a split `<org>.open.*` or `google.*` package, add that package explicitly to
`alis_requirements.txt` and pin a version from the owning `define-python` registry.

---

## Verify

1. **No legacy plumbing remains:**

   ```bash
   rg -n 'alis_services_protobuf\.|alis-services-protobuf|alis_services_protobuf_internal|build-protobuf-internal|protobuf-python-internal|protobuf-python/simple' \
     -g '*.py' -g 'requirements*.txt' -g 'alis_requirements.txt' -g 'pyproject.toml' -g 'Dockerfile*' .
   ```

   The command should return no matches.

2. **Imports resolve:**

   ```bash
   python -c "import <your.service.module>"   # or start the gRPC server module
   ```

3. **Tests compile** (if present):

   ```bash
   python -m pytest --collect-only .
   # or, for grpcio_testing suites:
   python -m unittest discover -s . -p '*_test.py'
   ```

4. **No mixed public-stub generations** — do not keep `google-common-protos` alongside split
   `google.*` packages. If startup fails with protobuf descriptor registration errors, audit
   for two pip packages exporting the same proto files.

---

## Quick checklist

- [ ] Legacy imports inventoried; each neuron mapped to `focus_package_id`.
- [ ] `alis_requirements.txt` uses `define-python` indexes, not `protobuf-python-internal`.
- [ ] Monolith pip packages removed; one requirement per neuron (+ cross-product / public stubs).
- [ ] Imports rewritten (monolith prefix dropped where present).
- [ ] Dockerfile uses keyring → `alis_requirements.txt` → `requirements.txt`; inline monolith `RUN` removed.
- [ ] Public stubs migrated off `google-common-protos` / `alis_services_protobuf.<org>.open.*`.
- [ ] Local venv install succeeds; server module imports cleanly.
