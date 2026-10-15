#!/usr/bin/env bash
set -euo pipefail
base="$HOME/obi-bench/task3"
out="$base/remeasure-bpf2go-prebuilt-20261014"
branch="$base/remeasure-final-20261014/branch"
main="$base/remeasure-final-20261014/main"
profile="$out/profile"
mkdir -p "$profile/mise/bin" "$profile/docker/bin" "$profile/docker-wrapper"
export MISE_DATA_DIR="$base/runs/mise-data" MISE_CACHE_DIR="$base/runs/mise-cache"
export GOMODCACHE="$base/runs/gomodcache" GOCACHE="$base/runs/gocache"
# Capture the command-level profile around one additional warm generation per path.
real_bpf2go="$(cd "$branch" && mise which bpf2go)"
real_clang="$(cd "$branch" && mise which clang)"
real_go="$(cd "$branch" && mise which go)"
real_bpf2go_dir="$(dirname "$real_bpf2go")"
llvm_tool_bin="$MISE_DATA_DIR/installs/conda-llvm-tools/22.1.8/.mise-bins"
cat > "$profile/mise/bin/bpf2go" <<'WRAP'
#!/usr/bin/env bash
start=$(date +%s%N)
"$REAL_BPF2GO" "$@"
rc=$?
end=$(date +%s%N)
printf 'bpf2go elapsed_ns=%s pid=%s args=%q\n' "$((end-start))" "$$" "$*" >> "$PROFILE_DIR/mise-bpf2go.log"
exit "$rc"
WRAP
cat > "$profile/mise/bin/clang" <<'WRAP'
#!/usr/bin/env bash
start=$(date +%s%N)
"$REAL_CLANG" "$@"
rc=$?
end=$(date +%s%N)
printf 'clang elapsed_ns=%s pid=%s source=%q\n' "$((end-start))" "$$" "${@: -1}" >> "$PROFILE_DIR/mise-clang.log"
exit "$rc"
WRAP
cat > "$profile/mise/bin/go" <<'WRAP'
#!/usr/bin/env bash
start=$(date +%s%N)
"$REAL_GO" "$@"
rc=$?
end=$(date +%s%N)
printf 'go elapsed_ns=%s pid=%s args=%q\n' "$((end-start))" "$$" "$*" >> "$PROFILE_DIR/mise-go.log"
exit "$rc"
WRAP
chmod +x "$profile/mise/bin"/*
# In the image these wrappers delegate to the generator image's own prebuilt tools.
cat > "$profile/docker/bin/bpf2go" <<'WRAP'
#!/bin/sh
start=$(date +%s%N)
/go/bin/bpf2go "$@"
rc=$?
end=$(date +%s%N)
printf 'bpf2go elapsed_ns=%s pid=%s\n' "$((end-start))" "$$" >> /profile/docker-bpf2go.log
exit "$rc"
WRAP
cat > "$profile/docker/bin/clang" <<'WRAP'
#!/bin/sh
start=$(date +%s%N)
/usr/lib/llvm22/bin/clang "$@"
rc=$?
end=$(date +%s%N)
printf 'clang elapsed_ns=%s pid=%s\n' "$((end-start))" "$$" >> /profile/docker-clang.log
exit "$rc"
WRAP
cat > "$profile/docker/bin/go" <<'WRAP'
#!/bin/sh
start=$(date +%s%N)
/usr/local/go/bin/go "$@"
rc=$?
end=$(date +%s%N)
printf 'go elapsed_ns=%s pid=%s args=%s\n' "$((end-start))" "$$" "$*" >> /profile/docker-go.log
exit "$rc"
WRAP
chmod +x "$profile/docker/bin"/*
# Main source's docker-generate target is unchanged; add a temporary mount/env via PATH wrapper.
cat > "$profile/docker-wrapper/docker" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == run ]]; then
  shift
  exec /usr/bin/docker run \
    --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod \
    --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build \
    -v "$PROFILE_DIR/docker:/profile" \
    -e BPF2GO=/profile/bin/bpf2go -e CLANG=/profile/bin/clang \
    -e PATH=/profile/bin:/go/bin:/usr/lib/llvm22/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
fi
exec /usr/bin/docker "$@"
WRAP
chmod +x "$profile/docker-wrapper/docker"
# Write exact profile command/environment and clear prior data before instrumented runs.
{
  echo "mise_bpf2go=$real_bpf2go"
  echo "mise_clang=$real_clang"
  echo "mise_go=$real_go"
  echo "docker_tools=$(docker run --rm --entrypoint sh ghcr.io/open-telemetry/obi-generator:0.2.17 -c 'command -v go; command -v bpf2go; command -v clang')"
  echo "profile_run_count=one extra full generation per path after the five timed samples"
  echo "generated_go_compile=not part of either generate command; go wrapper records invoked Go commands"
} > "$profile/environment.txt"
: > "$profile/mise-bpf2go.log"; : > "$profile/mise-clang.log"; : > "$profile/mise-go.log"
: > "$profile/docker-bpf2go.log"; : > "$profile/docker-clang.log"; : > "$profile/docker-go.log"
outputs=( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' -o -name '*_bpf*.go.d' )
find_generated() { find "$1/pkg" -type f \( "${outputs[@]}" \) "${@:2}"; }
find_generated "$branch" -delete
mise_start=$(date +%s%N)
(
  cd "$branch"
  PATH="$profile/mise/bin:$real_bpf2go_dir:$MISE_DATA_DIR/installs/clang/22.1.8/.mise-bins:$llvm_tool_bin:$MISE_DATA_DIR/installs/go/1.27.2/bin:$PATH" \
  REAL_BPF2GO="$real_bpf2go" REAL_CLANG="$real_clang" REAL_GO="$real_go" PROFILE_DIR="$profile" \
  BPF2GO="$profile/mise/bin/bpf2go" CLANG="$profile/mise/bin/clang" \
  make -f bpf/Makefile generate
) > "$profile/mise-run.log" 2>&1
mise_end=$(date +%s%N)
echo "elapsed_ns=$((mise_end-mise_start))" > "$profile/mise-wall.txt"
find_generated "$branch" | sort | sed "s|$branch/||" > "$profile/mise-output-list.txt"
find_generated "$branch" -delete
docker_start=$(date +%s%N)
(
 cd "$main"
 PATH="$profile/docker-wrapper:$PATH" PROFILE_DIR="$profile" make docker-generate
) > "$profile/docker-run.log" 2>&1
docker_end=$(date +%s%N)
echo "elapsed_ns=$((docker_end-docker_start))" > "$profile/docker-wall.txt"
find_generated "$main" | sort | sed "s|$main/||" > "$profile/docker-output-list.txt"
{
  echo "mise_clang_total_ns=$(awk -F'[ =]' '{s+=$3} END{print s+0}' "$profile/mise-clang.log")"
  echo "docker_clang_total_ns=$(awk -F'[ =]' '{s+=$3} END{print s+0}' "$profile/docker-clang.log")"
  echo "mise_bpf2go_calls=$(wc -l < "$profile/mise-bpf2go.log")"
  echo "docker_bpf2go_calls=$(wc -l < "$profile/docker-bpf2go.log")"
  echo "mise_clang_calls=$(wc -l < "$profile/mise-clang.log")"
  echo "docker_clang_calls=$(wc -l < "$profile/docker-clang.log")"
  echo "mise_go_calls=$(wc -l < "$profile/mise-go.log")"
  echo "docker_go_calls=$(wc -l < "$profile/docker-go.log")"
  echo "generated_outputs_mise=$(wc -l < "$profile/mise-output-list.txt")"
  echo "generated_outputs_docker=$(wc -l < "$profile/docker-output-list.txt")"
} > "$profile/summary.txt"
echo "profile completed: $profile"
cat "$profile/environment.txt" "$profile/mise-wall.txt" "$profile/docker-wall.txt" "$profile/summary.txt"
