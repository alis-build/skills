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
it with dots in your requirements file(s) to match the proto `package`.

Served from the product's **`define-python`** Artifact Registry repository:

```
https://<region>-python.pkg.dev/<product-project>/define-python/simple/
```

**Import root = proto `package` = pip package name.** There is no monolith prefix. Generated
`*_pb2.py` / `*_pb2_grpc.py` modules live under that package directory.

### Package layout and barrel exports

All **`define-python` packages** — per-neuron (`<org>.<product>.<neuron>.v1`), cross-product
neurons, and open/common stubs (`<org>.open.<area>.v1`, `google.type`, …) — share the same
installed layout:

| Directory                                                 | `__init__.py` role                                          |
| --------------------------------------------------------- | ----------------------------------------------------------- |
| Parent segments (e.g. `<org>`, `<org>.open`, …)           | Namespace only: `declare_namespace(__name__)`               |
| Leaf proto package (the pip package / `focus_package_id`) | **Barrel** — re-exports every `*_pb2` / `*_pb2_grpc` module |

Open stubs are not a different import scheme — only the legacy monolith **prefix** and **pip
requirement line** change during migration.

Leaf barrel shape (generated — do not hand-edit):

```python
from . import <file>_pb2 as <file>_pb2
from . import <file>_pb2_grpc as <file>_pb2_grpc

__all__ = [
    "<file>_pb2",
    "<file>_pb2_grpc",
]
```

**Preferred imports** use the barrel — import modules from the proto package:

```python
# Per-neuron
from <org>.<product>.<neuron>.v1 import <file>_pb2 as pb
from <org>.<product>.<neuron>.v1 import <file>_pb2_grpc as pb_grpc

# Open / common stub — same pattern
from <org>.open.<area>.v1 import <file>_pb2 as pb
from <org>.open.<area>.v1 import <file>_pb2_grpc as pb_grpc
```

Message and enum types live on the `*_pb2` module:

```python
from <org>.open.<area>.v1 import <file>_pb2 as pb
from <org>.open.<area>.v1.<file>_pb2 import <MessageType>   # direct submodule — also valid
# use pb.<MessageType>, etc.
```

The barrel re-exports **proto modules** (`*_pb2`, `*_pb2_grpc`), not individual message classes.
Do not expect `from <focus_package_id> import <MessageType>` to work.

**Inspect an installed package** (local venv, Docker build layer, or CI cache):

```bash
# Show installed files for the wheel
python -m pip show -f <focus_package_id>

# Read the barrel (site-packages path varies by platform / Python version)
python - <<'PY'
import importlib, inspect, os
pkg = importlib.import_module("<org>.<product>.<neuron>.v1")
print(os.path.dirname(inspect.getfile(pkg)))
print(open(inspect.getfile(pkg), encoding="utf-8").read())
PY
```

Leaf packages also ship `py.typed` and matching `__init__.pyi` / `*_pb2.pyi` stubs for type
checkers.

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

Cross-product neurons each get their own explicit pip requirement. They resolve from your own
product's `define-python` index when the owning product is accessible (the platform
distributes accessible products' packages there); add an `--extra-index-url` for the owning
product's `define-python` repo only when the package is not distributed into your index.

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

### Step 2 — Rewrite requirements

Requirements-file services declare private packages in one of two **valid target layouts**;
Poetry projects keep declaring them in `pyproject.toml` (see Step 5). `alis_requirements.txt`
is never required: default to the **embedded** layout, and use **split** only when
`alis_requirements.txt` already exists in the repo or the user asks for it. Keep the layout
the service already uses — do not split or merge files unless asked.

| Layout                 | Where private indexes + neuron packages live |
| ---------------------- | -------------------------------------------- |
| **Embedded** (default) | `requirements.txt` (alongside PyPI deps)     |
| **Split**              | `alis_requirements.txt`                      |

The Dockerfile install order for each layout lives in Step 4.

In both layouts:

