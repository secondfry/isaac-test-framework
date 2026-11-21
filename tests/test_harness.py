"""Dry run of main.lua against tests/stub.lua. Run: python -I tests/test_harness.py main.lua (venv with lupa)."""
import os
import subprocess
import sys
import tempfile
from lupa.lua53 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
OBS = ["obs esaujr cross", "obs esaujr out", "obs esaujr flip", "obs esaujr flipped cross", "obs esaujr birthright", "obs esaujr clicker", "obs mirror",
       "obs esaujr birthright keep", "obs esaujr cross35", "obs esaujr dead seed", "obs esaujr birthright flip"]
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "P4c", *OBS, "S4", "P1", "P2", "S1", "S1b", "S2", "S3", "r1", "r1 mirror",
             "continue", "continue settled", "L1"]
NO_SWAP = {"S1", "S1b", "S2", "L1", *OBS}  # an obs press that never swaps is INFO, not a fail
LARGE = NEW = {"continue", "continue settled", "L1"}  # NEW mirrors main.lua's new = true flags
# Exact verdicts: a lost check or note shows. Each look adds 5 invariant checks. P2 counts 8 or 9 checks per Clicker use: 22 here (the stub's
# Clicker splits on its second use), any number in game.
WANT = {
    "probes": "PASS 10 checks",
    "test3": "PASS 15 checks",
    "birthright": "PASS 36 checks",
    "P3": "PASS 30 checks",
    "P4a": "PASS 18 checks",
    "P4c": "PASS 87 checks",
    "S4": "PASS 29 checks",
    "P1": "PASS 25 checks",
    "P2": "PASS 22 checks",
    "continue": "PASS 14 checks",
    "continue settled": "PASS 20 checks",
    "S1": "PASS 53 checks",
    "S1b": "PASS 37 checks",
    "S2": "PASS 29 checks",
    "S3": "PASS 22 checks",
    "r1": "PASS 27 checks",
    "r1 mirror": "PASS 18 checks",
    "L1": "PASS 30 checks",
    **{n: "INFO data only" for n in OBS},
}
FLOOR_CHECKED = [n for n in SCENARIOS if n != "probes" and n not in OBS]  # the floor invariant covers every scenario with a look
# Every scenario but NO_SWAP swaps, and each swap must FAIL without a spend: a stored presser (Esau Jr., Flip without Birthright) on its watched
# drop, a staying one (Clicker) on its charge, a card on its count.
STORED = "spent nothing: stored presser seen with no drop after its use"
SPEND_SEEN = {"probes": STORED, "test3": STORED, "birthright": STORED, "P3": STORED, "P4a": STORED, "P4c": STORED, "S4": STORED,
              "P1": "spent nothing: card count", "P2": "spent nothing: charge", "S3": STORED, "r1": STORED, "r1 mirror": STORED,
              "continue": STORED, "continue settled": STORED}
ASK = "ACTION exit to the menu and Continue now by type"
# Each invariant's negative stub mode, and the scenarios it must fail on with that invariant's message (the rest may fail on their own checks).
HOLDS_C4 = ["test3", "birthright", "P3", "P4a", "P4c", "S4", "P1", "P2", "S1", "S3", "r1", "r1 mirror", "continue", "continue settled", "L1"]
INVARIANT_MODES = {
    "missCopy": ("invariant engine counts: c4 of ", HOLDS_C4),
    "dupCopy": ("invariant duplicates: c4 of ", HOLDS_C4),
    "keepStored": ("invariant phantom stored forms: ", ["test3", "S3", "continue", "continue settled"]),
    "leaveNotMerge": ("invariant left entries: ", ["test3", "P4c", "P2", "S3", "r1", "r1 mirror", "continue", "continue settled"]),
    # S4, P1, P2 and S3 list nothing after their last stage, so a next-floor name is still one they reached
    "laterFloor": ("invariant floors: ", ["test3", "birthright", "P3", "P4a", "P4c", "S1", "S1b", "S2", "r1", "r1 mirror", "continue", "continue settled", "L1"]),
}
REPORT = os.path.join(HERE, "..", "tools", "run_report.py")
OBS_REPORT = os.path.join(HERE, "..", "tools", "obs_report.py")


