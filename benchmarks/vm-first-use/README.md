# Task 1 first-use Docker vs Mise benchmark

All trials ran in the disposable Ubuntu 24.04.5 KVM guest in the sibling `kvm-docker` directory. Host CPU: AMD Ryzen 9 7900 12-Core Processor (24 online threads). Guest CPU: same exposed model, 4 vCPU / 8 GiB; guest Linux 6.8.0-142, amd64; Docker 29.1.3 / Buildx 0.30.1. Main source commit `a6207d767125db2355710502542451cc4b474d96`; Mise branch commit `7a5f0146890090f312751f9cb14ceb4c5f32739f`.

First-use definitions:
- Mise: fresh source copy, zero generated BPF artifacts, empty per-run `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `GOMODCACHE`, and `GOCACHE`; timed `mise run generate`.
- Docker: fresh source copy, zero generated BPF artifacts, Docker and containerd stores reset so the generator image was not local; timed `make docker-generate` (which includes the image pull and generation).
- Each full-task variant has five runs. Per-run metrics, full task logs, output hashes, and original console captures are preserved below.
- Setup-only was separately timed in five additional clean repetitions for Mise tool install and Docker image pull. Each Docker pull trial reset the Docker/containerd stores first, then timed only `docker pull`.

## Full first-use task durations

| Variant | Runs (seconds) | Median | Range |
| --- | --- | ---: | ---: |
| Mise `mise run generate` | 143.048, 158.491, 163.553, 156.790, 161.485 | 158.491 s | 143.048–163.553 s |
| Main `make docker-generate` | 142.188, 120.358, 116.872, 109.300, 96.970 | 116.872 s | 96.970–142.188 s |

These are end-to-end first-use times; Docker includes pulling its generator image, Mise includes installing configured tools, and both task paths also fetched Go/module dependencies. Do not subtract the standalone setup medians to claim an execution-only time: the setup and task trials are independent, and dependency/network activity also occurs during generation.

## Standalone clean setup durations

| Setup | Runs (seconds) | Median | Range |
| --- | --- | ---: | ---: |
| Mise `mise install` (8 tools; empty data/cache dirs) | 52.537, 54.455, 51.851, 54.104, 51.518 | 52.537 s | 51.518–54.455 s |
| `docker pull ghcr.io/open-telemetry/obi-generator:0.2.17` (empty Docker store) | 49.724, 55.840, 44.110, 52.871, 44.263 | 49.724 s | 44.110–55.840 s |

The image digest was `sha256:1ae9406f2566e32ccf5d8ba8e5ff0586a322300ae82870988ad605429021174a` in all Docker trials. The first four Mise install-only runs succeeded. The initial fifth attempt failed because the guest root filesystem filled; that is preserved as a disk-capacity failure, not a network failure. After copying and checksumming results, isolated task1 caches were removed and a clean retry succeeded at 51.518 s. Thus the five values above are five successful runs, with the failed attempt separately documented.

## Tool versions seen during full runs

- Host Mise: 2026.9.16.
- Mise path: pinned Go 1.27.1 toolchain for `internal/tools`, Go 1.27.2 auto-selected for root module, Clang 22.1.8 (conda-forge), `bpf2go` module `github.com/cilium/ebpf` v0.22.0.
- Main generator image: `ghcr.io/open-telemetry/obi-generator:0.2.17` above; its base Go is 1.27.0, Clang/LLVM 22.1.8 (Alpine package), and bpf2go v0.22.0.

## Raw data and checksums

- `sources/`: source snapshots and their SHA256SUMS.
- `results/`: selected per-run metrics, full stdout/stderr logs, and generated artifact SHA manifests. `task1-run-artifacts.tar.gz` is the same raw set in one archive.
- `setup-only-logs/`: per-run clean install and pull metrics/logs; includes failed disk-full run and successful retry.
- `logs-*.txt` and `mise-install-only-runs.txt`: original console captures.
- `SHA256SUMS`: checksums for all Task1 evidence files except this checksum file itself.