- Replace registry suffix `protobuf-python-internal` with `define-python`.
- Drop org `protobuf-python` monolith indexes and monolith pip packages.
- Add one pinned requirement per neuron package (and per cross-product / public-stub package).
- Group each `--extra-index-url` with the packages that resolve from it — for readability
  only. pip applies every index option in a requirements file to the whole install; line
  order does not scope resolution. Version pins, not placement, control what gets picked.

**Embedded layout** (`requirements.txt`, the default) — PyPI deps first, then the private
index grouped with its packages:

```text
grpcio==<version>
protobuf==<version>

# Internal definitions
--extra-index-url https://<region>-python.pkg.dev/<product-project>/define-python/simple/
<focus_package_id>==<version>
<org>.open.<area>.v1==<version>
```

**Split layout** (`alis_requirements.txt`, only when pre-existing or requested):

```text
# Internal definitions
--extra-index-url https://<region>-python.pkg.dev/<product-project>/define-python/simple/
<focus_package_id>==<version>
<org>.open.<area>.v1==<version>

# Cross-product fallback — only when the package is not in your product's index:
--extra-index-url https://<region>-python.pkg.dev/<other-product-project>/define-python/simple/
<other-focus-package-id>==<version>
```

Cross-product neurons and open/common stubs each get an **explicit pip requirement** (same as
any imported package that is not your own neuron). They resolve from the same product
`define-python` index when the owning package is accessible to the product — add a separate
`--extra-index-url` only when the package is not distributed into your product's index.

If you migrate from split to embedded, delete the emptied `alis_requirements.txt`. In the
other direction `requirements.txt` still holds the PyPI deps — never delete it.

Pin versions explicitly during migration; use unpinned only after the graph is clean.

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

| Legacy shape                        | Typical install order                                                                                     | Migration action                                                                                                                                                              |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inline monolith**                 | `requirements.txt` → keyring → `pip install --index-url …/protobuf-python/simple/ alis-services-protobuf` | Remove the inline monolith `RUN`. Move the private index + packages into the existing `requirements.txt` (embedded layout — the default; create `alis_requirements.txt` only if the user asks for the split layout). Install keyring, then the requirements file(s).                                              |
| **Split (`alis_requirements.txt`)** | keyring → `alis_requirements.txt` → `requirements.txt`                                                    | Keep the order; update `alis_requirements.txt` contents. Remove any leftover inline monolith `RUN`.                                                                           |
| **Embedded (`requirements.txt`)**   | keyring → `requirements.txt` (file contains `--extra-index-url` + monolith packages)                      | Keep the single-file layout; update index URLs and packages in `requirements.txt`. Remove any leftover inline monolith `RUN`. Delete unused `alis_requirements.txt` if empty. |

**Target install order** — depends on layout:

| Layout                 | Dockerfile steps after `COPY`                                 |
| ---------------------- | ------------------------------------------------------------- |
| **Embedded** (default) | keyring + auth → `requirements.txt`                           |
| **Split**              | keyring + auth → `alis_requirements.txt` → `requirements.txt` |

In both cases:

1. `COPY` application source.
2. Ensure `setuptools` is installed: the generated namespace `__init__.py` files call
   `pkg_resources.declare_namespace`, and Python 3.12+ venvs and images no longer bundle
   `setuptools`. Services commonly pin `setuptools<81` because newer releases deprecate
   `pkg_resources`.
3. Install **`keyring`** and **`keyrings.google-artifactregistry-auth`** from PyPI in their
   own step before any private-index install. pip authenticates to the private index through
   the keyring backend, so the backend must already be installed when that install starts —
   a requirements-file entry alone installs it too late to authenticate that same install.
4. Install the requirements file(s) for your layout (see table above). Private indexes and
   per-neuron packages live in the requirements file — as `--extra-index-url` lines, not as
   separate Dockerfile `RUN pip install --index-url …` commands.

