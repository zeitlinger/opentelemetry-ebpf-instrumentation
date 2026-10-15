#!/usr/bin/env bash
set -euo pipefail
base="$HOME/obi-bench/task3"
out="$base/remeasure-bpf2go-prebuilt-20261014"
main="$base/remeasure-final-20261014/main"
profile="$out/profile"
mkdir -p "$profile/docker/bin"
cat > "$profile/docker/bin/bpf2go" <<'WRAP'
#!/bin/sh
start=$(awk '{printf "%.2f", $1}' /proc/uptime)
/go/bin/bpf2go "$@"
rc=$?
end=$(awk '{printf "%.2f", $1}' /proc/uptime)
elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%.0f", (e-s)*1000000000}')
printf 'bpf2go elapsed_ns=%s pid=%s\n' "$elapsed" "$$" >> /profile/docker-bpf2go.log
exit "$rc"
WRAP
cat > "$profile/docker/bin/clang" <<'WRAP'
#!/bin/sh
start=$(awk '{printf "%.2f", $1}' /proc/uptime)
/usr/lib/llvm22/bin/clang "$@"
rc=$?
end=$(awk '{printf "%.2f", $1}' /proc/uptime)
elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%.0f", (e-s)*1000000000}')
printf 'clang elapsed_ns=%s pid=%s\n' "$elapsed" "$$" >> /profile/docker-clang.log
exit "$rc"
WRAP
cat > "$profile/docker/bin/go" <<'WRAP'
#!/bin/sh
start=$(awk '{printf "%.2f", $1}' /proc/uptime)
/usr/local/go/bin/go "$@"
rc=$?
end=$(awk '{printf "%.2f", $1}' /proc/uptime)
elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%.0f", (e-s)*1000000000}')
printf 'go elapsed_ns=%s pid=%s args=%s\n' "$elapsed" "$$" "$*" >> /profile/docker-go.log
exit "$rc"
WRAP
chmod +x "$profile/docker/bin"/*
: > "$profile/docker/docker-bpf2go.log"; : > "$profile/docker/docker-clang.log"; : > "$profile/docker/docker-go.log"
outputs=( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' -o -name '*_bpf*.go.d' )
find_generated() { find "$1/pkg" -type f \( "${outputs[@]}" \) "${@:2}"; }
find_generated "$main" -delete
before=$(find_generated "$main" | wc -l)
[[ "$before" -eq 0 ]] || { echo "expected zero outputs before profile, got $before" >&2; exit 2; }
_git_dir=$(git -C "$main" rev-parse --absolute-git-dir)
_git_common_dir=$(git -C "$main" rev-parse --path-format=absolute --git-common-dir)
{
 echo "profile_command=direct docker run replicating make docker-generate mounts/env; entrypoint shell keeps wrappers from generator /generate.sh defaults"
 echo "main_source=$main"
 echo "git_dir=$_git_dir"
 echo "git_common_dir=$_git_common_dir"
 echo "generator_image=$(docker image inspect --format='{{.Id}}' ghcr.io/open-telemetry/obi-generator:0.2.17)"
 echo "docker_gomodcache=obi-bpf-remeasure-gomodcache:/go/pkg/mod"
 echo "docker_gocache=obi-bpf-remeasure-gocache:/tmp/go-build"
} > "$profile/docker-instrumented-environment.txt"
start=$(awk '{printf "%.2f", $1}' /proc/uptime)
docker run --rm \
  --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod \
  --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build \
  -u "$(id -u):$(id -g)" \
  -v "$main:/src:z" \
  -v "$_git_common_dir:/src/.gitrepo:ro,z" \
  -v "$profile/docker:/profile" \
  -e GIT_DIR="/src/.gitrepo${_git_dir#$_git_common_dir}" \
  -e BPF_TARGETS=amd64,arm64 \
  -e BPF2GO=/profile/bin/bpf2go \
  -e CLANG=/profile/bin/clang \
  -e BPF_CLANG=/profile/bin/clang \
  -e GOCACHE=/tmp/go-build \
  -e PATH=/profile/bin:/go/bin:/usr/lib/llvm22/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -w /src \
  --entrypoint /bin/sh \
  ghcr.io/open-telemetry/obi-generator:0.2.17 \
  -c 'export PATH=/usr/lib/llvm22/bin:$PATH; make generate' \
  > "$profile/docker-run.log" 2>&1
end=$(awk '{printf "%.2f", $1}' /proc/uptime)
echo "elapsed_ns=$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%.0f", (e-s)*1000000000}')" > "$profile/docker-wall.txt"
count=$(find_generated "$main" | wc -l)
[[ "$count" -eq 90 ]] || { echo "expected 90 outputs after profile, got $count" >&2; exit 2; }
find_generated "$main" -print0 | sort -z | xargs -0 sha256sum > "$profile/docker-output-hashes.sha256"
{
  echo "docker_bpf2go_calls=$(wc -l < "$profile/docker/docker-bpf2go.log")"
  echo "docker_clang_calls=$(wc -l < "$profile/docker/docker-clang.log")"
  echo "docker_go_calls=$(wc -l < "$profile/docker/docker-go.log")"
  echo "docker_clang_total_ns=$(awk -F'[ =]' '{s+=$3} END{print s+0}' "$profile/docker/docker-clang.log")"
  echo "output_count=$count"
  echo "go_version=$(docker run --rm --entrypoint go ghcr.io/open-telemetry/obi-generator:0.2.17 version)"
  echo "toolchain=$(docker run --rm --entrypoint go ghcr.io/open-telemetry/obi-generator:0.2.17 env GOTOOLCHAIN)"
} > "$profile/docker-summary.txt"
echo "profile completed"; cat "$profile/docker-wall.txt" "$profile/docker-summary.txt"
