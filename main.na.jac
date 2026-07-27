"""kimi-fetch: resumable, file-by-file downloader for moonshotai/Kimi-K3.

Single module by design: the native compiler currently compiles imported
modules under gc=cycles no matter what --gc/-toml settings say (DOGFOOD.md
issue 9), so the zero-RC proof (--gc none --enforce-nogc --assert-no-rc)
only covers a program whose code lives in one module. Declarations live
here; bodies live in main.impl.jac, an annex of this same module.
"""

import sys;

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

def obj_close(src: &str, brace: int, limit: int) -> int;
def str_field(src: &str, key: &str, start: int, end: int) -> own str;
def int_field(src: &str, key: &str, start: int, end: int) -> int;
def strip_sha_prefix(s: &str) -> own str;
def lfs_sha(src: &str, start: int, end: int) -> own str;
def path_ok(p: &str) -> bool;
def next_entry(src: &str, pos: int) -> own FileEntry;

def read_file(path: &str) -> own str;
def run() -> int;

with entry:__main__ {
    sys.exit(run());
}
