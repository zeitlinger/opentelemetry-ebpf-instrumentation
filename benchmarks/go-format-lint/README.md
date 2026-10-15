# Go format + lint benchmark

Five warm, serial trials compared the legacy Make entry points with the Mise task graph on identical OBI application source.

**Update 2026-10-15:** [PR #3729](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/pull/3729) now runs golangci-lint after collectt (`wait_for`). In CI, running both at once made each recompute the type-check data the other would reuse, which slowed the lint jobs down. With that order Mise runs lint like `make -j8` does, and the local gain is gone:

| Timed path | Median | Five raw times (seconds) |
| --- | ---: | --- |
| `make -j8 fmt && make -j8 lint` | 7.491 s | 8.059, 7.491, 7.234, 8.335, 7.300 |
| `mise run fmt && mise run lint` (parallel, as above) | 5.283 s | 6.732, 5.124, 5.273, 7.320, 5.283 |
| `mise run fmt && mise run lint` with `wait_for` | 7.069 s | 8.855, 6.278, 7.069, 8.307, 6.449 |

Same worktrees and per-variant isolated caches as below, one warmup each, five alternating trials; the host had other load, hence the wider spread. Script and raw times: `wait-for-2026-10-15/`. The tables below are the original run.

| Timed path | Median | Five raw times (seconds) |
| --- | ---: | --- |
| `make fmt && make lint` | 7.246 s | 7.978, 7.246, 7.219, 7.152, 7.309 |
| `make -j8 fmt && make -j8 lint` | 7.180 s | 7.786, 7.180, 7.208, 7.146, 7.143 |
| `mise run fmt && mise run lint` | 5.199 s | 5.199, 5.237, 5.243, 5.159, 5.090 |

On the rebased source, Mise used about 28.3% less elapsed time than default Make and 27.6% less than Make `-j8` in this setup. The prior pre-rebase medians were 6.859 / 6.838 / 4.945 s; the times rose about 5–6%, while relative savings were essentially unchanged. That old run is retained under `history/pre-rebase-30f5/`. These numbers measure task scheduling on this workload; they do not show that Mise itself makes the linter faster or that Make cannot be restructured to parallelize lint checks. Both paths run natively, and tool installation is excluded.

## Source and toolchain controls

- Application source in both disposable worktrees: exact rebased HEAD `25ded36bfd194e98a3c7bff27b6081549e4c93e9` (`feat/mise-full-build`; rebased on `origin/main` `df8f55c473718b1f927faff0131460757b469388`).
- Legacy Makefile and original `internal/tools/go.mod`/`go.sum`: `origin/main` commit `df8f55c473718b1f927faff0131460757b469388`.
- Only those three legacy files were overlaid on the Make worktree. On the Mise worktree, the committed 2.13.2 pin was overlaid to 2.14.0 and `mise lock golangci-lint` refreshed the lockfile; this matches the uncommitted 2.14.0 pin update in the rebased feature worktree and does not change application source. Their exact original contents and the aligned tool-module result are archived under `legacy-overlay/` with SHA-256 checksums. The legacy tool module was updated with `go get -C internal/tools github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.14.0`; `prepare.sh` verifies that the result matches the archived aligned module files. This also updated that module's transitive tool dependencies. No root application dependency files were changed.
- Go: 1.27.2 in both paths. golangci-lint: 2.14.0 in both paths. Mise's pinned binary reports its build Go version as 1.27.0; the Make `go tool` command builds from the tool module under Go 1.27.2.
- Both command paths included `fmt` followed by the full `lint` task. Make ran `fmt` then `lint`; `-j8` applied to each Make invocation. Mise ran `mise run fmt` then `mise run lint`, with the Mise task graph scheduling its independent lint prerequisites concurrently by default.
- BPF generated `*_bpfel.go`, `*_bpfeb.go`, `*_bpfel.o`, and `*_bpfeb.o` files are ignored, not part of the source commit. For the measured runs, `prepare.sh` generated the BPF outputs in the Mise worktree, then copied the same outputs into the Make worktree. Generation is excluded from timing.
- Each variant had separate `GOCACHE`, `GOMODCACHE`, `GOLANGCI_LINT_CACHE`, and `XDG_CACHE_HOME`; each received one successful, unmeasured warmup before its five timed trials. The private `github.com/grafana/go-offsets-tracker@v0.1.7` module (needed by the rebased source) was copied identically from the host module cache into each separate `GOMODCACHE` before the warmup; the caches were then independent. The mise-managed Go and golangci-lint installations were already present; installation/setup was excluded. No Docker was used.
- Trials were serial, with a rotating order to balance position effects: Make / Make -j8 / Mise; Make -j8 / Mise / Make; Mise / Make / Make -j8, repeated as needed. All warmups and measured trials passed.

## Machine and run details

- Linux x86_64; AMD Ryzen 9 7900, 12 cores / 24 threads; 24 logical CPUs available; 91.4 GiB RAM.
- GNU Make 4.3; Mise 2026.10.7; Bash; `/usr/bin/time` was unavailable, so the harness uses Bash's `time` builtin with millisecond formatting.
- The Mise job setting was 8 (`mise settings get jobs`); it was not overridden for the benchmark. Make default was serial; the alternate used `-j8`. The host had 24 logical CPUs available.
- `results.tsv` is the raw trial table; `raw-logs.tar.gz` preserves stdout and stderr for every measured run, with paths corresponding to the table. The previous run at source `30f5e640b` remains archived separately under `history/pre-rebase-30f5/`; its medians were 6.859 / 6.838 / 4.945 s. `measure.sh` contains the timed command sequence and alternating schedule.
- These artifacts are being prepared on the separate worktree for remote branch `gregor/gregor/benchmark-mise-bpf-generation`, currently at `e363b9d884d79d1614278faaf6876355cbeb7239`; the artifact changes are not committed or pushed pending review.

## Reproduce

Use a checkout with the source and Make-overlay commits available, and a durable worktree directory outside that checkout. `prepare.sh` creates fresh detached worktrees, installs the project tools, generates BPF outputs, and applies the controlled legacy overlay. Setup is intentionally not timed.

```sh
export OBI_REPO=/path/to/opentelemetry-ebpf-instrumentation
export WORKTREE_ROOT=/path/to/durable/benchmark-worktrees
./prepare.sh

export MAKE_DIR="$WORKTREE_ROOT/make"
export MISE_DIR="$WORKTREE_ROOT/mise"
export BENCH_DIR=/path/to/durable/benchmark-results
./measure.sh
```

The harness pre-seeds only the private module above from the host Go module cache (or the Mise worktree Go module cache via `mise -C "$MISE_DIR" exec -- go env GOMODCACHE`), then uses isolated per-variant caches; run each variant once with the same command sequence before starting `measure.sh` to warm them. It writes logs and appends raw timings to `$BENCH_DIR/results.tsv`; set `BENCH_DIR` to a new empty directory for each complete run. The prior pre-rebase run is retained at `history/pre-rebase-30f5/` and is not the primary result.
