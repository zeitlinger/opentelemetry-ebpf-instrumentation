#!/usr/bin/env bash
set -euo pipefail
mode=${1:?usage: run-task3-parity.sh main|mise-branch}
base=/home/gregor/obi-bench/task3
run="$base/runs/$mode"
src="$base/sources/$mode"
mkdir -p "$base/runs"
[[ ! -e "$run" ]] || { echo "refusing to overwrite $run" >&2; exit 2; }
cp -a "$src" "$run"
git -C "$run" init -q
git -C "$run" config user.name benchmark
git -C "$run" config user.email benchmark@example.invalid
outputs=$(find "$run/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) | wc -l)
[[ "$outputs" == 0 ]] || { echo "expected no generated files, found $outputs" >&2; exit 2; }
{
  echo "mode=$mode"
  if [[ "$mode" == main ]]; then echo 'commit=a6207d767125db2355710502542451cc4b474d96'; else echo 'commit=7a5f0146890090f312751f9cb14ceb4c5f32739f'; fi
  echo "start_utc=$(date -u +%FT%TZ)"
  echo "docker=$(docker version --format '{{.Server.Version}}')"
  echo "generated_outputs_before=$outputs"
  if [[ "$mode" == main ]]; then echo "image=$(docker image inspect --format='{{.Id}}' ghcr.io/open-telemetry/obi-generator:0.2.17)"; else echo "mise=$(mise --version | head -1)"; fi
} > "$run/metrics.txt"
cd "$run"
if [[ "$mode" == mise-branch ]]; then
  export MISE_DATA_DIR="$base/runs/mise-data" MISE_CACHE_DIR="$base/runs/mise-cache"
  export GOMODCACHE="$base/runs/gomodcache" GOCACHE="$base/runs/gocache"
  mkdir -p "$MISE_DATA_DIR" "$MISE_CACHE_DIR" "$GOMODCACHE" "$GOCACHE"
  mise install > "$run/mise-install.log" 2>&1
fi
start=$(date +%s%N)
rc=0
if [[ "$mode" == main ]]; then
  make docker-generate > "$run/task.log" 2>&1 || rc=$?
else
  mise run generate > "$run/task.log" 2>&1 || rc=$?
fi
end=$(date +%s%N)
printf 'task_exit=%s\ntask_duration_ns=%s\nend_utc=%s\n' "$rc" "$((end-start))" "$(date -u +%FT%TZ)" >> "$run/metrics.txt"
if [[ "$rc" == 0 ]]; then
  find pkg -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -print0 | sort -z | xargs -0 sha256sum > "$run/generated-bpf.sha256"
  echo "generated_outputs_after=$(wc -l < "$run/generated-bpf.sha256")" >> "$run/metrics.txt"
  if [[ "$mode" == mise-branch ]]; then
    {
      echo "mise=$(mise --version | head -1)"
      echo "root_go=$(mise exec -- go version 2>&1 | tail -1)"
      echo "clang=$(mise exec -- clang --version 2>&1 | head -1)"
      echo "bpf2go_module=$(cd internal/tools && mise exec -- go list -m -f '{{.Version}}' github.com/cilium/ebpf 2>&1 | tail -1)"
      echo "toolchain_go=$(cd internal/tools && mise exec -- go version 2>&1 | tail -1)"
    } >> "$run/metrics.txt"
  fi
fi
cat "$run/metrics.txt"
tail -20 "$run/task.log"
exit "$rc"
