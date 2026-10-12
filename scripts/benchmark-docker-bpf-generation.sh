#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
  cat <<'HELP'
Benchmark the old Docker BPF-generation path on the current Mise source tree.

Usage:
  scripts/benchmark-docker-bpf-generation.sh [--runs N]

The script clones the current Mise worktree's committed HEAD into a temporary
folder, overlays the baseline checkout's committed Makefile and
`dependencies.Dockerfile`, then runs the old `make docker-generate` target there.
It reports the pinned generator image pull separately, then times repeated warm
no-op and cold/full generation runs (default: 3 repetitions each). Generated
files and Make's helper files are confined to the temporary clone.

Prerequisites:
  - Linux with Bash, GNU date, git, Docker (daemon available), make, and Python 3
  - Network access if the pinned generator image is not already present
  - Clean worktrees apart from this script; set MISE_ROOT to override the
    default Mise worktree path

Limitations:
  - Timings include Docker container startup and the generator image's cache
    behavior. They measure this machine and repository workload, not a general
    performance guarantee.
  - The cold/full case deletes generated BPF outputs and dependency files before
    each run; the warm case leaves outputs present and measures the no-op path.
  - Generation explicitly targets amd64 and arm64 so an inherited empty
    BPF_TARGETS value cannot make bpf2go reject the target list.
  - The temporary baseline Makefile overlay forwards BPF_TARGETS into Docker;
    the baseline recipe did not do this, but current source directives need it.
HELP
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

