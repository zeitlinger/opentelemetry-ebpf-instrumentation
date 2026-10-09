#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Render the OBI telemetry reference (attributes + metrics + spans) from the
# semantic-convention registry under `schemas/obi/` into `site/docs/`, which is
# published to GitHub Pages by publish-schemas.yml.
#
# Rendering goes through `weaver registry resolve` plus scripts/schema-docs.jq
# rather than `weaver registry generate`, because generation aborts on the
# duplicate-attribute diagnostics produced by OBI's `x.obi.*` override groups —
# the same expected findings scripts/lint-schema-filter.jq allowlists for
# `registry check`. Resolve still emits the complete resolved registry alongside
# those diagnostics, so we filter and render it ourselves. This can move to
# `registry generate` with a template set once weaver defines override semantics
# between a registry and its dependencies
# (https://github.com/open-telemetry/weaver/issues/1578).
#
# Those same duplicates make resolution non-deterministic for the overridden
# attributes: weaver may pick either the upstream or the OBI description between
# runs, so regenerating can produce a small diff with no registry change. That is
# why the output is not verified byte-for-byte in CI.
#
# The registry declares the upstream semconv registry as a dependency, resolved
# from the prefetched copy under schemas/obi/.deps (see
# scripts/fetch-upstream-semconv.sh). Weaver resolves that path relative to the
# working directory.
#
# Usage: generate-schema-docs.sh <registry-dir> [output-dir]
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $(basename "$0") <registry-dir> [output-dir]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$(cd "$1" && pwd)"
TARGET="${2:-$ROOT/site/docs}"
JQ_PROGRAM="$ROOT/scripts/schema-docs.jq"

resolved=$(mktemp)
trap 'rm -f "$resolved"' EXIT

# `--include-unreferenced` keeps OBI's standalone override and marker groups in
# the resolution. Weaver exits non-zero because of the expected duplicate
# diagnostics, so validity is judged by the payload, not the exit code.
#
# live-check resolves without the flag, so these pages are deliberately a
# superset of the enforced contract: a group no signal references is
# documented here but is not something live-check can hold OBI to. The
# alternative — dropping the flag — would leave those groups undocumented,
# which is worse for a reference whose job is to describe what OBI declares.
(cd "$REGISTRY" && weaver registry resolve \
    --registry "$REGISTRY" \
    --include-unreferenced \
    --format json) > "$resolved" 2>/dev/null || true

if ! jq -e '.groups | length > 0' "$resolved" >/dev/null 2>&1; then
  echo "generate-schema-docs: weaver registry resolve produced no usable registry" >&2
  exit 1
fi

mkdir -p "$TARGET"
for page in readme attributes metrics spans; do
  case "$page" in
    readme) out="README.md" ;;
    *) out="$page.md" ;;
  esac
  jq -r --arg page "$page" -f "$JQ_PROGRAM" "$resolved" > "$TARGET/$out"
done

echo "generate-schema-docs: rendered README.md attributes.md metrics.md spans.md into $TARGET"
