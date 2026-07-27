impl obj_close(src: &str, brace: int, limit: int) -> int {
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

impl str_field(src: &str, key: &str, start: int, end: int) -> own str {
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

impl int_field(src: &str, key: &str, start: int, end: int) -> int {
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

impl strip_sha_prefix(s: &str) -> own str {
    if s.startswith("sha256:") {
        tail: own str = s[7:];
        return tail;
    }
    copy: own str = s[0:len(s)];
    return copy;
}

impl lfs_sha(src: &str, start: int, end: int) -> own str {
    k = src.find("\"lfs\":", start);
    if k < 0 or k >= end {
        return "";
    }
    raw: own str = str_field(src, "\"oid\":", k, end);
    clean: own str = strip_sha_prefix(&raw);
    return clean;
}

impl path_ok(p: &str) -> bool {
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

impl next_entry(src: &str, pos: int) -> own FileEntry {
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

impl read_file(path: &str) -> own str {
    with open(f"{path}") as f {
        body: own str = f.read();
        return body;
    }
    return "";
}

impl run() -> int {
    if len(sys.argv) < 2 {
        print("usage: kimi-fetch <manifest.json>");
        return 1;
    }
    src: own str = read_file(&sys.argv[1]);
    pos = 0;
    files = 0;
    dirs = 0;
    total_bytes = 0;
    lfs = 0;
    while True {
        e = next_entry(&src, pos);
        if e.kind == ENTRY_END {
            break;
        }
        if e.kind == ENTRY_BAD {
            print(f"bad entry at {pos}");
            return 1;
        }
        if e.kind == ENTRY_FILE {
            files += 1;
            total_bytes += e.size;
            if e.sha256 != "" {
                lfs += 1;
            }
        } else {
            dirs += 1;
        }
        pos = e.next_pos;
    }
    print(f"files={files} lfs={lfs} dirs={dirs} bytes={total_bytes}");
    return 0;
}
