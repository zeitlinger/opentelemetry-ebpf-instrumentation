#!/usr/bin/env bash
set -euo pipefail
run_id=${1:?usage: run-mise-first-use.sh RUN_ID}
root=/home/gregor/obi-bench/task1
run="$root/runs/$run_id"
mkdir -p "$run"
if [[ -e "$run/repo" ]]; then echo "Refusing to overwrite $run/repo" >&2; exit 2; fi
cp -a "$root/sources/mise-branch" "$run/repo"
git -C "$run/repo" init -q
mkdir -p "$run/mise-data" "$run/mise-cache" "$run/gomodcache" "$run/gocache"
for d in mise-data mise-cache gomodcache gocache; do
  if [[ -n "$(find "$run/$d" -mindepth 1 -print -quit)" ]]; then echo "$d was not empty at start" >&2; exit 2; fi
done
outputs=$(find "$run/repo/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) | wc -l)
if [[ "$outputs" != 0 ]]; then echo "expected no generated files, found $outputs" >&2; exit 2; fi
{
  echo "run=$run_id"
  echo "commit=7a5f0146890090f312751f9cb14ceb4c5f32739f"
  echo "start_utc=$(date -u +%FT%TZ)"
  echo "host_mise=$(mise --version | head -1)"
  echo "host_docker=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
  echo "generated_outputs_before=$outputs"
  echo "mise_data_cache_initial=empty"
} > "$run/metrics.txt"
cd "$run/repo"
export MISE_DATA_DIR="$run/mise-data" MISE_CACHE_DIR="$run/mise-cache" GOMODCACHE="$run/gomodcache" GOCACHE="$run/gocache"
start=$(date +%s%N)
rc=0
mise run generate > "$run/mise-run.log" 2>&1 || rc=$?
end=$(date +%s%N)
printf 'task_exit=%s\ntask_duration_ns=%s\nend_utc=%s\n' "$rc" "$((end-start))" "$(date -u +%FT%TZ)" >> "$run/metrics.txt"
if [[ "$rc" == 0 ]]; then
  find pkg -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -print0 | sort -z | xargs -0 sha256sum > "$run/generated-bpf.sha256"
  echo "generated_outputs_after=$(wc -l < "$run/generated-bpf.sha256")" >> "$run/metrics.txt"
  {
    echo "mise=$(mise --version | head -1)"
    echo "root_go=$(mise exec -- go version 2>&1 | tail -1)"
    echo "clang=$(mise exec -- clang --version 2>&1 | head -1)"
    echo "bpf2go_module=$(cd internal/tools && mise exec -- go list -m -f '{{.Version}}' github.com/cilium/ebpf 2>&1 | tail -1)"
    echo "toolchain_go=$(cd internal/tools && mise exec -- go version 2>&1 | tail -1)"
  } >> "$run/metrics.txt"
fi
cat "$run/metrics.txt"
tail -15 "$run/mise-run.log"
exit "$rc"