RUNS=3
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --runs)
      (($# >= 2)) || die "--runs requires a positive integer"
      RUNS=$2
      shift 2
      ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive integer"

for command_name in git docker make python3 date; do
  command -v "$command_name" >/dev/null || die "required command not found: $command_name"
done
date +%s%N | grep -Eq '^[0-9]{19}$' || die "GNU date with nanosecond support is required"

BASELINE_ROOT="$(git rev-parse --show-toplevel)"
MISE_ROOT="${MISE_ROOT:-/home/gregor/source/opentelemetry-ebpf-instrumentation-worktrees/pr-3672-1791469276832670719-65278-0}"
[[ -d "$MISE_ROOT/.git" || -f "$MISE_ROOT/.git" ]] || die "Mise worktree not found: $MISE_ROOT"

baseline_changes="$(git -C "$BASELINE_ROOT" status --porcelain --untracked-files=all | grep -vE '^\?\? scripts/benchmark-docker-bpf-generation\.sh$' || true)"
[[ -z "$baseline_changes" ]] || die "baseline worktree must be clean apart from this script"
mise_changes="$(git -C "$MISE_ROOT" status --porcelain --untracked-files=all || true)"
[[ -z "$mise_changes" ]] || die "Mise worktree must be clean"

BASELINE_COMMIT="$(git -C "$BASELINE_ROOT" rev-parse HEAD)"
SOURCE_COMMIT="$(git -C "$MISE_ROOT" rev-parse HEAD)"
MAKEFILE_BLOB="$(git -C "$BASELINE_ROOT" rev-parse "$BASELINE_COMMIT:Makefile")"
DEPENDENCIES_BLOB="$(git -C "$BASELINE_ROOT" rev-parse "$BASELINE_COMMIT:dependencies.Dockerfile")"
BASELINE_MAKEFILE="$(git -C "$BASELINE_ROOT" show "$BASELINE_COMMIT:Makefile")"
grep -Eq '^[[:space:]]*docker-generate[[:space:]]*:' <<< "$BASELINE_MAKEFILE" || die "baseline Makefile has no docker-generate target"
docker_generator="$(awk '/^GEN_IMG \?= / { sub(/^GEN_IMG \?= /, ""); print; exit }' <<< "$BASELINE_MAKEFILE")"
[[ -n "$docker_generator" ]] || die "could not find GEN_IMG in baseline Makefile"

docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/obi-docker-bpf-bench.XXXXXX")"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

SNAPSHOT="$TMP_ROOT/source"
git clone --quiet --no-hardlinks --no-checkout "$MISE_ROOT" "$SNAPSHOT"
git -C "$SNAPSHOT" checkout --quiet --detach "$SOURCE_COMMIT"
# Current go:generate directives use BPF_TARGETS; the legacy Docker recipe did
# not forward it into the container, so add that compatibility argument only
# to this temporary Makefile overlay.
git -C "$BASELINE_ROOT" show "$BASELINE_COMMIT:Makefile" \
  | awk '{ print } /-e GIT_DIR=/ { print "\t\t-e BPF_TARGETS=\"$(BPF_TARGETS)\" \\" }' \
  > "$SNAPSHOT/Makefile"
git -C "$BASELINE_ROOT" show "$BASELINE_COMMIT:dependencies.Dockerfile" > "$SNAPSHOT/dependencies.Dockerfile"

printf 'Current source commit:       %s\n' "$SOURCE_COMMIT"
printf 'Baseline Makefile commit:    %s\n' "$BASELINE_COMMIT"
printf 'Baseline Makefile blob SHA:  %s\n' "$MAKEFILE_BLOB"
printf 'Baseline dependencies blob:  %s\n' "$DEPENDENCIES_BLOB"
printf 'Docker generator image:      %s\n' "$docker_generator"
printf 'Repetitions: %s per timing\n' "$RUNS"
printf '\nSetup cost (not included in task timings)\n'
if docker image inspect "$docker_generator" >/dev/null 2>&1; then
  printf 'Docker image pull: skipped (image already present)\n'
else
  start="$(date +%s%N)"
  docker pull "$docker_generator" >"$TMP_ROOT/docker-pull.log" 2>&1 || {
    cat "$TMP_ROOT/docker-pull.log" >&2
    die "Docker generator image pull failed"
  }
  end="$(date +%s%N)"
  printf 'Docker image pull: %.3f s\n' "$((end - start))e-9"
fi

clear_generated() {
  find "$SNAPSHOT/pkg" -type f \( \
    -name '*_bpfel.go' -o -name '*_bpfeb.go' -o \
    -name '*_bpfel.go.d' -o -name '*_bpfeb.go.d' -o \
    -name '*_bpfel.o' -o -name '*_bpfeb.o' \
  \) -delete
}

run_generation() {
  (cd "$SNAPSHOT" && BPF_TARGETS=amd64,arm64 OCI_BIN=docker make docker-generate)
}

timed() {
  local label=$1
  shift
  local log="$TMP_ROOT/run.log"
  local start end elapsed
  start="$(date +%s%N)"
  if "$@" >"$log" 2>&1; then
    end="$(date +%s%N)"
    elapsed=$((end - start))
    printf '%s %s\n' "$label" "$elapsed" >> "$TMP_ROOT/timings"
    printf '  %-14s %d: %.3f s\n' "$label" "$(( $(grep -c "^$label " "$TMP_ROOT/timings") ))" "$((elapsed))e-9"
  else
    cat "$log" >&2
    die "$label generation failed"
  fi
}

: > "$TMP_ROOT/timings"
printf '\nWarm no-op (generation outputs present)\n'
run_generation >"$TMP_ROOT/prime.log" 2>&1 || {
  cat "$TMP_ROOT/prime.log" >&2
  die "initial generation failed"
}
for ((i = 1; i <= RUNS; i++)); do
  timed docker-noop run_generation
done

printf '\nCold/full generation (outputs removed before every run)\n'
for ((i = 1; i <= RUNS; i++)); do
  clear_generated
  timed docker-full run_generation
done

printf '\nMedian timings\n'
python3 - "$TMP_ROOT/timings" <<'PY'
import statistics
import sys

groups = {}
with open(sys.argv[1], encoding="utf-8") as timings:
    for line in timings:
        name, nanoseconds = line.split()
        groups.setdefault(name, []).append(int(nanoseconds) / 1_000_000_000)

for name in ("docker-noop", "docker-full"):
    values = groups[name]
    print(f"{name:14s} median {statistics.median(values):.3f} s ({len(values)} runs)")
PY
