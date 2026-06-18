#!/usr/bin/env bash
# resolve-alis-workspace.sh — Resolve Alis Build workspace context from the
# filesystem. Outputs fields compatible with alis.os.context.v1.Context.
#
# Usage:
#   bash scripts/resolve-alis-workspace.sh [--json] [--cwd PATH] [--help]
#
# Requires: bash 4+, jq
# Does not call Alis Build MCP — use MCP for authoritative neuron lists,
# environments, and when not on disk under ~/alis.build.
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CWD="${PWD}"
JSON=0

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: resolve-alis-workspace.sh [--json] [--cwd PATH] [--help]

Resolve Alis Build workspace paths from the local filesystem.
Resolves as much context as the CWD depth allows — from just the root
directory up to a full neuron with build/define paths and playground.

Options:
  --json    Emit JSON on stdout (default: human-readable table)
  --cwd     Start discovery from PATH instead of the current directory
  --help    Show this help

Stdout: resolved context (JSON or text)
Stderr: diagnostics

Path conventions:
  Build:  ~/alis.build/{org}/build/{product}/{neuron_path...}/
  Define: ~/alis.build/{org}/define/{org}/{product}/{neuron_path...}/
  Infra:  <neuron_build_root>/infra/

For neuron lists, environments, and other platform data use Alis Build MCP.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  JSON=1; shift ;;
    --cwd)   CWD="${2:?--cwd requires a path}"; shift 2 ;;
    --help)  usage; exit 0 ;;
    *)       echo "Error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Gate: CWD must be under ~/alis.build
# ---------------------------------------------------------------------------
ALIS_HOME="${HOME}/alis.build"
if [[ ! -d "$ALIS_HOME" ]]; then
  echo "Error: ~/alis.build does not exist." >&2
  exit 1
fi

# Resolve physical paths for the containment check, but emit logical paths
# so output matches the user's ~/alis.build even when it is a symlink.
ALIS_HOME_REAL="$(cd "$ALIS_HOME" && pwd -P)"
RESOLVED_CWD_REAL="$(cd "$CWD" && pwd -P)"