Registry URL changes (`protobuf-python-internal` → `define-python`, dropping org
`protobuf-python` / `openprotos-python` indexes) belong in the **requirements file that holds
private packages** (`alis_requirements.txt` or `requirements.txt`), not in Dockerfile `RUN`s.

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
# After — per-neuron shape (embedded layout, default)
RUN pip3 install keyring keyrings.google-artifactregistry-auth
RUN pip3 install -r requirements.txt --no-cache
```

```dockerfile
# After — per-neuron shape (split layout)
RUN pip3 install keyring keyrings.google-artifactregistry-auth
RUN pip3 install -r alis_requirements.txt --no-cache
RUN pip3 install -r requirements.txt --no-cache
```

When the Dockerfile already matches your chosen layout, the install block often needs **no
structural change** — only the requirements file contents and removal of any stray inline
monolith install.

**Protobuf runtime version:** newer `define-python` packages may require a newer `protobuf`
major than your existing pins. After installing requirements, check for version conflicts.
Some services add an explicit pin, e.g. `pip install --upgrade --no-deps protobuf==<version>`,
once the dependency tree resolves. Only add this when the build or an import-time check fails —
do not pin preemptively.

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
```

Then, embedded layout (default):

```bash
pip install -r requirements.txt
```

Or split layout:

```bash
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

The public-stubs **invariant** lives in [`SKILL.md`](../SKILL.md). On Python, open and split
common packages are ordinary **`define-python` wheels** — same barrel layout, pip name =
proto `package`, and import paths documented above. Migration is:

1. Drop the legacy monolith prefix from imports.
2. Add an explicit pip requirement for each imported package.
3. Drop legacy monolith pip sources (`google-common-protos`, `openprotos-python`, etc.).

### Legacy sources

| Legacy source              | Typical pip / registry                   | Typical import                                                       |
| -------------------------- | ---------------------------------------- | -------------------------------------------------------------------- |
| Alis google monolith       | `google-common-protos`                   | `from google.type import date_pb2`                                   |
| Open monolith              | `openprotos-python` registry + org index | `from alis_services_protobuf.<org>.open.<area>.v1 import <file>_pb2` |
| Product monolith re-export | via `alis-services-protobuf`             | `from alis_services_protobuf.<org>.open.<area>.v1 import <file>_pb2` |

### Target (same as per-neuron)

| Proto package          | Pip package            | Import                                        |
| ---------------------- | ---------------------- | --------------------------------------------- |
| `google.type`          | `google.type`          | `from google.type import date_pb2`            |
| `google.rpc`           | `google.rpc`           | `from google.rpc import code_pb2`             |
| `google.longrunning`   | `google.longrunning`   | `import google.longrunning.operations_pb2`    |
| `<org>.open.<area>.v1` | `<org>.open.<area>.v1` | `from <org>.open.<area>.v1 import <file>_pb2` |

**Import rewrite:**

```python
# Before
from alis_services_protobuf.<org>.open.<area>.v1 import <file>_pb2

# After — same barrel import as any other define-python package
from <org>.open.<area>.v1 import <file>_pb2
```

**Explicit dependencies:** list every imported open/common/neuron package in your requirements
file, after the `--extra-index-url` it resolves from. A package's `METADATA` may declare further
`define-python` deps (e.g. `<org>.open.<area>.v1` requiring `google.type`) — add those too if
import fails. Remove unused imports instead of adding packages you do not need.

**`google-common-protos`:** this Alis-managed monolith overlaps split `google.*` packages. Do
not install it alongside split packages — same registration conflict as Go/JS. Keep
**`googleapis-common-protos`** (PyPI) only when you also need standard Google API client protos;
it does not replace Alis split packages.

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
- [ ] Private indexes use `define-python`, not `protobuf-python-internal` (in whichever file holds them).
- [ ] Monolith pip packages removed; one requirement per neuron (+ cross-product / public stubs).
- [ ] Imports rewritten (monolith prefix dropped where present); unused stub imports removed.
- [ ] Dockerfile matches chosen layout (embedded by default; split only if pre-existing or requested); inline monolith `RUN` removed; both `keyring` and `keyrings.google-artifactregistry-auth` installed before private indexes.
- [ ] Public stubs migrated off `google-common-protos` / `alis_services_protobuf.<org>.open.*`.
- [ ] Local venv install succeeds; server module imports cleanly.
