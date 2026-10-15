# Warm BPF generation remeasurement: prebuilt bpf2go

This follow-up compares the branch's Mise task against `origin/main`'s `make docker-generate` in the same existing Ubuntu 24.04.5 KVM guest (Linux 6.8.0-142, AMD Ryzen 9 7900, 4 vCPU, 7.8 GiB RAM; Docker 29.1.3). The generator image was already present. The branch source snapshot is based on `feat/mise-full-build` at the rebase base `a6207d767125db2355710502542451cc4b474d96`, including the Go 1.27.2 pin and the pinned prebuilt `go:github.com/cilium/ebpf/cmd/bpf2go` 0.22.0 implementation. Exact changed source/config files are under `source-files/`; the main snapshot is at the same base commit.

## Method and setup

- Before timing, `mise run generate` generated 90 outputs and matched the previous branch full-run manifest byte-for-byte (zero missing/extra/different). The 280 BPF C/H source inputs (excluding tests) are byte-identical across branch and main; manifests are in `results/`.
- Each path had one untimed full warm-up after Mise tools/image and caches were ready. Five timed full-generation runs per path deleted and verified removal of every generated Go binding, BPF object, and `.go.d` sidecar before running. Each full run was followed by one timed no-op, whose output hashes were checked against that full run. Exact commands, wrapper, logs, raw timings, and per-run hashes are included.
- Main's `docker-generate` remains unchanged. A temporary `docker` PATH wrapper adds the same named, persistent warmed volumes to each of the 11 Docker runs: `obi-bpf-remeasure-gomodcache` → `/go/pkg/mod` and `obi-bpf-remeasure-gocache` → `/tmp/go-build`. The wrapper invocations are recorded.
- Guest caches after warm-up: Mise module cache 1.1 GiB and Go build cache 125 MiB; Docker module volume 736.4 MiB and build volume 12.8 MiB. Mise 2026.9.16, Go 1.27.2 on Mise (`GOTOOLCHAIN=auto`) versus Go 1.27.0 in the generator image (`GOTOOLCHAIN=local`), bpf2go v0.22.0 both ways, Clang 22.1.8 both ways (Mise conda-forge build vs image Alpine build). Version evidence is in `environment.txt`, logs, and profile environment files.

## Results

| Path | Full generation median (range) | No-op median (range) |
|---|---:|---:|
| Mise | 35.681 s (33.745–38.086 s) | 0.094 s (0.092–0.131 s) |
| Main Make + Docker | 32.260 s (32.007–32.444 s) | 0.481 s (0.455–0.522 s) |

Raw samples are in `results/timings.csv`; summaries in `results/timing-summary.txt`. On these warm runs, Mise full generation was 3.421 s slower at the median, while its no-op was 0.387 s faster. The prior warm set had medians 33.272 s Mise and 28.696 s Docker. Both paths slowed in this set (+2.409 s Mise, +3.564 s Docker), so the smaller relative full-generation gap is not evidence that the bpf2go implementation caused a speedup. Host/guest load and CPU steal were not captured during the timed windows; no claim about the gap reduction is warranted.

## Profile and generated-output comparison

One additional instrumented warm full run per path measured Mise wall time at 34.438 s and Docker wall time at 31.260 s. Both invoked bpf2go 30 times, Clang 30 times, and `go generate` twice. Summed per-process Clang wall time was 65.966 s for Mise and 59.170 s for Docker; the summed per-process bpf2go inclusive times were 66.850 s and 60.090 s. These process totals overlap because architecture generation runs in parallel; they must not be added to estimate elapsed time. The profile points to longer Clang work on the Mise path as a plausible contributor, despite both reporting Clang 22.1.8; it does not isolate causality. Generated Go compilation is not part of either `generate` task. A separate cold-cache `go test -run '^$' ./pkg/internal/ebpf/...` diagnostic compiled generated packages in 75.848 s; it is not included in generation timings.

Across branch vs main, all 30 generated Go sources and 30 depfiles match, but 22/30 `.o` hashes differ. A representative generictracer x86 object has identical section names and only `.BTF` differs; this is not an exhaustive section comparison for the other 21 objects. Thus outputs are not wholly byte-identical; the evidence suggests metadata/toolchain-build differences may explain at least the representative object, but does not establish the cause for all differences.

The Mise generation logs contain zero Go 1.27.x toolchain-download mentions; the selected Mise Go stayed at 1.27.2 and no second toolchain was downloaded. Toolchain installation directories still contain pre-existing 1.27.1 and 1.27.2 installs.

## Evidence and reproduction

- `remeasure-bpf2go-prebuilt-20261014.sh` is the run script; `profile-bpf2go-20261014.sh` and `profile-docker-bpf2go-20261014.sh` reproduce the instrumented profiles.
- `logs/`, `profile/`, and `results/` contain raw evidence and checks. `check-elf-sections.py` documents the representative object comparison.
- `SHA256SUMS` checksums all files in this directory except itself.
