# Warm BPF generation remeasurement

All runs were performed on the same existing Ubuntu 24.04.5 KVM guest (`obi-mise-bench`, Linux 6.8.0-142, AMD Ryzen 9 7900, 4 vCPU, 7.8 GiB RAM), not on the host. Docker 29.1.3 is installed in the guest; the generator image was already pulled. VM provisioning/image details are in `../README.md`.

## Sources and method

- Main source: `origin/main` at the branch rebase base `a6207d767125db2355710502542451cc4b474d96`.
- Mise source: `feat/mise-full-build` snapshot at `7a5f0146890090f312751f9cb14ceb4c5f32739f`, with current uncommitted `mise.toml`/`mise.lock` Go 1.27.2 pin update overlaid. Source snapshots are under `branch/` and `main/`.
- The 280 BPF C/H input files (excluding BPF tests) are byte-identical; the file-by-file hashes are in `results/{main,branch}-bpf-inputs.sha256`.
- Timed commands: `mise run generate` and `make docker-generate`. The runner deletes generated Go bindings, objects, and `.go.d` dependency sidecars before every full run, then asserts none remain. Each full run is immediately followed by a timed no-op. Both paths also get one untimed full-generation warm-up after tools/image are ready and caches are populated.
- Main's `docker-generate` runs an ephemeral `docker run --rm` and ordinarily has no persistent Go cache mount. To meet the requested warm-cache conditions without changing Makefile, the temporary `docker` PATH wrapper injects named volumes at the image's actual cache paths: `obi-bpf-remeasure-gomodcache` → `/go/pkg/mod`; `obi-bpf-remeasure-gocache` → `/tmp/go-build`. The Make target itself is unchanged. `logs/docker-wrapper-invocations.txt` records all 11 invocations (one warm-up plus ten timed samples) using these same mounts; the wrapper and runner are preserved here.
- Mise tools and the generator image were installed/pulled before timing. The Mise module/build cache was already populated; each path ran an untimed warm-up. Setup and warm-up logs are under `logs/`.

## Results

Raw nanosecond samples are in `results/timings.csv`; medians and ranges are in `results/timing-summary.txt`.

| Path | Full generation (median; range) | No-op (median; range) |
|---|---:|---:|
| Mise | 33.272 s (32.850–33.808 s) | 0.090 s (0.089–0.093 s) |
| Main Make + Docker | 28.696 s (28.590–28.895 s) | 0.442 s (0.424–0.451 s) |

On this warm comparison, Mise no-op is about 4.9× faster, saving about 0.35 s. Full generation is about 4.58 s slower with Mise (about 16% of Docker's median); the measurement does **not** show a full-generation speedup from Mise. No separate Docker startup/bind-mount timing was taken; the no-op comparison includes that overhead.

The full-run difference is not isolated. The Docker image actually runs Go 1.27.0 with `GOTOOLCHAIN=local`, Alpine clang 22.1.8, and its prebuilt bpf2go. The Mise path uses Go 1.27.2, a conda-forge Clang 22.1.8 build, and `go tool` bpf2go. Both advertise clang 22.1.8 and bpf2go v0.22.0, use the same BPF flags, and generate both architectures with two-way architecture parallelism, but the actual Go/Clang builds and bpf2go invocation differ. The timing data does not isolate which difference accounts for the full-generation gap.

## Output checks

`results/cross-path-comparison.txt` compares final full-generation output hashes: all 30 Go bindings and all 30 `.go.d` files match; 22/30 object files differ. A representative `generictracer/bpf_x86_bpfel.o` section comparison found `.BTF` differed while the other 150 non-empty sections matched (`results/section-comparison.txt`), indicating metadata-order differences rather than changed BPF program instructions. This section-level check is representative, not exhaustive across all mismatches.

Per-run hashes show branch outputs were identical across all five full runs. Main had one or two object-hash variations in some samples. In every pair, the no-op output hashes matched that sample's preceding full generation exactly. See `results/stability.txt` and the full per-run hash manifests.

The Mise timed logs contain no `go: downloading go1.27.*` messages. `mise install` found Go 1.27.2 already installed; `mise exec -- go version` reports 1.27.2 with `GOTOOLCHAIN=auto`. An older Go 1.27.1 install remains in the guest tool cache but was not selected; no second Go toolchain was downloaded during the Mise task. The Docker generator image uses Go 1.27.0 with `GOTOOLCHAIN=local`, despite the source go.mod toolchain directive being Go 1.27.2.

`SHA256SUMS` covers the runner, cache wrapper, source snapshots, raw logs/results, and this README (excluding itself).
