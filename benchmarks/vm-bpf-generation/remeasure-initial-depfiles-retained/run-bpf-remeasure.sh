#!/usr/bin/env bash
set -euo pipefail
base="$HOME/obi-bench/task3"
out="$base/remeasure-20261014"
branch="$out/branch"
main="$out/main"
mkdir -p "$out/logs" "$out/results"
[[ ! -e "$branch" && ! -e "$main" ]] || { echo "output exists" >&2; exit 2; }
cp -a "$base/sources/mise-branch" "$branch"
cp -a "$base/sources/main" "$main"
git -C "$branch" init -q
git -C "$main" init -q
# The main generator image sets GOCACHE=/tmp/go-build. docker-generate uses --rm and
# mounts only the source tree, so named volumes are injected via this PATH wrapper
# to make warm module/build caches persist across the untimed warm-up and samples.
wrapper_dir="$out/docker-cache-wrapper"
mkdir -p "$wrapper_dir"
cat > "$wrapper_dir/docker" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == run ]]; then
  shift
  printf '%s\n' "docker run --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build" >> /home/gregor/obi-bench/task3/remeasure-20261014/logs/docker-wrapper-invocations.txt
  exec /usr/bin/docker run \
    --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/go/pkg/mod \
    --mount type=volume,src=obi-bpf-remeasure-gocache,target=/tmp/go-build \
    "$@"
