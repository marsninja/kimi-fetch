# kimi-fetch

A deliberately small, deliberately robust downloader for one Hugging Face
repository: [moonshotai/Kimi-K3](https://huggingface.co/moonshotai/Kimi-K3/tree/main).

Inspired by [HuggingFaceModelDownloader](https://github.com/bodaay/HuggingFaceModelDownloader),
reduced to a single job: faithfully download every file of Kimi-K3, one file at
a time, and **survive being stopped at any moment**. Run it again and it picks
up exactly where it left off — mid-file, mid-list, whenever — until the full
set of files is complete and verified.

`kimi-fetch` is written in [Jac](https://www.jaseci.org/) and compiled to a
standalone native binary. Every module passes Jac's ownership/borrow checker
under the zero-RC contract: the shipped binary contains **no garbage collector
and no reference counting** — every allocation has a statically determined
free point, proven at build time with `--enforce-nogc --assert-no-rc`.

## Usage

```bash
kimi-fetch [DEST]           # download everything into DEST (default ./Kimi-K3)
kimi-fetch DEST --status    # show per-file progress, download nothing
kimi-fetch DEST --dry-run   # list what would be downloaded
kimi-fetch DEST --refresh   # re-fetch the file manifest first
```

Stop it however you like — Ctrl-C, `kill -9`, power loss. State lives entirely
on disk:

- the file manifest is cached at `DEST/.kimi-fetch/manifest.json`
- an in-flight file downloads to `<name>.part` and resumes with a byte-range
  request from wherever it stopped
- a file is renamed to its final name only after its size — and for LFS files
  its SHA-256 — has been verified, so a finished filename is always a good file

## Building

Requires the `jac` toolchain and `curl` on `PATH` (plus `shasum`/`sha256sum`
for verification, present on stock macOS/Linux).

```bash
jac nacompile main.na.jac --gc none --enforce-nogc --assert-no-rc -o kimi-fetch
```

Release binaries for Linux x86_64 and macOS arm64 are produced by the release
workflow from exactly that command and attached to GitHub Releases.

## Dogfood notes

This project doubles as a dogfooding exercise for Jac's native + ownership
pathway; issues and paper cuts found along the way are recorded in
[DOGFOOD.md](DOGFOOD.md).
