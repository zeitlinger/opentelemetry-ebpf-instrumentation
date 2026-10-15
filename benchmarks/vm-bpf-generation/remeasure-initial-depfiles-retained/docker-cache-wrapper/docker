#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == run ]]; then
  shift
  echo 'docker run --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build' >> /home/gregor/obi-bench/task3/remeasure-20261014/logs/docker-wrapper-invocations.txt
  exec /usr/bin/docker run \
    --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod \
    --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build \
    "$@"
fi
exec /usr/bin/docker "$@"
