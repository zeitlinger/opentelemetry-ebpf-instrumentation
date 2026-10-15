> Historical, superseded run: this benchmark used pre-rebase source commit `30f5e640bd0d0addfc95bb809b3f3381d014eed5`. Current primary results use `25ded36bfd194e98a3c7bff27b6081549e4c93e9`; see the parent README and `results.tsv`.

# Go format + lint benchmark

Five warm, serial trials compared the legacy Make entry points with the Mise task graph on identical OBI application source.

| Timed path | Median | Five raw times (seconds) |
| --- | ---: | --- |
| `make fmt && make lint` | 6.859 s | 6.862, 6.853, 6.817, 6.859, 6.888 |
| `make -j8 fmt && make -j8 lint` | 6.838 s | 6.821, 6.899, 6.800, 6.852, 6.838 |
| `mise run fmt && mise run lint` | 4.945 s | 4.968, 4.954, 4.921, 4.916, 4.945 |

Mise used about 27.9% less elapsed time than default Make and 27.7% less than Make `-j8` in this setup. These numbers measure task scheduling on this workload; they do not show that Mise itself makes the linter faster or that Make cannot be restructured to parallelize lint checks. Both paths run natively, and tool installation is excluded.

## Source and toolchain controls

- Application source in both disposable worktrees: `30f5e640bd0d0addfc95bb809b3f3381d014eed5` (`feat/mise-full-build` / PR #3729 head at measurement time).
- Legacy Makefile and original `internal/tools/go.mod`/`go.sum`: `origin/main` commit `df8f55c473718b1f927faff0131460757b469388`.
- Only those three legacy files were overlaid on the Make worktree. Their exact original contents and the aligned tool-module result are archived under `legacy-overlay/` with SHA-256 checksums. The legacy tool module was updated with `go get -C internal/tools github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.14.0`; `prepare.sh` verifies that the result matches the archived aligned module files. This also updated that module's transitive tool dependencies. No root application dependency files were changed.
- Go: 1.27.2 in both paths. golangci-lint: 2.14.0 in both paths. Mise's pinned binary reports its build Go version as 1.27.0; the Make `go tool` command builds from the tool module under Go 1.27.2.
- Both command paths included `fmt` followed by the full `lint` task. Make ran `fmt` then `lint`; `-j8` applied to each Make invocation. Mise ran `mise run fmt` then `mise run lint`, with the Mise task graph scheduling its independent lint prerequisites concurrently by default.
- BPF generated `*_bpfel.go`, `*_bpfeb.go`, `*_bpfel.o`, and `*_bpfeb.o` files are ignored, not part of the source commit. For the measured runs, the 60 generated files present in the PR checkout were copied byte-for-byte into both scratch worktrees. For a fresh reproduction, `prepare.sh` generates them in the Mise worktree, then copies the same outputs into the Make worktree. Generation is excluded from timing.
- Each variant had separate `GOCACHE`, `GOMODCACHE`, `GOLANGCI_LINT_CACHE`, and `XDG_CACHE_HOME`; each received one successful, unmeasured warmup before its five timed trials. The mise-managed Go and golangci-lint installations were already present; installation/setup was excluded. No Docker was used.
- Trials were serial, with a rotating order to balance position effects: Make / Make -j8 / Mise; Make -j8 / Mise / Make; Mise / Make / Make -j8, repeated as needed. All warmups and measured trials passed.

## Machine and run details

- Linux x86_64; AMD Ryzen 9 7900, 12 cores / 24 threads; 24 logical CPUs available; 91.4 GiB RAM.
- GNU Make 4.3; Mise 2026.10.7; Bash; `/usr/bin/time` was unavailable, so the harness uses Bash's `time` builtin with millisecond formatting.
- The Mise job setting was 8 (`mise settings get jobs`); it was not overridden for the benchmark. Make default was serial; the alternate used `-j8`. The host had 24 logical CPUs available.
- `results.tsv` is the raw trial table; `raw-logs.tar.gz` preserves stdout and stderr for every measured run, with paths corresponding to the table. `measure.sh` contains the timed command sequence and alternating schedule.
- These artifacts are being prepared on the separate worktree for remote branch `gregor/gregor/benchmark-mise-bpf-generation`, currently at `e363b9d884d79d1614278faaf6876355cbeb7239`; the artifact changes are not committed or pushed pending review.

## Reproduce

Use a checkout with the two source commits available, and a durable worktree directory outside that checkout. `prepare.sh` creates fresh detached worktrees, installs the project tools, generates BPF outputs, and applies the controlled legacy overlay. Setup is intentionally not timed.

```sh
export OBI_REPO=/path/to/opentelemetry-ebpf-instrumentation
export WORKTREE_ROOT=/path/to/durable/benchmark-worktrees
./prepare.sh

export MAKE_DIR="$WORKTREE_ROOT/make"
export MISE_DIR="$WORKTREE_ROOT/mise"
export BENCH_DIR=/path/to/durable/benchmark-results
./measure.sh
```

The harness expects warmed caches: run each variant once with the same command sequence before starting `measure.sh`. It writes logs and appends raw timings to `$BENCH_DIR/results.tsv`; set `BENCH_DIR` to a new empty directory for each complete run.
