#!/usr/bin/env bash
set -euo pipefail
B="$1"; S="$2"; SEED="$3"; v="$4"
c="$S/cache/$v"; mkdir -p "$c"/{go,gomod,golangci,xdg}
export GOCACHE="$c/go" GOMODCACHE="$c/gomod" GOLANGCI_LINT_CACHE="$c/golangci" XDG_CACHE_HOME="$c/xdg"
m='github.com/grafana/go-offsets-tracker@v0.1.7'; d='cache/download/github.com/grafana/go-offsets-tracker'
mkdir -p "$GOMODCACHE/$m" "$GOMODCACHE/$d"; chmod -R u+w "$GOMODCACHE/$m" "$GOMODCACHE/$d"
cp -a "$SEED/$m/." "$GOMODCACHE/$m/"; cp -a "$SEED/$d/." "$GOMODCACHE/$d/"
case $v in
  make-j8) cd "$B/make"; cmd='mise exec -- make -j8 fmt && mise exec -- make -j8 lint' ;;
  mise|mise-waitfor) cd "$B/mise"
    if [[ $v == mise-waitfor ]]; then perl -0pi -e 's/(\[tasks\."lint:go"\]\nhide = true\n)(?!wait_for)/$1wait_for = ["lint:collectt"]\n/' mise.toml
    else cp "$S/mise.toml.orig" mise.toml; fi
    cmd='mise run fmt && mise run lint' ;;
esac
s=$(date +%s%N); sh -c "$cmd" >"$S/$v.log" 2>&1 || { echo "$v FAILED"; exit 1; }; e=$(date +%s%N)
python3 -I -c "print('%.3f' % (($e-$s)/1e9))"
