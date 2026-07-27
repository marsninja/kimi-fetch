test "plain file entry parses" {
    m: own str = "[{\"type\":\"file\",\"oid\":\"62375aaf\",\"size\":1639,\"path\":\".gitattributes\"}]";
    e = next_entry(&m, 0);
    assert e.kind == ENTRY_FILE;
    assert e.path == ".gitattributes";
    assert e.size == 1639;
    assert e.sha256 == "";
    assert e.next_pos > 0;
}

test "lfs entry yields sha256 and scan terminates" {
    m: own str = "[{\"type\":\"file\",\"oid\":\"fb73b5d2\",\"size\":2341216112,\"lfs\":{\"oid\":\"975584c00f85\",\"size\":2341216112,\"pointerSize\":135},\"xetHash\":\"a8211e23\",\"path\":\"model-00001-of-000096.safetensors\"}]";
    e = next_entry(&m, 0);
    assert e.kind == ENTRY_FILE;
    assert e.path == "model-00001-of-000096.safetensors";
    assert e.size == 2341216112;
    assert e.sha256 == "975584c00f85";
    tail = next_entry(&m, e.next_pos);
    assert tail.kind == ENTRY_END;
}

test "sha256 prefix is stripped" {
    m: own str = "[{\"type\":\"file\",\"size\":5,\"lfs\":{\"oid\":\"sha256:deadbeef\"},\"path\":\"a.bin\"}]";
    e = next_entry(&m, 0);
    assert e.sha256 == "deadbeef";
}

test "directory entries are skipped then files parse" {
    m: own str = "[{\"type\":\"directory\",\"oid\":\"44cb3966\",\"size\":0,\"path\":\"assets\"},{\"type\":\"file\",\"oid\":\"870b8be6\",\"size\":87988,\"path\":\"assets/kimi-logo.png\"}]";
    d = next_entry(&m, 0);
    assert d.kind == ENTRY_SKIP;
    e = next_entry(&m, d.next_pos);
    assert e.kind == ENTRY_FILE;
    assert e.path == "assets/kimi-logo.png";
    assert e.size == 87988;
}

test "empty array ends immediately" {
    m: own str = "[]";
    e = next_entry(&m, 0);
    assert e.kind == ENTRY_END;
}

test "traversal and quoting hazards are rejected" {
    bad1: own str = "[{\"type\":\"file\",\"size\":5,\"path\":\"../evil\"}]";
    e1 = next_entry(&bad1, 0);
    assert e1.kind == ENTRY_BAD;
    bad2: own str = "[{\"type\":\"file\",\"size\":5,\"path\":\"/etc/passwd\"}]";
    e2 = next_entry(&bad2, 0);
    assert e2.kind == ENTRY_BAD;
    bad3: own str = "[{\"type\":\"file\",\"size\":5,\"path\":\"a'b\"}]";
    e3 = next_entry(&bad3, 0);
    assert e3.kind == ENTRY_BAD;
}

test "escaped quote in a path survives scanning and is rejected" {
    m: own str = "[{\"type\":\"file\",\"size\":5,\"path\":\"we\\\"ird\"},{\"type\":\"file\",\"size\":7,\"path\":\"ok.txt\"}]";
    e = next_entry(&m, 0);
    assert e.kind == ENTRY_BAD;
    f = next_entry(&m, e.next_pos);
    assert f.kind == ENTRY_FILE;
    assert f.path == "ok.txt";
}

test "missing size is rejected" {
    m: own str = "[{\"type\":\"file\",\"path\":\"x.txt\"}]";
    e = next_entry(&m, 0);
    assert e.kind == ENTRY_BAD;
}

test "parent_dir splits at last slash" {
    a: own str = "assets/deep/logo.png";
    d: own str = parent_dir(&a);
    assert d == "assets/deep";
    b: own str = "top.txt";
    d2: own str = parent_dir(&b);
    assert d2 == "";
}

test "int parsing helpers" {
    w: own str = "   12345\n";
    assert parse_leading_int(&w) == 12345;
    n1: own str = "42";
    assert to_int(&n1) == 42;
    n2: own str = "4x";
    assert to_int(&n2) == -1;
    n3: own str = "";
    assert to_int(&n3) == -1;
}

test "qp shell-quotes one value" {
    s: own str = "a b";
    q: own str = qp(&s);
    assert q == "'a b'";
}

test "first_hex_token stops at first non-hex" {
    o: own str = "975584c00f85  model.safetensors\n";
    t: own str = first_hex_token(&o);
    assert t == "975584c00f85";
}

test "path whitelist rejects shell metacharacters" {
    ok1: own str = "model-00001-of-000096.safetensors";
    assert path_ok(&ok1);
    ok2: own str = "assets/kimi-logo.png";
    assert path_ok(&ok2);
    bad1: own str = "a b";
    assert not path_ok(&bad1);
    bad2: own str = "a$(reboot)/x";
    assert not path_ok(&bad2);
    bad3: own str = "a`b";
    assert not path_ok(&bad3);
}

test "resolve url composes" {
    r: own str = "config.json";
    u: own str = repo_resolve_url(&r);
    assert u == "https://huggingface.co/moonshotai/Kimi-K3/resolve/main/config.json";
}

test "file_size and sha256_file agree with the shell" {
    _ = sh("mkdir -p /tmp/kimi_fetch_test");
    p: own str = "/tmp/kimi_fetch_test/x.txt";
    with open(f"{p}", "w") as f {
        f.write("abc");
    }
    t: own str = "/tmp/kimi_fetch_test/probe.tmp";
    assert file_size(&p, &t) == 3;
    h: own str = sha256_file(&p, &t);
    assert h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
}
