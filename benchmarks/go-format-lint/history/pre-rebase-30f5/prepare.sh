#!/usr/bin/env bash
set -euo pipefail

# Recreate the two source worktrees used by measure.sh. Tool installation and
# BPF generation are setup, not part of the timed command.
: "${OBI_REPO:?set OBI_REPO to a checkout of the OBI git repository}"
: "${WORKTREE_ROOT:?set WORKTREE_ROOT to a durable directory outside the repository}"

SOURCE_COMMIT=30f5e640bd0d0addfc95bb809b3f3381d014eed5
MAKE_BASE_COMMIT=df8f55c473718b1f927faff0131460757b469388

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for commit in "$SOURCE_COMMIT" "$MAKE_BASE_COMMIT"; do
  git -C "$OBI_REPO" cat-file -e "$commit^{commit}"
done
mkdir -p "$WORKTREE_ROOT"
for name in make mise; do
  test ! -e "$WORKTREE_ROOT/$name" || { echo "$WORKTREE_ROOT/$name already exists" >&2; exit 1; }
  git -C "$OBI_REPO" worktree add --detach "$WORKTREE_ROOT/$name" "$SOURCE_COMMIT"
done

mise -C "$WORKTREE_ROOT/mise" install
mise -C "$WORKTREE_ROOT/mise" run generate
mise -C "$WORKTREE_ROOT/make" install

# Carry the exact generated bindings and objects to the legacy Make worktree;
# these ignored outputs are not included in the source commit.
while IFS= read -r -d '' path; do
  mkdir -p "$WORKTREE_ROOT/make/$(dirname "$path")"
  cp "$WORKTREE_ROOT/mise/$path" "$WORKTREE_ROOT/make/$path"
done < <(cd "$WORKTREE_ROOT/mise" && find pkg -type f \
  \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -print0)

# Apply the Make-era entry point and tool manifest to the same application
# source; align its golangci-lint module and transitive versions to Mise.
cp "$SCRIPT_DIR/legacy-overlay/Makefile" "$WORKTREE_ROOT/make/Makefile"
mkdir -p "$WORKTREE_ROOT/make/internal/tools"
cp "$SCRIPT_DIR/legacy-overlay/internal/tools/"* "$WORKTREE_ROOT/make/internal/tools/"
mise -C "$WORKTREE_ROOT/make" exec -- go get -C internal/tools github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.14.0
cmp "$WORKTREE_ROOT/make/internal/tools/go.mod" "$SCRIPT_DIR/legacy-overlay/aligned/internal/tools/go.mod"
cmp "$WORKTREE_ROOT/make/internal/tools/go.sum" "$SCRIPT_DIR/legacy-overlay/aligned/internal/tools/go.sum"

printf 'Make source: '; git -C "$WORKTREE_ROOT/make" rev-parse HEAD
printf 'Mise source: '; git -C "$WORKTREE_ROOT/mise" rev-parse HEAD
printf 'Make tool module: '; grep 'github.com/golangci/golangci-lint/v2 ' "$WORKTREE_ROOT/make/internal/tools/go.mod"
printf 'Mise golangci: '; mise -C "$WORKTREE_ROOT/mise" exec -- golangci-lint version
