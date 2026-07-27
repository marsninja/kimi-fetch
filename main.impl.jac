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
    if p.startswith("/") or p.startswith("-") {
        return False;
    }
    if p.find("..") >= 0 {
        return False;
    }
    i = 0;
    limit = len(p);
    while i < limit {
        c = ord(p[i]);
        alpha = (c >= 97 and c <= 122) or (c >= 65 and c <= 90);
        digit = c >= 48 and c <= 57;
        safe_punct = c == 45 or c == 46 or c == 47 or c == 95;
        if not (alpha or digit or safe_punct) {
            return False;
        }
        i += 1;
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

impl str_eq(a: &str, b: &str) -> bool {
    return a == b;
}

# Shell-quote one value. Commands are assembled by concatenating these
# single-interpolation pieces: a multi-interpolation f-string drops the
# single-quote characters between its placeholders (DOGFOOD.md issue 10).
impl qp(s: &str) -> own str {
    out: own str = f"'{s}'";
    return out;
}

impl starts_with(s: &str, prefix: &str) -> bool {
    return s.startswith(prefix);
}

impl contains(hay: &str, needle: &str) -> bool {
    return hay.find(needle) >= 0;
}

impl parse_leading_int(s: &str) -> int {
    i = 0;
    limit = len(s);
    while i < limit and (ord(s[i]) == 32 or ord(s[i]) == 9) {
        i += 1;
    }
    n = 0;
    got = False;
    while i < limit {
        c = ord(s[i]);
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

impl to_int(s: &str) -> int {
    limit = len(s);
    if limit == 0 {
        return -1;
    }
    n = 0;
    i = 0;
    while i < limit {
        c = ord(s[i]);
        if c < 48 or c > 57 {
            return -1;
        }
        n = n * 10 + (c - 48);
        i += 1;
    }
    return n;
}

impl first_hex_token(s: &str) -> own str {
    i = 0;
    limit = len(s);
    while i < limit {
        c = ord(s[i]);
        hex_digit = (c >= 48 and c <= 57) or (c >= 97 and c <= 102);
        if not hex_digit {
            break;
        }
        i += 1;
    }
    tok: own str = s[0:i];
    return tok;
}

impl parent_dir(p: &str) -> own str {
    i = len(p) - 1;
    while i >= 0 {
        if ord(p[i]) == 47 {
            out: own str = p[0:i];
            return out;
        }
        i -= 1;
    }
    return "";
}

impl sh(cmd: own str) -> int {
    rc = os.system(f"{cmd}");
    if rc == 0 {
        return 0;
    }
    code = rc // 256;
    if code == 0 {
        return 199;
    }
    return code;
}

impl read_file(path: &str) -> own str {
    with open(f"{path}") as f {
        body: own str = f.read();
        return body;
    }
    return "";
}

impl file_size(path: &str, tmp: &str) -> int {
    cmd: own str = "wc -c < " + qp(path) + " > " + qp(tmp) + " 2>/dev/null";
    rc = sh(cmd);
    if rc != 0 {
        return -1;
    }
    out: own str = read_file(tmp);
    return parse_leading_int(&out);
}

impl sha256_file(path: &str, tmp: &str) -> own str {
    plat: own str = f"{sys.platform}";
    tool: own str = "sha256sum";
    if str_eq(&plat, &"darwin") {
        tool = "shasum -a 256";
    }
    cmd: own str = tool + " " + qp(path) + " > " + qp(tmp);
    rc = sh(cmd);
    if rc != 0 {
        return "";
    }
    out: own str = read_file(tmp);
    tok: own str = first_hex_token(&out);
    return tok;
}

impl repo_api_url() -> own str {
    return "https://huggingface.co/api/models/moonshotai/Kimi-K3/tree/main?recursive=true";
}

impl repo_resolve_url(rel: &str) -> own str {
    url: own str = f"https://huggingface.co/moonshotai/Kimi-K3/resolve/main/{rel}";
    return url;
}

impl auth_flag() -> own str {
    t = os.getenv("HF_TOKEN");
    if t is None {
        return "";
    }
    tok: own str = f"{t}";
    if len(tok) == 0 or contains(&tok, &"'") {
        return "";
    }
    flag: own str = f"-H 'Authorization: Bearer {tok}'";
    return flag;
}

impl fetch_manifest(state: &str, refresh: bool) -> bool {
    mpath: own str = f"{state}/manifest.json";
    have = os.path.isfile(f"{mpath}");
    if have and not refresh {
        return True;
    }
    print("fetching manifest ...");
    tpath: own str = f"{state}/manifest.json.tmp";
    au: own str = auth_flag();
    url: own str = repo_api_url();
    cmd: own str = "curl -fsSL --retry 3 --retry-delay 2 " + au + " -o " + qp(&tpath) + " " + qp(
        &url
    );
    rc = sh(cmd);
    if rc != 0 {
        if have {
            print("warning: manifest refresh failed; using cached copy");
            return True;
        }
        print(f"error: manifest fetch failed (curl exit {rc})");
        return False;
    }
    body: own str = read_file(&tpath);
    if not starts_with(&body, &"[") {
        print("error: manifest response is not a JSON array");
        _ = sh(f"rm -f '{tpath}'");
        return False;
    }
    mv_cmd: own str = "mv -f " + qp(&tpath) + " " + qp(&mpath);
    if sh(mv_cmd) != 0 {
        print("error: could not finalize manifest");
        return False;
    }
    return True;
}

impl verify_part(part: &str, e: &FileEntry, tmp: &str) -> bool {
    sz = file_size(part, tmp);
    if sz != e.size {
        print(f"    verify failed: size {sz}, expected {e.size}");
        return False;
    }
    want: own str = f"{e.sha256}";
    if len(want) == 0 {
        return True;
    }
    got: own str = sha256_file(part, tmp);
    if not str_eq(&got, &want) {
        print(f"    verify failed: sha256 {got}, expected {want}");
        return False;
    }
    return True;
}

impl attempt_one(dest: &str, e: &FileEntry, tmp: &str) -> bool {
    fin: own str = f"{dest}/{e.path}";
    part: own str = f"{fin}.part";
    have = 0;
    if os.path.isfile(f"{part}") {
        have = file_size(&part, tmp);
    }
    if have > e.size {
        print("    stale oversized partial, restarting");
        _ = sh(f"rm -f '{part}'");
        have = 0;
    }
    if have < e.size {
        if have > 0 {
            print(f"    resuming from byte {have}");
        }
        au: own str = auth_flag();
        url: own str = repo_resolve_url(&e.path);
        cmd: own str = "curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -C - " + au + " -o " + qp(
            &part
        ) + " " + qp(&url);
        rc = sh(cmd);
        if rc != 0 {
            print(f"    curl failed (exit {rc})");
            return False;
        }
    }
    if not verify_part(&part, e, tmp) {
        _ = sh(f"rm -f '{part}'");
        return False;
    }
    mv_cmd: own str = "mv -f " + qp(&part) + " " + qp(&fin);
    if sh(mv_cmd) != 0 {
        print("    could not finalize file");
        return False;
    }
    return True;
}

impl download_one(dest: &str, e: &FileEntry, tmp: &str) -> bool {
    if attempt_one(dest, e, tmp) {
        return True;
    }
    print("    retrying from scratch");
    part: own str = f"{dest}/{e.path}.part";
    _ = sh(f"rm -f '{part}'");
    return attempt_one(dest, e, tmp);
}

impl print_usage() -> None {
    print("kimi-fetch: resumable downloader for huggingface.co/moonshotai/Kimi-K3");
    print("");
    print("usage: kimi-fetch [DEST] [flags]");
    print("  DEST                destination directory (default: Kimi-K3)");
    print("  --status            show per-file progress, download nothing");
    print("  --dry-run           list pending files, download nothing");
    print("  --refresh           re-fetch the manifest before starting");
    print("  --limit N           stop after downloading N files this run");
    print("  --include SUBSTR    only handle files whose path contains SUBSTR");
    print("  --help              show this help");
    print("");
    print("Interrupt it any time: partial files resume, finished files are");
    print("verified (size + sha256 for LFS) before taking their final name.");
}

impl run() -> int {
    dest: own str = "Kimi-K3";
    refresh = False;
    status_only = False;
    dry = False;
    limit = -1;
    only: own str = "";
    got_dest = False;
    argc = len(sys.argv);
    i = 1;
    while i < argc {
        a: own str = f"{sys.argv[i]}";
        if str_eq(&a, &"--refresh") {
            refresh = True;
        } elif str_eq(&a, &"--status") {
            status_only = True;
        } elif str_eq(&a, &"--dry-run") {
            dry = True;
        } elif str_eq(&a, &"--limit") {
            i += 1;
            if i >= argc {
                print("error: --limit needs a number");
                return 2;
            }
            la: own str = f"{sys.argv[i]}";
            limit = to_int(&la);
            if limit < 0 {
                print("error: --limit needs a non-negative number");
                return 2;
            }
        } elif str_eq(&a, &"--include") {
            i += 1;
            if i >= argc {
                print("error: --include needs a substring");
                return 2;
            }
            only = f"{sys.argv[i]}";
        } elif str_eq(&a, &"--help") or str_eq(&a, &"-h") {
            print_usage();
            return 0;
        } elif starts_with(&a, &"-") {
            print(f"error: unknown flag {a}");
            return 2;
        } else {
            if got_dest {
                print("error: more than one destination given");
                return 2;
            }
            dest = f"{sys.argv[i]}";
            got_dest = True;
        }
        i += 1;
    }
    if contains(&dest, &"'") {
        print("error: destination path may not contain a single quote");
        return 2;
    }
    state: own str = f"{dest}/.kimi-fetch";
    if sh(f"mkdir -p '{state}'") != 0 {
        print("error: cannot create destination directory");
        return 1;
    }
    if not fetch_manifest(&state, refresh) {
        return 1;
    }
    mpath: own str = f"{state}/manifest.json";
    tmp: own str = f"{state}/probe.tmp";
    src: own str = read_file(&mpath);

    total_files = 0;
    pos = 0;
    while True {
        e = next_entry(&src, pos);
        if e.kind == ENTRY_END {
            break;
        }
        if e.kind == ENTRY_BAD {
            print(f"error: unusable manifest entry at offset {pos}");
            print("(delete the manifest cache and re-run with --refresh)");
            return 1;
        }
        if e.kind == ENTRY_FILE {
            total_files += 1;
        }
        pos = e.next_pos;
    }

    idx = 0;
    done_before = 0;
    fetched = 0;
    filtered = 0;
    pending = 0;
    pending_bytes = 0;
    pos = 0;
    while True {
        e = next_entry(&src, pos);
        if e.kind == ENTRY_END {
            break;
        }
        pos = e.next_pos;
        if e.kind != ENTRY_FILE {
            continue;
        }
        idx += 1;
        if len(only) > 0 and not contains(&e.path, &only) {
            filtered += 1;
            continue;
        }
        fin: own str = f"{dest}/{e.path}";
        if os.path.isfile(f"{fin}") {
            done_before += 1;
            continue;
        }
        if status_only or dry {
            pending += 1;
            pending_bytes += e.size;
            part: own str = f"{fin}.part";
            if os.path.isfile(f"{part}") {
                have = file_size(&part, &tmp);
                print(f"partial  {e.path} ({have}/{e.size} bytes)");
            } else {
                print(f"pending  {e.path} ({e.size} bytes)");
            }
            continue;
        }
        pdir: own str = parent_dir(&e.path);
        if len(pdir) > 0 {
            full_dir: own str = f"{dest}/{pdir}";
            mk_cmd: own str = "mkdir -p " + qp(&full_dir);
            if sh(mk_cmd) != 0 {
                print("error: could not create parent directory");
                return 1;
            }
        }
        print(f"[{idx}/{total_files}] {e.path} ({e.size} bytes)");
        if not download_one(&dest, &e, &tmp) {
            print(f"error: giving up on {e.path} for this run; re-run to resume");
            return 1;
        }
        fetched += 1;
        if limit >= 0 and fetched >= limit {
            print(f"stopping: --limit {limit} reached");
            break;
        }
    }

    if status_only or dry {
        print(
            f"{done_before} done, {pending} pending ({pending_bytes} bytes) of {total_files} files"
        );
        return 0;
    }
    done_now = done_before + fetched;
    print(f"{done_now} of {total_files} files complete ({fetched} fetched this run)");
    if filtered > 0 {
        print(f"{filtered} files skipped by --include filter");
    }
    if done_now + filtered < total_files {
        print("run again to continue");
    } elif filtered == 0 {
        print("all files complete");
    }
    return 0;
}
