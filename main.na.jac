"""kimi-fetch: resumable, file-by-file downloader for moonshotai/Kimi-K3.

Single module by design: the native compiler currently compiles imported
modules under gc=cycles no matter what --gc/-toml settings say (DOGFOOD.md
issue 9), so the zero-RC proof (--gc none --enforce-nogc --assert-no-rc)
only covers a program whose code lives in one module. Declarations live
here; bodies live in main.impl.jac, an annex of this same module.

Transfers and hashing shell out to curl / shasum / sha256sum: the native
stdlib has no HTTP client or hash functions (and no way to stat a file
size — see DOGFOOD.md), so the binary orchestrates the ubiquitous system
tools instead. All dynamic shell arguments are single-quoted and every
manifest path is vetted by path_ok() before it can reach a command line.
"""

import sys;
import os;

glob ENTRY_END: int = 0;
glob ENTRY_FILE: int = 1;
glob ENTRY_SKIP: int = 2;
glob ENTRY_BAD: int = 3;

obj FileEntry {
    has kind: int;
    has path: own str;
    has size: int;
    has sha256: own str;
    has next_pos: int;
}

# --- manifest scanning ---
def obj_close(src: &str, brace: int, limit: int) -> int;
def str_field(src: &str, key: &str, start: int, end: int) -> own str;
def int_field(src: &str, key: &str, start: int, end: int) -> int;
def strip_sha_prefix(s: &str) -> own str;
def lfs_sha(src: &str, start: int, end: int) -> own str;
def path_ok(p: &str) -> bool;
def next_entry(src: &str, pos: int) -> own FileEntry;

# --- small string/shell primitives ---
def str_eq(a: &str, b: &str) -> bool;
def qp(s: &str) -> own str;
def starts_with(s: &str, prefix: &str) -> bool;
def contains(hay: &str, needle: &str) -> bool;
def parse_leading_int(s: &str) -> int;
def to_int(s: &str) -> int;
def first_hex_token(s: &str) -> own str;
def parent_dir(p: &str) -> own str;
def sh(cmd: own str) -> int;
def read_file(path: &str) -> own str;
def file_size(path: &str, tmp: &str) -> int;
def sha256_file(path: &str, tmp: &str) -> own str;

# --- repo endpoints ---
def repo_api_url() -> own str;
def repo_resolve_url(rel: &str) -> own str;
def auth_flag() -> own str;

# --- engine ---
def fetch_manifest(state: &str, refresh: bool) -> bool;
def verify_part(part: &str, e: &FileEntry, tmp: &str) -> bool;
def attempt_one(dest: &str, e: &FileEntry, tmp: &str) -> bool;
def download_one(dest: &str, e: &FileEntry, tmp: &str) -> bool;
def print_usage() -> None;
def run() -> int;

with entry:__main__ {
    sys.exit(run());
}
