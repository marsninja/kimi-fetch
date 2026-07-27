"""Streaming scanner for the Hugging Face tree-API manifest JSON.

The manifest is one JSON array of tree entries. Building a list of parsed
entries is off the table under the zero-RC contract (append of heap elements
is E1406), so the scanner is a cursor: `next_entry(&src, pos)` parses the
next object and returns it together with the position to resume from.
"""

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

def obj_close(src: &str, brace: int, limit: int) -> int {
    depth = 0;
    i = brace;
    in_str = False;
    while i < limit {
        c = ord(src[i]);
        if in_str {
            if c == 92 {
                i += 2;
                continue;
            }
            if c == 34 {
                in_str = False;
            }
        } elif c == 34 {
            in_str = True;
        } elif c == 123 {
            depth += 1;
        } elif c == 125 {
            depth -= 1;
            if depth == 0 {
                return i + 1;
            }
        }
        i += 1;
    }
    return -1;
}

def str_field(src: &str, key: &str, start: int, end: int) -> own str {
    k = src.find(key, start);
    if k < 0 or k >= end {
        return "";
    }
    i = k + len(key);
    while i < end and ord(src[i]) == 32 {
        i += 1;
    }
    if i >= end or ord(src[i]) != 34 {
        return "";
    }
    i += 1;
    j = i;
    while j < end {
        c = ord(src[j]);
        if c == 92 {
            j += 2;
            continue;
        }
        if c == 34 {
            break;
        }
        j += 1;
    }
    if j >= end {
        return "";
    }
    out: own str = src[i:j];
    return out;
}

def int_field(src: &str, key: &str, start: int, end: int) -> int {
    k = src.find(key, start);
    if k < 0 or k >= end {
        return -1;
    }
    i = k + len(key);
    while i < end and ord(src[i]) == 32 {
        i += 1;
    }
    n = 0;
    got = False;
    while i < end {
        c = ord(src[i]);
        if c >= 48 and c <= 57 {
            n = n * 10 + (c - 48);
            got = True;
            i += 1;
        } else {
            break;
        }
    }
    if not got {
        return -1;
    }
    return n;
}

def strip_sha_prefix(s: &str) -> own str {
    if s.startswith("sha256:") {
        tail: own str = s[7:];
        return tail;
    }
    copy: own str = s[0:len(s)];
    return copy;
}

def lfs_sha(src: &str, start: int, end: int) -> own str {
    k = src.find("\"lfs\":", start);
    if k < 0 or k >= end {
        return "";
    }
    raw: own str = str_field(src, "\"oid\":", k, end);
    clean: own str = strip_sha_prefix(&raw);
    return clean;
}

def path_ok(p: &str) -> bool {
    if len(p) == 0 {
        return False;
    }
    if p.startswith("/") {
        return False;
    }
    if p.startswith("-") {
        return False;
    }
    if p.find("..") >= 0 {
        return False;
    }
    if p.find("'") >= 0 {
        return False;
    }
    if p.find("\\") >= 0 {
        return False;
    }
    return True;
}

def next_entry(src: &str, pos: int) -> own FileEntry {
    limit = len(src);
    start = src.find("{", pos);
    if start < 0 {
        return FileEntry(kind=ENTRY_END, path="", size=0, sha256="", next_pos=-1);
    }
    end = obj_close(src, start, limit);
    if end < 0 {
        return FileEntry(kind=ENTRY_BAD, path="", size=0, sha256="", next_pos=-1);
    }
    typ: own str = str_field(src, "\"type\":", start, end);
    if typ != "file" {
        return FileEntry(kind=ENTRY_SKIP, path="", size=0, sha256="", next_pos=end);
    }
    p: own str = str_field(src, "\"path\":", start, end);
    sz = int_field(src, "\"size\":", start, end);
    if sz < 0 or not path_ok(&p) {
        return FileEntry(kind=ENTRY_BAD, path=p, size=sz, sha256="", next_pos=end);
    }
    sha: own str = lfs_sha(src, start, end);
    return FileEntry(kind=ENTRY_FILE, path=p, size=sz, sha256=sha, next_pos=end);
}
