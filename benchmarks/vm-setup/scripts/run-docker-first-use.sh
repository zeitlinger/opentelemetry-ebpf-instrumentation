#!/usr/bin/env bash
set -euo pipefail
run_id=${1:?usage: run-docker-first-use.sh RUN_ID}
root=/home/gregor/obi-bench/task1
run="$root/runs/$run_id"
mkdir -p "$run"
if [[ -e "$run/repo" ]]; then echo "Refusing to overwrite $run/repo" >&2; exit 2; fi
cp -a "$root/sources/main" "$run/repo"
git -C "$run/repo" init -q
git -C "$run/repo" config user.name benchmark
git -C "$run/repo" config user.email benchmark@example.invalid
outputs=$(find "$run/repo/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) | wc -l)
if [[ "$outputs" != 0 ]]; then echo "expected no generated files, found $outputs" >&2; exit 2; fi
/home/gregor/reset-docker-store.sh > "$run/docker-reset.log" 2>&1
{
  echo "run=$run_id"
  echo "commit=a6207d767125db2355710502542451cc4b474d96"
  echo "start_utc=$(date -u +%FT%TZ)"
  echo "docker_server=$(docker version --format '{{.Server.Version}}')"
  echo "host_kernel=$(uname -sr)"
  echo "docker_store_empty=yes"
  echo "generator_image=ghcr.io/open-telemetry/obi-generator:0.2.17"
  echo "generated_outputs_before=$outputs"
} > "$run/metrics.txt"
cd "$run/repo"
start=$(date +%s%N)
rc=0
make docker-generate > "$run/make-docker-generate.log" 2>&1 || rc=$?
end=$(date +%s%N)
printf 'task_exit=%s\ntask_duration_ns=%s\nend_utc=%s\n' "$rc" "$((end-start))" "$(date -u +%FT%TZ)" >> "$run/metrics.txt"
if [[ "$rc" == 0 ]]; then
  find pkg -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -print0 | sort -z | xargs -0 sha256sum > "$run/generated-bpf.sha256"
  echo "generated_outputs_after=$(wc -l < "$run/generated-bpf.sha256")" >> "$run/metrics.txt"
  docker image inspect --format='{{.Id}} {{json .RepoDigests}}' ghcr.io/open-telemetry/obi-generator:0.2.17 >> "$run/metrics.txt"
fi
cat "$run/metrics.txt"
tail -20 "$run/make-docker-generate.log"
exit "$rc"
