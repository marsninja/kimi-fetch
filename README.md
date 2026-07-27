# kimi-fetch

A deliberately small, deliberately robust downloader for one Hugging Face
repository: [moonshotai/Kimi-K3](https://huggingface.co/moonshotai/Kimi-K3/tree/main).

Inspired by [HuggingFaceModelDownloader](https://github.com/bodaay/HuggingFaceModelDownloader),
reduced to a single job: faithfully download every file of Kimi-K3, one file at
a time, and **survive being stopped at any moment**. Run it again and it picks
up exactly where it left off — mid-file, mid-list, whenever — until the full
set of files is complete and verified.

`kimi-fetch` is written in [Jac](https://www.jaseci.org/) and compiled to a
~68 KB standalone native binary. Every function passes Jac's ownership/borrow
checker under the zero-RC contract: the shipped binary contains **no garbage
collector and no reference counting** — every allocation has a statically
determined free point, proven at build time by
`--gc none --enforce-nogc --assert-no-rc`.

## Usage

```bash
kimi-fetch [DEST] [flags]     # download everything into DEST (default ./Kimi-K3)
```

| Flag | Effect |
|---|---|
| `--status` | show per-file progress (done / partial / pending), download nothing |
| `--dry-run` | list pending files, download nothing |
| `--refresh` | re-fetch the file manifest before starting |
| `--limit N` | stop after downloading N files this run |
| `--include SUBSTR` | only handle files whose path contains SUBSTR |

`HF_TOKEN` in the environment is passed to Hugging Face as a bearer token when
set (not needed for this public repo, but helps with rate limits).

Stop it however you like — Ctrl-C, `kill -9`, power loss. State lives entirely
on disk:

- the file manifest is cached at `DEST/.kimi-fetch/manifest.json`, fetched
  atomically (written to a temp name, validated, then renamed)
- an in-flight file downloads to `<name>.part` and resumes from its current
  byte offset with an HTTP range request
- a file takes its final name only after its size — and, for LFS files, its
  SHA-256 — has been verified, so a finished filename is always a good file;
  a corrupted partial is detected at verify time, deleted, and re-fetched
  from scratch in the same run

The full set is ~1.56 TB across 100+ files, most of them ~2.3 GB
safetensors shards. `--include`/`--limit` make it easy to take just the
configs/tokenizer or to fetch the set in bounded sessions.

## Runtime dependencies

`curl` on `PATH` (transfers), plus `wc` and `shasum`/`sha256sum`
(verification) — all present on stock macOS and Linux. The binary itself
depends on nothing else: no Python, no libraries.

## Building

Requires the `jac` toolchain:

```bash
jac nacompile main.na.jac --gc none --enforce-nogc --assert-no-rc -o kimi-fetch
```

`jac check .` gates types and the ownership contract; `jac test main.na.jac`
runs the test suite. CI runs all three on Linux x86_64 and macOS arm64, and
the release workflow produces binaries from exactly that headless nacompile
command and attaches them to [GitHub Releases](../../releases).

## Dogfood notes

This project doubles as a dogfooding exercise for Jac's native + ownership
pathway; compiler issues and guide gaps found along the way are recorded in
[DOGFOOD.md](DOGFOOD.md) — several of them shaped this tool's architecture.
