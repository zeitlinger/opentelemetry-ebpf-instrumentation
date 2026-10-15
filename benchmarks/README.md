# Mise migration benchmarks

Evidence for the proposal to manage OBI's tools and tasks with Mise
([PR #3729](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/pull/3729)).
Each directory has its own README with method, raw results and checksums.

| Directory | What | Where |
| --- | --- | --- |
| `go-format-lint/` | Warm Go format + full lint: Make, Make `-j8`, Mise (five runs each) | Host |
| `vm-bpf-generation/` | Warm BPF generation and no-op: `mise run generate` vs `make docker-generate`, same sources; plus prebuilt-bpf2go re-measurement and per-step profile | Ubuntu 24.04 KVM guest, 4 vCPU / 8 GiB |
| `vm-first-use/` | Cold first use: empty Mise/Go caches vs empty Docker store; setup-only timings | Same KVM guest |
| `vm-setup/` | Scripts used to provision and access the KVM guest | — |
| `ci-baseline/` | GitHub Actions job durations: last 20 successful `main` push runs, and PR #3729 runs | GitHub Actions |

Not included, to keep the branch small: source snapshots, worktrees, the generated
BPF objects (their SHA-256 hashes are in the results) and the VM disk images.
`SHA256SUMS` files may therefore list files that are not present here.
