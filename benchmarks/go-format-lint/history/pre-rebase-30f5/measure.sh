#!/usr/bin/env bash
set -euo pipefail

: "${MAKE_DIR:?set MAKE_DIR to the legacy Make worktree}"
: "${MISE_DIR:?set MISE_DIR to the Mise worktree}"
: "${BENCH_DIR:?set BENCH_DIR to the durable benchmark directory}"

run_one() {
  local variant="$1" trial="$2" directory cache logfile logname elapsed_file
  case "$variant" in
    make|make-j8) directory="$MAKE_DIR" ;;
    mise) directory="$MISE_DIR" ;;
    *) echo "unknown variant: $variant" >&2; return 2 ;;
  esac
  cache="$BENCH_DIR/cache/$variant"
  mkdir -p "$cache" "$BENCH_DIR/logs"
  export GOCACHE="$cache/go" GOMODCACHE="$cache/gomod"
  export GOLANGCI_LINT_CACHE="$cache/golangci" XDG_CACHE_HOME="$cache/xdg"
  mkdir -p "$GOCACHE" "$GOMODCACHE" "$GOLANGCI_LINT_CACHE" "$XDG_CACHE_HOME"
  logname="logs/${variant}-${trial}.log"
  logfile="$BENCH_DIR/$logname"
  elapsed_file="$BENCH_DIR/logs/${variant}-${trial}.seconds"
  cd "$directory"
  if [[ "$variant" == mise ]]; then
    ( TIMEFORMAT='%3R'; time sh -c 'mise run fmt && mise run lint' >"$logfile" 2>&1 ) 2>"$elapsed_file"
  else
    local jobs=()
    [[ "$variant" == make-j8 ]] && jobs=(-j8)
    ( TIMEFORMAT='%3R'; time sh -c 'mise exec -- make "$@" fmt && mise exec -- make "$@" lint' sh "${jobs[@]}" >"$logfile" 2>&1 ) 2>"$elapsed_file"
  fi
  printf '%s\t%s\t%s\t%s\n' "$trial" "$variant" "$(cat "$elapsed_file")" "$logname" | tee -a "$BENCH_DIR/results.tsv"
}

# Rotating order balances position effects; runs are serial, never concurrent.
orders=("make make-j8 mise" "make-j8 mise make" "mise make make-j8")
for trial in {1..5}; do
  order=${orders[$(((trial - 1) % ${#orders[@]}))]}
  for variant in $order; do run_one "$variant" "$trial"; done
done
