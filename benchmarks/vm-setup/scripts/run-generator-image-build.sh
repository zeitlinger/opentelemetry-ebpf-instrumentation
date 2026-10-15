#!/usr/bin/env bash
set -uo pipefail
root=/home/gregor/obi-bench/task3
repo="$root/runs/mise-branch"
export MISE_DATA_DIR="$root/runs/mise-data" MISE_CACHE_DIR="$root/runs/mise-cache"
export GOMODCACHE="$root/runs/gomodcache" GOCACHE="$root/runs/gocache"
export GENERATOR_OCI_LAYOUT="$root/generator-image-layout"
log="$root/generator-image-build-retry.log"
status="$root/generator-image-build-retry.metrics"
cd "$repo"
printf 'start_utc=%s\n' "$(date -u +%FT%TZ)" > "$status"
start=$(date +%s%N)
mise run generator-image-build > "$log" 2>&1
rc=$?
end=$(date +%s%N)
printf 'build_exit=%s\nbuild_duration_ns=%s\nend_utc=%s\n' "$rc" "$((end-start))" "$(date -u +%FT%TZ)" >> "$status"
if [[ -f "$GENERATOR_OCI_LAYOUT/index.json" ]]; then
  printf 'oci_index_sha256=%s\noci_layout_bytes=%s\n' \
    "$(sha256sum "$GENERATOR_OCI_LAYOUT/index.json" | cut -d' ' -f1)" \
    "$(du -sb "$GENERATOR_OCI_LAYOUT" | cut -f1)" >> "$status"
fi
exit "$rc"
