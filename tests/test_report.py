"""tools/report.py on synthetic logs in the harness's log vocabulary: python -B -I tests/test_report.py."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPORT = os.path.join(HERE, "..", "tools", "report.py")
ENGINE = "[INFO] - Binding of Isaac: Repentance+ v1.9.7.19.J511"


def probe(*texts):
    return ["[INFO] - Lua Debug: PROBE " + t for t in texts]


def test_lines(spec, name, verdict, snaps=(), body=(), tags=("hello", "vanilla")):
    key = f"{spec} > {name}"
    return probe(f"TEST START {key} | tags {','.join(tags)}") + list(body) + probe(*(f"SNAP {key} | {k} = {v}" for k, v in snaps)) + probe(f"RESULT {key} {verdict}")


def session(*tests, update="no", engine=True, total=None, done=True):
    head = [ENGINE] if engine else []
    start = probe(f"HARNESS START {total or len(tests)} tests, tags 'tags hello', update snapshots {update}, mod data 'tags hello\\r\\nSTUCK 1 x'")
    return head + start + [line for t in tests for line in t] + (probe("HARNESS DONE") if done else [])


def run(log, specs, *args, env=None, isolated=True):
    """report.py on `log` in a temp folder: (exit code, stdout lines, report.json, out folder)."""
    out = tempfile.mkdtemp()
    path = os.path.join(out, "log.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")
    flags = ["-B", "-I"] if isolated else ["-B"]
    p = subprocess.run([sys.executable, *flags, REPORT, path, "--out", out, "--specs", specs, *args], capture_output=True, env=env)
    assert not p.stderr, p.stderr.decode(errors="replace")
    with open(os.path.join(out, "report.json"), encoding="utf-8") as f:
        data = json.load(f)
    return p.returncode, p.stdout.decode("utf-8", errors="replace").splitlines(), data, out


def snap_file(specs, spec="hello"):
    path = os.path.join(specs, spec + ".snap.txt")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


PASSING = test_lines("hello", "fresh Isaac", "PASS 3 assertions")
SNAPPED = test_lines("hello", "fresh run", "RECORDED", snaps=[("0 start / lineup", "A"), ("0 start / A type", "0")])


def test_verdicts():
    specs = tempfile.mkdtemp()
    skip = probe("RESULT hello > Clicker on Isaac SKIP not tagged (tags 'tags hello')")
    code, out, _, _ = run(session(PASSING, skip), specs)
    assert (code, out[-1]) == (0, "ALL PASS"), out
    assert "hello > fresh Isaac: PASS 3 assertions" in out, out
    failing = test_lines("hello", "fresh Isaac", "FAIL c703 owned 0, want 1",
                         body=probe("INFO hello > fresh Isaac step 1: x", "ASSERT FAIL hello > fresh Isaac c703 owned 0"))
    code, out, _, _ = run(session(failing), specs)
    assert (code, out[-1]) == (1, "NEEDS ANALYSIS: hello > fresh Isaac FAIL"), out
    assert "  ASSERT FAIL hello > fresh Isaac c703 owned 0" in out and "  info step 1: x" in out, out
    explained = test_lines("base_change", "P2", "PASS 61 assertions; unreached: no split in 20 Clicker uses")
    odd = test_lines("base_change", "P3", "PASS 2 assertions; unreached: the Flip; late Continue mid-test")
    code, out, _, _ = run(session(explained, odd), specs)
    assert out[-1] == "NEEDS ANALYSIS: base_change > P3 unreached: the Flip; base_change > P3 late Continue mid-test", out
    code, out, _, _ = run(session(PASSING, total=2, done=False), specs)
    assert out[-1] == "NEEDS ANALYSIS: results for 1 of 2 tests; no HARNESS DONE", out
    asked = test_lines("continue", "continue", "PASS 1 assertions", body=probe("ACTION exit to the menu and Continue now by type 0"))
    code, out, _, _ = run(session(asked), specs)
    assert out[-1] == "NEEDS ANALYSIS: continue asked 1 times, resumed 0", out
    noise = ["[WARN] - Different number of collectibles in collection 0/733", "[ERROR] - Failed to read player data from gamestate",
             "[INFO] - Lua Debug: Error in \"PostUpdate\" call: x 12"]
    code, out, _, _ = run(session(PASSING) + noise, specs)
    assert out[-1] == "NEEDS ANALYSIS: 1 distinct errors", out
    print("PASS verdicts: pass, skip, fail with context, unreached, cut off, continues, errors")


def test_snapshots():
    specs = tempfile.mkdtemp()
    code, out, data, out_dir = run(session(SNAPPED), specs)
    assert (code, out[-1]) == (0, "ALL PASS"), out
    text = snap_file(specs)
    lines = text.splitlines()
    assert lines[0] == "# hello snapshots, written by tools/report.py from a played session", lines
    assert lines[2] == "## fresh run" and lines[3].startswith("# game Binding of Isaac: Repentance+ v1.9.7.19.J511, session "), lines
    assert lines[4:6] == ["0 start / lineup = A", "0 start / A type = 0"], lines
    assert data["tests"][0]["snapshot"] == {"state": "new", "diff": [], "written": True}, data
    assert os.path.exists(os.path.join(out_dir, "traces", "hello - fresh run.txt"))

    code, out, data, out_dir = run(session(SNAPPED), specs)
    assert (code, data["tests"][0]["snapshot"]["state"]) == (0, "match"), out
    assert not os.path.exists(os.path.join(out_dir, "traces")), "a matching test left a trace"

    changed = test_lines("hello", "fresh run", "RECORDED", snaps=[("0 start / lineup", "A"), ("0 start / A type", "21")])
    code, out, data, _ = run(session(changed), specs)
    assert code == 1 and out[-1] == "NEEDS ANALYSIS: hello > fresh run FAIL", out
    assert "    0 start / A type: snapshot '0', session '21'" in out, out
    assert data["tests"][0]["snapshot"]["diff"] == [{"key": "0 start / A type", "snapshot": "0", "session": "21"}], data
    assert snap_file(specs) == text, "a diff without the flag rewrote the snapshot"

    failing = test_lines("hello", "fresh run", "FAIL broke", snaps=[("0 start / A type", "21")])
    run(session(failing, update="yes"), specs)
    assert snap_file(specs) == text, "a FAIL test rewrote the snapshot"

    cut = test_lines("hello", "fresh run", "RECORDED; unreached: 2 Flip never happened", snaps=[("0 start / A type", "29")])
    run(session(cut, update="yes"), specs)
    assert snap_file(specs) == text, "a test with an unreached step rewrote the snapshot"
    run(session(test_lines("hello", "cut new", "RECORDED; unreached: 1 Flip never happened", snaps=[("0 start / lineup", "A")])), specs)
    assert "## cut new" not in snap_file(specs), "a test with an unreached step wrote a new snapshot"

    code, out, data, _ = run(session(changed, update="yes"), specs)
    assert (code, data["tests"][0]["snapshot"]["state"]) == (0, "updated"), out
    assert "0 start / A type = 21" in snap_file(specs), snap_file(specs)

    skipped = test_lines("hello", "fresh run", "SKIP no case", snaps=[("0 start / A type", "8")])
    code, out, data, _ = run(session(skipped, test_lines("hello", "skip new", "SKIP no case", snaps=[("0 start / lineup", "A")]), update="yes"), specs)
    assert (code, [t["snapshot"] for t in data["tests"]]) == (0, [None, None]), out
    assert "0 start / A type = 21" in snap_file(specs) and "## skip new" not in snap_file(specs), snap_file(specs)
    print("PASS snapshots: new is written, match, diff shows both values, update only with the flag, never from a FAIL test, one with an unreached step or a SKIP")


def test_stub_log():
    specs = tempfile.mkdtemp()
    code, out, data, _ = run(session(SNAPPED, engine=False), specs)
    assert (code, out[-1]) == (0, "ALL PASS"), out
    assert snap_file(specs) is None, "a dry log wrote a snapshot"
    assert data["tests"][0]["snapshot"] == {"state": "new", "diff": [], "written": False}, data
    print("PASS a log without the engine line writes no snapshot")


def test_guard():
    specs = tempfile.mkdtemp()
    later = test_lines("hello", "Clicker on Isaac", "PASS 1 assertions")
    for line in ("[INFO] - Updating mod 'rehud_repplus'", "[INFO] - Lua is resetting!"):
        code, out, data, _ = run(session(PASSING, [line], later, total=2), specs)
        assert code == 1 and out[-1] == f"NEEDS ANALYSIS: hello > Clicker on Isaac FAIL; environment changed: {line}", out
        assert f"  FAIL: environment changed: {line}" in out, out
        assert data["tests"][0]["status"] == "PASS" and data["session"]["guard"] == [line], data
    in_debug = ["[INFO] - Lua Debug: [INFO] - Updating mod 'x'", "[INFO] - Lua Debug: [INFO] - Lua is resetting!"]
    code, out, _, _ = run(session(PASSING, in_debug, later, total=2), specs)
    assert (code, out[-1]) == (0, "ALL PASS"), out
    print("PASS log guard: mod update and Lua reset fail later tests, not inside Lua Debug lines")


def test_json():
    specs = tempfile.mkdtemp()
    torn = test_lines("hello", "fresh Isaac", "PASS 3 assertions") + probe("TEARDOWN FAIL hello > fresh Isaac endPress: boom")
    untagged = test_lines("hello", "no tags", "PASS 0 assertions", tags=())
    skipped = probe("RESULT hello > Clicker on Isaac SKIP not tagged (tags 'tags hello')")
    code, out, data, _ = run(session(torn, SNAPPED, untagged, skipped), specs)
    assert code == 1 and out[-1] == "NEEDS ANALYSIS: hello > fresh Isaac teardown failed", out
    assert [t["tags"] for t in data["tests"]] == [["hello", "vanilla"], ["hello", "vanilla"], [], None], data["tests"]  # SKIP: no TEST START
    assert set(data) == {"session", "tests", "verdict", "reasons"}, data
    assert set(data["session"]) == {"version", "tags", "update", "guard", "start", "done"}, data["session"]
    assert data["session"]["version"] == ENGINE[len("[INFO] - "):] and data["session"]["tags"] == "tags hello", data["session"]
    t = data["tests"][0]
    assert set(t) == {"spec", "name", "tags", "status", "assertions", "failures", "unreached", "snapshot", "teardown", "trace", "updates"}, t
    assert (t["status"], t["assertions"], t["failures"], t["teardown"]) == ("PASS", 3, [], ["TEARDOWN FAIL hello > fresh Isaac endPress: boom"]), t
    assert data["verdict"] == "NEEDS ANALYSIS" and data["reasons"] == ["hello > fresh Isaac teardown failed"], data
    print("PASS report.json fields, tags from TEST START, teardown failures kept apart from the verdict")


def test_timeline():
    specs = tempfile.mkdtemp()
    traced = test_lines("esau_jr", "cross", "RECORDED", body=probe(
        "TRACE u1 step press begins",
        "TRACE u1 after press: PLAYER 0 type 29 seed 77 hash 1001 ctrl 0 parent false c4 1 c703 1 primary 703 secondary 0 pocket 711",
        "TRACE u2 after press: PLAYER 0 type 29 seed 77 hash 2002 ctrl 0 parent false c4 0 c703 1 primary 703 secondary 0 pocket 711",
        "TRACE u2 after press: ROSTER key 77 number 1 swapped false partner nil left false"))
    code, out, data, _ = run(session(traced), specs, "--timeline", "cross")
    assert out[0] == "== esau_jr > cross" and any(r.startswith("u2 ") and "| P0 t29 B [c703] act 703/0/711 || roster k1#1" in r for r in out), out
    assert any(r.startswith("    A = hash 1001 seed 77: appeared u1, gone u2") for r in out), out
    assert data["tests"][0]["updates"] == 2, data
    print("PASS timeline labels characters by GetPtrHash")


def test_cp1251():
    # -I would drop PYTHONIOENCODING; a console on cp1251 cannot encode this line (B5)
    specs = tempfile.mkdtemp()
    log = session(test_lines("hello", "fresh Isaac", "PASS 1 assertions", body=probe("INFO hello > fresh Isaac floor 地下室 ✓")))
    code, out, _, _ = run(log, specs, env={**os.environ, "PYTHONIOENCODING": "cp1251"}, isolated=False)
    assert (code, out[-1]) == (0, "ALL PASS"), out
    assert "  info floor ??? ?" in out, out
    print("PASS a cp1251 console prints unencodable text as ?")


def test_session1():
    # harness session 1's play-set log (2026-11-23, tags seed), trimmed to the engine line and the harness's own lines
    with open(os.path.join(HERE, "fixtures", "session1-seed.txt"), encoding="utf-8") as f:
        log = f.read().splitlines()
    specs = tempfile.mkdtemp()
    code, out, data, _ = run(log, specs)
    assert data["session"]["version"] == ENGINE[len("[INFO] - "):], data["session"]
    t = next(t for t in data["tests"] if t["name"] == "fresh run on a fixed seed")
    assert (t["status"], t["snapshot"]["state"], t["snapshot"]["written"]) == ("RECORDED", "new", True), t
    assert "## fresh run on a fixed seed" in snap_file(specs), "session 1's snapshot not written"
    assert (code, out[-1]) == (0, "ALL PASS"), (code, out[-1])
    print("PASS session 1's log: engine version, the seed recon test recorded and its snapshot written, ALL PASS")


TESTS = [test_verdicts, test_snapshots, test_stub_log, test_guard, test_json, test_timeline, test_cp1251, test_session1]


if __name__ == "__main__":
    for test in TESTS:
        test()
    print("PASS report")
