"""Dry run of main.lua against tests/stub.lua. Run: python -I tests/test_harness.py main.lua (venv with lupa)."""
import os
import sys
from lupa.lua53 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "S4", "P1", "P2", "S1", "S1b", "S2", "S3", "r1", "r1 mirror",
             "continue", "continue settled", "L1"]
NO_SWAP = {"S1", "S1b", "S2", "L1"}
LARGE = NEW = {"continue", "continue settled", "L1"}  # NEW mirrors main.lua's new = true flags
# Exact verdicts: a lost check or note shows. P2 counts 3 or 4 checks per Clicker use: 7 here (the stub's Clicker splits on its second use), any number in game.
WANT = {
    "probes": "PASS 10 checks",
    "test3": "PASS 5 checks",
    "birthright": "PASS 16 checks",
    "P3": "PASS 10 checks",
    "P4a": "PASS 3 checks",
    "S4": "PASS 14 checks",
    "P1": "PASS 5 checks",
    "P2": "PASS 7 checks",
    "continue": "PASS 4 checks",
    "continue settled": "PASS 5 checks",
    "S1": "PASS 18 checks",
    "S1b": "PASS 7 checks",
    "S2": "PASS 9 checks",
    "S3": "PASS 12 checks",
    "r1": "PASS 12 checks",
    "r1 mirror": "PASS 8 checks",
    "L1": "PASS 15 checks",
}
FLOOR_CHECKED = ["test3", "birthright", "P3", "P4a", "S4", "P1", "P2", "S1", "S1b", "S3", "r1", "r1 mirror", "continue", "continue settled", "L1"]
# Every scenario but NO_SWAP swaps, and each swap must FAIL without a spend: a stored presser (Esau Jr., Flip without Birthright) on its watched
# drop, a staying one (Clicker) on its charge, a card on its count.
STORED = "spent nothing: stored presser seen with no drop after its use"
SPEND_SEEN = {"probes": STORED, "test3": STORED, "birthright": STORED, "P3": STORED, "P4a": STORED, "S4": STORED,
              "P1": "spent nothing: card count", "P2": "spent nothing: charge", "S3": STORED, "r1": STORED, "r1 mirror": STORED,
              "continue": STORED, "continue settled": STORED}
ASK = "ACTION exit to the menu and Continue now by type"


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

    # Clicker from the Dead form rolling 29 (run 8): S3's merge checks with Flip kept, the rest unchanged
    got = check_finished(run(path, tlazRoll=29), "Clicker rolls 29")
    for name in SCENARIOS:
        assert got[name] == ("PASS 11 checks" if name == "S3" else WANT[name]), f"Clicker rolls 29: {name}: {got[name]}"
    print("PASS Clicker rolling 29:", got["S3"])

    got = check_finished(run(path, mode=""), "default mode")
    for name in SCENARIOS:
        want = "SKIP large and not new (default mode)" if name in LARGE and name not in NEW else WANT[name]
        assert got[name] == want, f"default mode: {name}: {got[name]}"
    print("PASS default mode runs small and new large scenarios, skips the rest")

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
    print("PASS dry run")


if __name__ == "__main__":
    main(sys.argv[1])