if [[ "$RESOLVED_CWD_REAL" != "$ALIS_HOME_REAL"/* && "$RESOLVED_CWD_REAL" != "$ALIS_HOME_REAL" ]]; then
  echo "Error: CWD must be under ~/alis.build (resolved: $RESOLVED_CWD_REAL)" >&2
  exit 1
fi

# Rewrite CWD into the logical ALIS_HOME prefix.
RESOLVED_CWD="${ALIS_HOME}${RESOLVED_CWD_REAL#"$ALIS_HOME_REAL"}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Walk up from a starting directory looking for an infra/ child.
# Stops at (and excludes) $stop_at. Prints the match or returns 1.
find_neuron_root() {
  local p="$1" stop_at="$2"
  while [[ "$p" != "$stop_at" && "$p" == "$stop_at"/* ]]; do
    if [[ -d "$p/infra" ]]; then
      echo "$p"
      return 0
    fi
    p="$(dirname "$p")"
  done
  return 1
}

# ---------------------------------------------------------------------------
# Progressive parsing — resolve as much as the path depth allows
# ---------------------------------------------------------------------------
# Depth levels relative to ALIS_HOME:
#   0: ~/alis.build                       → root only
#   1: ~/alis.build/{org}                 → organisation
#   2: ~/alis.build/{org}/build|define    → organisation + repo kind
#   3+: depends on repo kind              → product, then neuron

ORG_ID=""
REPO_KIND=""
PRODUCT_ID=""
NEURON_PATH=""
BUILD_PRODUCT_ROOT=""
DEFINE_PRODUCT_ROOT=""

# Split the path below ALIS_HOME into segments.
REL="${RESOLVED_CWD#"$ALIS_HOME"}"
REL="${REL#/}"  # strip leading slash; empty if CWD == ALIS_HOME

if [[ -n "$REL" ]]; then
  IFS='/' read -ra SEGS <<< "$REL"
else
  SEGS=()
fi
DEPTH=${#SEGS[@]}

# --- Level 1: organisation ---
if [[ $DEPTH -ge 1 ]]; then
  ORG_ID="${SEGS[0]}"
fi

# --- Level 2: repo kind (build / define) ---
if [[ $DEPTH -ge 2 ]]; then
  REPO_KIND="${SEGS[1]}"
  if [[ "$REPO_KIND" != "build" && "$REPO_KIND" != "define" ]]; then
    REPO_KIND=""
  fi
fi

# --- Level 3+: product and neuron ---
if [[ -n "$REPO_KIND" ]]; then
  case "$REPO_KIND" in
    build)
      # build layout: {org}/build/{product}/{neuron_path...}
      if [[ $DEPTH -ge 3 ]]; then
        PRODUCT_ID="${SEGS[2]}"
        BUILD_PRODUCT_ROOT="$ALIS_HOME/$ORG_ID/build/$PRODUCT_ID"
        DEFINE_PRODUCT_ROOT="$ALIS_HOME/$ORG_ID/define/$ORG_ID/$PRODUCT_ID"

        if [[ $DEPTH -ge 4 ]]; then
          # Try to find neuron root (parent of infra/) by walking up from CWD
          NEURON_ROOT="$(find_neuron_root "$RESOLVED_CWD" "$BUILD_PRODUCT_ROOT" || true)"
          if [[ -n "$NEURON_ROOT" ]]; then
            NEURON_PATH="${NEURON_ROOT#"${BUILD_PRODUCT_ROOT}"/}"
          fi
        fi
      fi
      ;;
    define)
      # define layout: {org}/define/{org}/{product}/{neuron_path...}
      #   SEGS: [org, define, org, product, ...]
      if [[ $DEPTH -ge 4 ]]; then
        PRODUCT_ID="${SEGS[3]}"
        BUILD_PRODUCT_ROOT="$ALIS_HOME/$ORG_ID/build/$PRODUCT_ID"
        DEFINE_PRODUCT_ROOT="$ALIS_HOME/$ORG_ID/define/$ORG_ID/$PRODUCT_ID"

        if [[ $DEPTH -ge 5 ]]; then
          local_segs=("${SEGS[@]:4}")
          NEURON_PATH="$(IFS='/'; echo "${local_segs[*]}")"
        fi
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Derive neuron id from the path (replace / with -)
# e.g. agents/users/v1 → agents-users-v1
# ---------------------------------------------------------------------------
FOCUS_NEURON_ID=""
if [[ -n "$NEURON_PATH" ]]; then
  FOCUS_NEURON_ID="${NEURON_PATH//\//-}"
fi

# ---------------------------------------------------------------------------
# Resolve workstation paths (cross-resolve build ↔ define)
# ---------------------------------------------------------------------------
NEURON_BUILD_ROOT=""
NEURON_DEFINE_ROOT=""
INFRA=""
PLAYGROUND=""

if [[ -n "$NEURON_PATH" && -n "$BUILD_PRODUCT_ROOT" ]]; then
  NEURON_BUILD_ROOT="$BUILD_PRODUCT_ROOT/$NEURON_PATH"
fi
if [[ -n "$NEURON_PATH" && -n "$DEFINE_PRODUCT_ROOT" ]]; then
  NEURON_DEFINE_ROOT="$DEFINE_PRODUCT_ROOT/$NEURON_PATH"
fi
if [[ -n "$NEURON_BUILD_ROOT" ]]; then
  INFRA_PATH="$NEURON_BUILD_ROOT/infra"
  if [[ -d "$INFRA_PATH" ]]; then
    INFRA="$INFRA_PATH"
  fi
  PLAYGROUND_PATH="$NEURON_BUILD_ROOT/.playground"
  if [[ -d "$PLAYGROUND_PATH" ]]; then
    PLAYGROUND="$PLAYGROUND_PATH"
  fi
fi

# ---------------------------------------------------------------------------
# Build resource names (only what we have)
# ---------------------------------------------------------------------------
ORGANISATION=""
PRODUCT=""
FOCUS_NEURON_NAME=""
NEURONS_JSON="[]"

if [[ -n "$ORG_ID" ]]; then
  ORGANISATION="organisations/$ORG_ID"
fi
if [[ -n "$ORG_ID" && -n "$PRODUCT_ID" ]]; then
  PRODUCT="organisations/$ORG_ID/products/$PRODUCT_ID"
fi
if [[ -n "$FOCUS_NEURON_ID" && -n "$PRODUCT" ]]; then
  FOCUS_NEURON_NAME="$PRODUCT/neurons/$FOCUS_NEURON_ID"
  NEURONS_JSON="$(echo "$FOCUS_NEURON_NAME" | jq -R . | jq -s .)"
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
null_or_str() { [[ -n "$1" ]] && echo "\"$1\"" || echo "null"; }

if [[ $JSON -eq 1 ]]; then
  BUILD_REPOS="[]"
  DEFINE_REPOS="[]"
  if [[ -n "$NEURON_BUILD_ROOT" && -d "$NEURON_BUILD_ROOT" ]]; then
    BUILD_REPOS="$(echo "$NEURON_BUILD_ROOT" | jq -R . | jq -s .)"
  fi
  if [[ -n "$NEURON_DEFINE_ROOT" ]]; then
    DEFINE_REPOS="$(echo "$NEURON_DEFINE_ROOT" | jq -R . | jq -s .)"
  fi

  jq -n \
    --arg organisation "$ORGANISATION" \
    --arg organisation_id "$ORG_ID" \
    --arg product "$PRODUCT" \
    --arg product_id "$PRODUCT_ID" \
    --arg focus_neuron "$FOCUS_NEURON_NAME" \
    --arg focus_neuron_id "$FOCUS_NEURON_ID" \
    --argjson neurons "$NEURONS_JSON" \
    --arg root_directory "$ALIS_HOME" \
    --argjson define_repos "$DEFINE_REPOS" \
    --argjson build_repos "$BUILD_REPOS" \
    --arg infra "$INFRA" \
    --arg playground "$PLAYGROUND" \
    '{
      organisation: (if $organisation == "" then null else $organisation end),
      organisation_id: (if $organisation_id == "" then null else $organisation_id end),
      product: (if $product == "" then null else $product end),
      product_id: (if $product_id == "" then null else $product_id end),
      focus_neuron: (if $focus_neuron == "" then null else $focus_neuron end),
      focus_neuron_id: (if $focus_neuron_id == "" then null else $focus_neuron_id end),
      neurons: $neurons,
      workstations: {
        root_directory: $root_directory,
        define_repos: $define_repos,
        build_repos: $build_repos,
        infra: (if $infra == "" then null else $infra end),
        playground: (if $playground == "" then null else $playground end)
      }
    }'
else
  echo "organisation:                    ${ORGANISATION:-(not resolved)}"
  echo "organisation_id:                 ${ORG_ID:-(not resolved)}"
  echo "product:                         ${PRODUCT:-(not resolved)}"
  echo "product_id:                      ${PRODUCT_ID:-(not resolved)}"
  echo "focus_neuron:                    ${FOCUS_NEURON_NAME:-(not resolved)}"
  echo "focus_neuron_id:                 ${FOCUS_NEURON_ID:-(not resolved)}"
  echo "workstations.root_directory:     $ALIS_HOME"
  echo "workstations.build_repos:        ${NEURON_BUILD_ROOT:-(not resolved)}"
  echo "workstations.define_repos:        ${NEURON_DEFINE_ROOT:-(not resolved)}"
  echo "workstations.infra:              ${INFRA:-(not resolved)}"
  echo "workstations.playground:         ${PLAYGROUND:-(not resolved)}"
fi
