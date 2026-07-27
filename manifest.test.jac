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
