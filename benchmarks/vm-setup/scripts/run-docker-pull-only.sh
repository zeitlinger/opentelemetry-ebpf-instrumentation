#!/usr/bin/env bash
set -euo pipefail
run_id=${1:?usage: run-docker-pull-only.sh RUN_ID}
root=/home/gregor/obi-bench/task1/setup-only/$run_id
mkdir -p "$root"
/home/gregor/reset-docker-store.sh > "$root/docker-reset.log" 2>&1
[[ -z "$(docker image ls -aq)" ]]
{
 echo "run=$run_id"; echo "start_utc=$(date -u +%FT%TZ)"; echo "docker=$(docker version --format '{{.Server.Version}}')"; echo "docker_store_empty=yes"; echo "image=ghcr.io/open-telemetry/obi-generator:0.2.17"
} > "$root/metrics.txt"
start=$(date +%s%N); rc=0
docker pull ghcr.io/open-telemetry/obi-generator:0.2.17 > "$root/docker-pull.log" 2>&1 || rc=$?
end=$(date +%s%N)
printf 'pull_exit=%s\npull_duration_ns=%s\nend_utc=%s\n' "$rc" "$((end-start))" "$(date -u +%FT%TZ)" >> "$root/metrics.txt"
if [[ "$rc" == 0 ]]; then docker image inspect --format='image_id={{.Id}} repo_digests={{json .RepoDigests}} image_size={{.Size}}' ghcr.io/open-telemetry/obi-generator:0.2.17 >> "$root/metrics.txt"; fi
cat "$root/metrics.txt"
tail -8 "$root/docker-pull.log"
exit "$rc"