fi
exec /usr/bin/docker "$@"
WRAPPER
chmod +x "$wrapper_dir/docker"
docker volume create obi-bpf-remeasure-gomodcache >/dev/null
docker volume create obi-bpf-remeasure-gocache >/dev/null
docker run --rm --user 0:0 -v obi-bpf-remeasure-gomodcache:/mnt alpine:3.22 sh -c 'chmod 0777 /mnt'
docker run --rm --user 0:0 -v obi-bpf-remeasure-gocache:/mnt alpine:3.22 sh -c 'chmod 0777 /mnt'
# Warmed caches are deliberately shared with the prior Task 3 setup; keep all commands rooted in the same KVM guest.
export MISE_DATA_DIR="$base/runs/mise-data" MISE_CACHE_DIR="$base/runs/mise-cache"
export GOMODCACHE="$base/runs/gomodcache" GOCACHE="$base/runs/gocache"
mkdir -p "$GOMODCACHE" "$GOCACHE"
{
 echo "date_utc=$(date -u +%FT%TZ)"
 echo "guest=$(hostname)"
 echo "uname=$(uname -a)"
 echo "cpu=$(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -1)"
 echo "cpus=$(nproc)"
 echo "memory=$(free -h | awk '/^Mem:/{print $2}')"
 echo "docker=$(docker version --format '{{.Server.Version}}')"
 echo "docker_generator=$(docker image inspect --format='{{.Id}}' ghcr.io/open-telemetry/obi-generator:0.2.17)"
 echo "docker_gomodcache_volume=obi-bpf-remeasure-gomodcache mounted at /go/pkg/mod"
 echo "docker_gocache_volume=obi-bpf-remeasure-gocache mounted at /tmp/go-build"
 echo "mise=$(mise --version | head -1)"
 echo "mise_go_install_before=$(find "$MISE_DATA_DIR/installs/go" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null || true)"
 echo "main_source=$(cd "$main" && git rev-parse --short=12 HEAD 2>/dev/null || printf 'archive-a6207d7')"
 echo "branch_source=$(cd "$branch" && git rev-parse --short=12 HEAD 2>/dev/null || printf 'archive-7a5f014-plus-go-pin-1.27.2')"
 echo "mise_go_pin=$(sed -n 's/^go = "\([^"]*\)"/\1/p' "$branch/mise.toml")"
 echo "module_go_toolchain=$(sed -n 's/^toolchain //p' "$branch/go.mod")"
 echo "main_go_toolchain=$(sed -n 's/^toolchain //p' "$main/go.mod" || true)"
 echo "go_cache=$(du -sh "$GOCACHE" | cut -f1)"
 echo "gomod_cache=$(du -sh "$GOMODCACHE" | cut -f1)"
} > "$out/environment.txt"
# Install the newly pinned Go before timing; all other tools and generator image were already installed/pulled.
cd "$branch"
mise install > "$out/logs/mise-install.log" 2>&1
mise exec -- go version > "$out/logs/mise-go-version.txt" 2>&1
# Untimed full warm-ups populate tool, module, and build caches for both paths.
find "$branch/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -delete
mise run generate > "$out/logs/warmup-branch.log" 2>&1
find "$main/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -delete
cd "$main"
PATH="$wrapper_dir:$PATH" make docker-generate > "$out/logs/warmup-main.log" 2>&1
# Each full run deletes all generated outputs; immediately follow with an untampered no-op sample.
for mode in branch main; do
 if [[ "$mode" == branch ]]; then dir="$branch"; task=(mise run generate); else dir="$main"; task=(env PATH="$wrapper_dir:$PATH" make docker-generate); fi
 for i in 1 2 3 4 5; do
   find "$dir/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -delete
   n=$(find "$dir/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) | wc -l)
   [[ "$n" -eq 0 ]] || { echo "generated outputs remain before full run $mode/$i: $n" >&2; exit 2; }
   start=$(date +%s%N)
   (cd "$dir" && "${task[@]}") > "$out/logs/${mode}-full-${i}.log" 2>&1
   end=$(date +%s%N)
   printf '%s,full,%s,%s,%s\n' "$mode" "$i" "$((end-start))" "$(date -u +%FT%TZ)" >> "$out/results/timings.csv"
   find "$dir/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -print0 | sort -z | xargs -0 sha256sum > "$out/results/${mode}-full-${i}.sha256"
   outputs=$(wc -l < "$out/results/${mode}-full-${i}.sha256")
   [[ "$outputs" -eq 60 ]] || { echo "expected 60 outputs but got $outputs on $mode full $i" >&2; exit 2; }
   start=$(date +%s%N)
   (cd "$dir" && "${task[@]}") > "$out/logs/${mode}-noop-${i}.log" 2>&1
   end=$(date +%s%N)
   printf '%s,noop,%s,%s,%s\n' "$mode" "$i" "$((end-start))" "$(date -u +%FT%TZ)" >> "$out/results/timings.csv"
   find "$dir/pkg" -type f \( -name '*_bpfel.go' -o -name '*_bpfeb.go' -o -name '*_bpfel.o' -o -name '*_bpfeb.o' \) -print0 | sort -z | xargs -0 sha256sum > "$out/results/${mode}-noop-${i}.sha256"
   cmp "$out/results/${mode}-full-${i}.sha256" "$out/results/${mode}-noop-${i}.sha256"
   echo "done $mode full/noop $i"
 done
done
{
 echo "branch_go=$(cd "$branch" && mise exec -- go version 2>&1 | tail -1)"
 echo "branch_goenv_gotoolchain=$(cd "$branch" && mise exec -- go env GOTOOLCHAIN 2>&1 | tail -1)"
 echo "branch_go_install_after=$(find "$MISE_DATA_DIR/installs/go" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tr '\n' ' ')"
 echo "module_cache_final=$(du -sh "$GOMODCACHE" | cut -f1)"
 echo "build_cache_final=$(du -sh "$GOCACHE" | cut -f1)"
 echo "go_toolchain_download_mentions=$(grep -Ehi 'downloading go1\.27\.[0-9]' "$out/logs"/*.log | wc -l)"
 echo "branch_outputs=$(wc -l < "$out/results/branch-full-5.sha256")"
 echo "main_outputs=$(wc -l < "$out/results/main-full-5.sha256")"
 echo "docker_gomodcache_volume_size=$(docker run --rm --mount type=volume,src=obi-bpf-remeasure-gomodcache,target=/mnt alpine:3.22 du -sh /mnt | cut -f1)"
 echo "docker_gocache_volume_size=$(docker run --rm --mount type=volume,src=obi-bpf-remeasure-gocache,target=/mnt alpine:3.22 du -sh /mnt | cut -f1)"
} > "$out/postflight.txt"
sha256sum "$out"/environment.txt "$out"/postflight.txt "$out"/results/* "$out"/logs/* > "$out/SHA256SUMS"
echo "measurement completed: $out"
cat "$out/results/timings.csv"
cat "$out/postflight.txt"
