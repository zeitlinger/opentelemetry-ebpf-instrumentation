# Task 3: current-main BPF generation parity and Mise generator image

Execution ran in the disposable Ubuntu 24.04.5 KVM guest (Linux 6.8.0-142, amd64, 4 vCPU / 8 GiB) on a host with an AMD Ryzen 9 7900 12-Core Processor (24 online threads); guest exposed the same CPU model. Docker 29.1.3 / Buildx 0.30.1. No primary PR worktree was edited. Isolated branch/main sources are in `sources/`, isolated guest worktrees/runs are in `worktrees/` (host snapshots), and the resulting metrics/logs/hashes and output artifacts are under `results/`.

See `results/task3-analysis.txt` for the hash comparison and interpretation. `results/runs/` preserves full logs, metrics, and generated SHA256 manifests. `results/outputs/` contains both runs' 120 generated files (60 each); `generated-bpf-outputs.tar.gz` is the same set archived. BPF C/H inputs are byte-identical across the two snapshots (280 files each), with hash lists in `sources/`.

The branch generator-image task `mise run generator-image-build` succeeded in the isolated branch worktree. A warm-cache verification took 3.651 s (exit 0), producing OCI manifest `sha256:02432f30bf2a66f9f476f3d2b73e70803634cf7c8c4e5f42f1164d266a9c5ff2` and an OCI layout of 1,290,896,285 bytes. We loaded the same built image with buildx for inspection; tool versions are in `results/generator-tool-versions.txt`. No application/release image was built.

`SHA256SUMS` checks all Task3 evidence (excluding the checksum file itself).
