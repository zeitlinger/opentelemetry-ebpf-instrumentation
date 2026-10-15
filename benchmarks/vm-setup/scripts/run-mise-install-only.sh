#!/usr/bin/env bash
set -euo pipefail
run_id=${1:?usage: run-mise-install-only.sh RUN_ID}
root=/home/gregor/obi-bench/task1
run="$root/setup-only/$run_id"
mkdir -p "$run"
cp -a "$root/sources/mise-branch" "$run/repo"
mkdir -p "$run/mise-data" "$run/mise-cache"
[[ -z "$(find "$run/mise-data" -mindepth 1 -print -quit)" && -z "$(find "$run/mise-cache" -mindepth 1 -print -quit)" ]]
cd "$run/repo"
export MISE_DATA_DIR="$run/mise-data" MISE_CACHE_DIR="$run/mise-cache"
{
 echo "run=$run_id"; echo "start_utc=$(date -u +%FT%TZ)"; echo "mise=$(mise --version | head -1)"; echo "initial_mise_data_cache=empty"
} > "$run/metrics.txt"
start=$(date +%s%N); rc=0
mise install > "$run/mise-install.log" 2>&1 || rc=$?
end=$(date +%s%N)
printf 'install_exit=%s\ninstall_duration_ns=%s\nend_utc=%s\n' "$rc" "$((end-start))" "$(date -u +%FT%TZ)" >> "$run/metrics.txt"
cat "$run/metrics.txt"
grep -E 'installed [0-9]+ tools|mise ✓|mise ERROR' "$run/mise-install.log" | tail -15 || true
exit "$rc"