def run(path, mode="regression", on_exit="continue", **flags):
    """Plays the whole suite; on_exit is what the fake user does when asked to exit and Continue: "continue" or "new"."""
    lua = LuaRuntime()
    assert lua.eval("_VERSION") == "Lua 5.3", lua.eval("_VERSION")
    with open(os.path.join(HERE, "stub.lua"), encoding="utf-8") as f:
        lua.execute(f.read())
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())
    g = lua.globals()
    g.modData = mode
    for k, v in flags.items():
        g[k] = v
    g.startRun(3, False)
    asked = 0
    for _ in range(200000):
        if g.pendingStart is not None:
            t = g.pendingStart
            g.pendingStart = None
            g.startRun(t, False)
        g.engineInput()
        g.fakeTrack()
        g.fire(1)
        g.fire(2)
        log = list(g.LOG.values())
        asks = sum(ASK in s for s in log)
        if asks > asked:
            asked = asks
            g.startRun(0, on_exit == "continue")
        if log[-1] == "PROBE HARNESS DONE":
            break
    return list(g.LOG.values())


def results(log):
    out = {}
    for s in log:
        if s.startswith("PROBE RESULT "):
            rest = s[len("PROBE RESULT "):]
            name = next(n for n in sorted(SCENARIOS, key=len, reverse=True) if rest.startswith(n + " "))
            assert name not in out, f"two RESULTs for {name}"
            out[name] = rest[len(name) + 1:]
    return out


def check_finished(log, label):
    assert log[-1] == "PROBE HARNESS DONE", f"{label}: run did not finish"
    assert not any("HARNESS ERROR" in s for s in log), f"{label}: harness error"
    got = results(log)
    assert list(got) == SCENARIOS, f"{label}: RESULTs {list(got)}"
    return got


def all_fail(got, label, why, names=SCENARIOS):
    for name in SCENARIOS:
        if name in names:
            assert got[name].startswith("FAIL") and why in got[name], f"{label}: {name}: {got[name]}"
        else:
            assert got[name] == WANT[name], f"{label}: {name}: {got[name]}"
    print(f"PASS {label} fails:", got["test3"])


def run_report(log):
    """tools/run_report.py on these lines (a list) or on a file path: (exit code, last line)."""
    tmp = isinstance(log, list)
    if tmp:
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
            f.write("\n".join(log))
        log = f.name
    try:
        p = subprocess.run([sys.executable, "-B", "-I", REPORT, log], capture_output=True, text=True)
    finally:
        if tmp:
            os.remove(log)
    assert not p.stderr, p.stderr
    return p.returncode, p.stdout.strip().splitlines()[-1]


