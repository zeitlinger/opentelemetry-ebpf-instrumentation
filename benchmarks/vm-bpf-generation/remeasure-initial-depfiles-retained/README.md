# Superseded initial warm BPF generation measurement

> Diagnostic only; superseded by `../remeasure-20261014/`. The initial runner deleted generated Go/object outputs but left 30 `*_bpf*.go.d` sidecars in each source tree. This did force a full generation, but the corrected measurement deletes the sidecars too.

All timed runs were performed on the existing `obi-mise-bench` Ubuntu 24.04.5 KVM guest (Linux 6.8.0-142, AMD Ryzen 9 7900, 4 vCPU, 7.8 GiB RAM), not on the host. Docker 29.1.3 is available in the guest; the generator image was already present. Guest provisioning and VM image details are in `../README.md`.

## Sources and commands

- Main source: `origin/main` at the branch rebase base `a6207d767125db2355710502542451cc4b474d96`.
- Mise source: branch source `7a5f0146890090f312751f9cb14ceb4c5f32739f`, plus the current uncommitted `mise.toml`/`mise.lock` Go 1.27.2 pin update. The snapshot/config are under `branch/`.
- 280 BPF C/H inputs (excluding BPF tests) match byte-for-byte; file hashes are in `results/{main,branch}-bpf-inputs.sha256`.
- Commands: `mise run generate` and `make docker-generate`. Before each of the five timed full runs, the script deletes all generated `*_bpfel.go`, `*_bpfeb.go`, `*_bpfel.o`, and `*_bpfeb.o` files and asserts none remain. Each full run is followed by a timed no-op. The untimed warm-up runs both paths first.
- The Docker Make target uses `docker run --rm` and has no persistent Go cache mount. To satisfy the requested warm-cache conditions without changing Makefile, the test's temporary `docker` PATH wrapper adds the same two named cache volumes to every Docker `run`. The wrapper and runner are preserved here. `logs/docker-wrapper-invocations.txt` records each of the ten timed Docker invocations using those exact mounts; the warm-up call used the same wrapper.
- Mise tools and the generator image were installed/pulled before timing. Go module/build caches were populated by existing cache state and one untimed generation warm-up for each path. Setup/warm-up logs are in `logs/`.

## Results

Raw nanosecond samples are in `results/timings.csv`; medians and ranges are in `results/timing-summary.txt`.

| Path | Full generation (median; range) | No-op (median; range) |
|---|---:|---:|
| Mise | 32.498 s (31.405–33.542 s) | 0.091 s (0.090–0.094 s) |
| Main Make + Docker | 29.226 s (28.925–29.426 s) | 0.450 s (0.437–0.460 s) |

On this warm measurement, Mise no-op is about 5x faster (about 0.36 s saved). Full generation is about 3.27 s slower on Mise (about 11% relative to Docker); this measurement does not show a full-generation speedup from Mise. The no-op difference includes Docker container startup; no separate timing breakdown was taken. The full-run gap is not isolated: the Docker image runs Go 1.27.0 with `GOTOOLCHAIN=local`, Alpine clang 22.1.8, and a prebuilt bpf2go; Mise runs Go 1.27.2, a conda-forge Clang 22.1.8 build, and `go tool` bpf2go. Both use the same advertised clang/bpf2go versions, BPF flags, architecture targets, and two-way architecture parallelism, but the different Go/Clang builds and tool invocation remain confounders.

`results/cross-path-comparison.txt` compares the 60 final output hashes per path: all generated Go bindings match; 22/30 object files differ. A representative object section-level comparison found `.BTF` differed while all other sections matched (`results/section-comparison.txt`); this indicates metadata ordering rather than changed BPF instruction sections. Per-run hashes show rare single-object hash variation across repeated full builds: one object for some Mise runs and one object (not always the same one) for some Docker runs. Every per-sample no-op preserved that sample's full-generation hashes.

The Mise timed task logs contain no Go toolchain auto-download. `mise install` found Go 1.27.2 already installed; `mise exec -- go version` reports 1.27.2 with `GOTOOLCHAIN=auto`. The prior 1.27.1 install remains in the guest cache but is not selected.

`SHA256SUMS` covers the runner, cache wrapper, source snapshots, raw logs/results, and this README (excluding itself).
