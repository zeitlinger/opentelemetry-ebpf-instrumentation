#!/usr/bin/env bash
set -euo pipefail
base="$HOME/obi-bench/task3"
out="$base/remeasure-bpf2go-prebuilt-20261014"
branch="$base/remeasure-final-20261014/branch"
main="$base/remeasure-final-20261014/main"
wrapper_dir="$out/docker-cache-wrapper"
mkdir -p "$out/logs" "$out/results" "$wrapper_dir"
[[ -f "$out/results/hash-comparison.txt" ]] || { echo "hash gate missing" >&2; exit 2; }
grep -q 'differing=0' "$out/results/hash-comparison.txt" || { echo "hash gate failed" >&2; exit 2; }
# Keep Make's docker-generate target unchanged while using the persistent named warm caches.
cat > "$wrapper_dir/docker" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == run ]]; then
  shift
  printf '%s\n' "docker run --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build" >> /home/gregor/obi-bench/task3/remeasure-bpf2go-prebuilt-20261014/logs/docker-wrapper-invocations.txt
  exec /usr/bin/docker run \
    --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod \
    --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build \
    "$@"
fi
exec /usr/bin/docker "$@"
WRAPPER
chmod +x "$wrapper_dir/docker"
export MISE_DATA_DIR="$base/runs/mise-data" MISE_CACHE_DIR="$base/runs/mise-cache"
export GOMODCACHE="$base/runs/gomodcache" GOCACHE="$base/runs/gocache"
mkdir -p "$GOMODCACHE" "$GOCACHE"
outputs=( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' -o -name '*_bpf*.go.d' )
find_generated() { find "$1/pkg" -type f \( "${outputs[@]}" \) "${@:2}"; }
{
  echo "date_utc=$(date -u +%FT%TZ)"
  echo "guest=$(hostname)"
  echo "uname=$(uname -a)"
  echo "cpu=$(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -1)"
  echo "cpus=$(nproc)"
  echo "memory=$(free -h | awk '/^Mem:/{print $2}')"
  echo "docker=$(docker version --format '{{.Server.Version}}')"
  echo "docker_generator=$(docker image inspect --format='{{.Id}}' ghcr.io/open-telemetry/obi-generator:0.2.17)"
  echo "docker_gomodcache_volume=obi-bpf-remeasure-gomodcache mounted at /go/pkg/mod"
  echo "docker_gocache_volume=obi-bpf-remeasure-gocache mounted at /tmp/go-build"
  echo "mise=$(mise --version | head -1)"
  echo "branch_go_pin=$(sed -n 's/^go = "\([^"]*\)"/\1/p' "$branch/mise.toml")"
  echo "branch_bpf2go_pin=$(grep -F 'go:github.com/cilium/ebpf/cmd/bpf2go' "$branch/mise.toml")"
  echo "branch_go=$(cd "$branch" && mise exec -- go version 2>&1 | tail -1)"
  echo "branch_gotoolchain=$(cd "$branch" && mise exec -- go env GOTOOLCHAIN 2>&1 | tail -1)"
  echo "docker_go=$(docker run --rm --entrypoint go ghcr.io/open-telemetry/obi-generator:0.2.17 version)"
  echo "docker_gotoolchain=$(docker run --rm --entrypoint go ghcr.io/open-telemetry/obi-generator:0.2.17 env GOTOOLCHAIN)"
  echo "mise_install_go_versions=$(find "$MISE_DATA_DIR/installs/go" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null || true)"
  echo "branch_source=feat/mise-full-build current snapshot at baseline path"
  echo "main_source=origin/main rebase base a6207d767125db2355710502542451cc4b474d96"
  echo "go_mod_cache_size=$(du -sh "$GOMODCACHE" | cut -f1)"
  echo "go_build_cache_size=$(du -sh "$GOCACHE" | cut -f1)"
  echo "output_hash_gate=$(cat "$out/results/hash-comparison.txt" | head -1)"
} > "$out/environment.txt"
# BPF source inputs must remain byte-identical to the earlier source snapshots.
for mode in branch main; do
  (cd "${!mode}" && find bpf -type f \( -name '*.c' -o -name '*.h' \) ! -path '*/tests/*' -print0 | sort -z | xargs -0 sha256sum) \
    | sed "s|${!mode}/||" > "$out/results/${mode}-bpf-inputs.sha256"
done
cmp "$out/results/branch-bpf-inputs.sha256" "$out/results/main-bpf-inputs.sha256"
# Untimed full warm-ups happen after tools/image and the shared caches are already present.
for mode in branch main; do
  dir="${!mode}"
  find_generated "$dir" -delete
  if [[ "$mode" == branch ]]; then (cd "$dir" && mise run generate) > "$out/logs/warmup-branch.log" 2>&1
  else (cd "$dir" && PATH="$wrapper_dir:$PATH" make docker-generate) > "$out/logs/warmup-main.log" 2>&1; fi
  count=$(find_generated "$dir" | wc -l)
  [[ "$count" -eq 90 ]] || { echo "expected 90 outputs after $mode warmup, got $count" >&2; exit 2; }
done
: > "$out/results/timings.csv"
echo 'path,kind,run,duration_ns,finished_utc' >> "$out/results/timings.csv"
for mode in branch main; do
  dir="${!mode}"
  for i in 1 2 3 4 5; do
    find_generated "$dir" -delete
    n=$(find_generated "$dir" | wc -l)
    [[ "$n" -eq 0 ]] || { echo "generated files remain before $mode full $i: $n" >&2; exit 2; }
    start=$(date +%s%N)
    if [[ "$mode" == branch ]]; then (cd "$dir" && mise run generate) > "$out/logs/${mode}-full-${i}.log" 2>&1
    else (cd "$dir" && PATH="$wrapper_dir:$PATH" make docker-generate) > "$out/logs/${mode}-full-${i}.log" 2>&1; fi
    end=$(date +%s%N)
    printf '%s,full,%s,%s,%s\n' "$mode" "$i" "$((end-start))" "$(date -u +%FT%TZ)" >> "$out/results/timings.csv"
    find_generated "$dir" -print0 | sort -z | xargs -0 sha256sum > "$out/results/${mode}-full-${i}.sha256"
    outputs_count=$(wc -l < "$out/results/${mode}-full-${i}.sha256")
    [[ "$outputs_count" -eq 90 ]] || { echo "expected 90 generated files but got $outputs_count on $mode full $i" >&2; exit 2; }
    start=$(date +%s%N)
    if [[ "$mode" == branch ]]; then (cd "$dir" && mise run generate) > "$out/logs/${mode}-noop-${i}.log" 2>&1
    else (cd "$dir" && PATH="$wrapper_dir:$PATH" make docker-generate) > "$out/logs/${mode}-noop-${i}.log" 2>&1; fi
    end=$(date +%s%N)
    printf '%s,noop,%s,%s,%s\n' "$mode" "$i" "$((end-start))" "$(date -u +%FT%TZ)" >> "$out/results/timings.csv"
    find_generated "$dir" -print0 | sort -z | xargs -0 sha256sum > "$out/results/${mode}-noop-${i}.sha256"
    cmp "$out/results/${mode}-full-${i}.sha256" "$out/results/${mode}-noop-${i}.sha256"
    echo "done $mode full/noop $i"
  done
done
{
  echo "branch_go_final=$(cd "$branch" && mise exec -- go version 2>&1 | tail -1)"
  echo "branch_go_env_gotoolchain=$(cd "$branch" && mise exec -- go env GOTOOLCHAIN 2>&1 | tail -1)"
  echo "branch_go_install_after=$(find "$MISE_DATA_DIR/installs/go" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tr '\n' ' ')"
  echo "go_toolchain_download_mentions=$(grep -Ehi 'downloading go1\.27\.[0-9]' "$out/logs"/*.log | wc -l)"
  echo "branch_generated_files=$(wc -l < "$out/results/branch-full-5.sha256")"
  echo "main_generated_files=$(wc -l < "$out/results/main-full-5.sha256")"
  echo "docker_gomodcache_volume_size=$(docker run --rm --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/mnt alpine:3.22 du -sh /mnt | cut -f1)"
  echo "docker_gocache_volume_size=$(docker run --rm --mount type=volume,src=obi-bpf-remeasure-gocache,target=/mnt alpine:3.22 du -sh /mnt | cut -f1)"
} > "$out/postflight.txt"
python3 - "$out/results/timings.csv" "$out/results/timing-summary.txt" <<'PY'
import csv, statistics, sys
from pathlib import Path
rows=list(csv.DictReader(open(sys.argv[1])))
with open(sys.argv[2],"w") as f:
 for path in ("branch","main"):
  for kind in ("full","noop"):
   values=[int(r["duration_ns"])/1e9 for r in rows if r["path"]==path and r["kind"]==kind]
   f.write(f"{path} {kind}: median={statistics.median(values):.3f}s range={min(values):.3f}-{max(values):.3f}s samples="+", ".join(f"{x:.3f}" for x in values)+"\n")
PY
sha256sum "$out"/environment.txt "$out"/source-state.txt "$out"/postflight.txt "$out"/results/* "$out"/logs/* "$out"/docker-cache-wrapper/docker > "$out/SHA256SUMS"
echo "completed: $out"
cat "$out/results/timing-summary.txt"
cat "$out/postflight.txt"