def obs_report(log):
    """tools/obs_report.py on the dry run: a timeline and a summary for every obs scenario, seeds labelled."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write("\n".join(log))
    try:
        p = subprocess.run([sys.executable, "-B", "-I", OBS_REPORT, f.name], capture_output=True, text=True)
    finally:
        os.remove(f.name)
    assert p.returncode == 0 and not p.stderr, p.stderr
    out = p.stdout.splitlines()
    assert out[-1] == f"obs scenarios: {len(OBS)} ({', '.join(OBS)})", out[-1]
    for name in OBS:
        assert f"== {name}" in out and f"  summary {name}: INFO data only" in out, name
    # obs esaujr cross: the original (A) is stored by Esau Jr. and back after the second press; the form (B) holds the c5 marker
    rows = out[out.index("== obs esaujr cross"):out.index("  summary obs esaujr cross: INFO data only") + 3]
    assert any(r.startswith("u") and "| P0 t29 B [c5 c711]" in r for r in rows), rows
    assert rows[-2].startswith("    A = ") and "appeared u1, gone u2, back u" in rows[-2], rows[-2]
    assert rows[-1].startswith("    B = ") and "engine c5x1" in rows[-1], rows[-1]
    assert any(r.startswith("       PLAYERX 0 variant ") for r in out), "no PLAYERX line under a row"
    assert any(r.startswith("       COUNT players ") for r in out), "no COUNT line under a row"
    print("PASS obs_report: timelines and summaries for", len(OBS), "obs scenarios")


def main(path):
    log = run(path)
    got = check_finished(log, "regression mode")
    for name in SCENARIOS:
        print("RESULT", name, got[name])
        assert got[name] == WANT[name], f"{name}: {got[name]}"
    assert any(s.startswith("PROBE HARNESS START") and "regression mode" in s for s in log), "mode not logged"
    assert sum(s.startswith("PROBE GAME START") and s.endswith("continued true") for s in log) == 3, "the three continues did not resume"
    presses = [s for s in log if s.startswith("PROBE PRESS ")]
    swaps = [s for s in log if s.startswith("PROBE SWAP ")]
    stored = [s for s in swaps if " spent stored presser charge, " in s]
    assert presses and len(presses) == len(swaps) and stored, (len(presses), len(swaps), len(stored))
    print("PASS every swap logged a spend:", len(swaps), "swaps,", len(stored), "by a stored presser")
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in log), "P2 never split"
    print("PASS P2 reaches the split")
    assert run_report(log) == (0, "ALL PASS"), run_report(log)
    print("PASS run_report on the dry run: ALL PASS")
    obs_report(log)
    code, verdict = run_report(os.path.join(HERE, "fixtures", "run8-trimmed.txt"))
    assert (code, verdict) == (1, "NEEDS ANALYSIS: S3 unobserved: rolled Tainted Lazarus, see r1; results for 4 of 16 scenarios"), (code, verdict)
    print("PASS run_report parses the run 8 fixture:", verdict)

    # Clicker from the Dead form rolling 29 (run 8): S3's merge checks with Flip kept, the rest unchanged
    got = check_finished(run(path, tlazRoll=29), "Clicker rolls 29")
    for name in SCENARIOS:
        assert got[name] == ("PASS 21 checks" if name == "S3" else WANT[name]), f"Clicker rolls 29: {name}: {got[name]}"
    print("PASS Clicker rolling 29:", got["S3"])

    got = check_finished(run(path, mode=""), "default mode")
    for name in SCENARIOS:
        want = "SKIP large and not new (default mode)" if name in LARGE and name not in NEW else WANT[name]
        assert got[name] == want, f"default mode: {name}: {got[name]}"
    print("PASS default mode runs small and new large scenarios, skips the rest")

    log = run(path, mode="only obs")
    got = check_finished(log, "only obs mode")
    assert any(s.startswith("PROBE HARNESS START") and "only obs mode" in s for s in log), "only mode not logged"
    for name in SCENARIOS:
        assert got[name] == (WANT[name] if name in OBS else "SKIP not obs (only obs mode)"), f"only obs mode: {name}: {got[name]}"
    print("PASS only obs runs just the obs scenarios")

    got = check_finished(run(path, on_exit="new"), "new run instead of Continue")
    for name in LARGE:
        assert got[name].startswith("FAIL") and "a new run started, not a Continue" in got[name], got[name]
    print("PASS new run instead of Continue fails:", got["continue"])

    all_fail(check_finished(run(path, ignoreRestart=True), "restart ignored"), "restart timeout", "no new game after 600 updates")
    # probes' first press is Esau Jr., a swap: every scenario fails on its first press
    all_fail(check_finished(run(path, ignorePress=True), "press ignored"), "press ignored", "no new character, arms ",
             [n for n in SCENARIOS if n not in NO_SWAP])

    got = check_finished(run(path, noSpend=True), "no spend")
    for name in SCENARIOS:
        if name in NO_SWAP:
            assert got[name] == WANT[name], f"no spend: {name}: {got[name]}"
        else:
            assert got[name].startswith("FAIL") and SPEND_SEEN[name] in got[name], f"no spend: {name}: {got[name]}"
    print("PASS no spend fails every swap:", got["test3"][:110])

    got = check_finished(run(path, wrongFloor=True), "wrong floor")
    for name in SCENARIOS:
        if name in FLOOR_CHECKED:
            # expectN names the wrong floor; a floor-filtered count names the floor it found too few on
            assert got[name].startswith("FAIL") and ("on 'Wrong'" in got[name] or " on Floor" in got[name]), f"wrong floor: {name}: {got[name]}"
        else:
            assert got[name] == WANT[name], f"wrong floor: {name}: {got[name]}"
    print("PASS a wrong ReHUD floor fails:", got["test3"][:90])

    for mode, (why, names) in INVARIANT_MODES.items():
        log = run(path, **{mode: True})
        got = check_finished(log, mode)
        hit = [n for n in SCENARIOS if got[n].startswith("FAIL") and why in got[n]]
        assert hit == names, f"{mode}: invariant fired in {hit}"
        print(f"PASS {mode} fails the invariant in {len(hit)} scenarios")
    code, verdict = run_report(log)
    assert code == 1 and verdict.startswith("NEEDS ANALYSIS: test3 FAIL;"), (code, verdict)
    print("PASS run_report on a failing run:", verdict[:60])
    print("PASS dry run")


if __name__ == "__main__":
    main(sys.argv[1])
