"""Dry run of main.lua against tests/stub.lua. Run: python -I tests/test_harness.py main.lua (venv with lupa)."""
import os
import sys
from lupa.lua53 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "P4b", "P1", "P2", "r1", "continue", "continue settled"]
# Exact verdicts: a lost check or note shows. P2 has 2 checks here, 4+ in game: the stub's Clicker splits on its second use.
WANT = {
    "probes": "PASS 10 checks; unobserved: Esau Jr. spend, Flip spend",
    "test3": "PASS 5 checks; unobserved: Flip spend",
    "birthright": "PASS 16 checks; unobserved: Flip spend",
    "P3": "PASS 4 checks; unobserved: Flip spend",
    "P4a": "PASS 3 checks; unobserved: Esau Jr. 1 spend, Esau Jr. 2 spend",
    "P4b": "INFO data only; unobserved: Esau Jr. 1 spend, Esau Jr. 2 spend",
    "P1": "PASS 5 checks",
    "P2": "PASS 2 checks",
    "r1": "INFO data only; unobserved: Flip spend, Esau Jr. 1 (overcharged) spend, Esau Jr. 2 spend",
    "continue": "PASS 3 checks; unobserved: Flip spend",
    "continue settled": "PASS 4 checks; unobserved: Flip spend",
}
FLOOR_CHECKED = ["test3", "birthright", "P3", "P4a", "P1", "P2", "continue", "continue settled"]
# A swap whose presser stays present must FAIL without a spend. Birthright's stub forms both stay charged, so the press flips twice in
# one update and fails as "no new character" instead.
SPEND_SEEN = {"probes": "spent nothing", "birthright": "Flip 1 of 2: no new character", "P1": "spent nothing", "P2": "spent nothing"}
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


def all_fail(got, label, why):
    for name in SCENARIOS:
        assert got[name].startswith("FAIL") and why in got[name], f"{label}: {name}: {got[name]}"
    print(f"PASS {label} fails:", got["test3"])


def main(path):
    log = run(path)
    got = check_finished(log, "regression mode")
    for name in SCENARIOS:
        print("RESULT", name, got[name])
        assert got[name] == WANT[name], f"{name}: {got[name]}"
    assert any(s.startswith("PROBE HARNESS START") and "regression mode" in s for s in log), "mode not logged"
    assert sum(s.startswith("PROBE GAME START") and s.endswith("continued true") for s in log) == 2, "both continues did not resume"
    presses = [s for s in log if s.startswith("PROBE PRESS ")]
    swaps = [s for s in log if s.startswith("PROBE SWAP ")]
    unseen = [s for s in swaps if " spend unobserved " in s]
    assert presses and len(presses) == len(swaps) and all(" spent " in s or s in unseen for s in swaps), (len(presses), len(swaps))
    print("PASS every swap spends or notes it:", len(swaps), "swaps,", len(unseen), "unobserved")
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in log), "P2 never split"
    print("PASS P2 reaches the split")
    assert sum(s.startswith("PROBE R1 ") for s in log) == 4, "r1 did not answer all four questions"
    for s in log:
        if s.startswith("PROBE R1 "):
            print(s)

    got = check_finished(run(path, mode=""), "default mode")
    for name in SCENARIOS:
        want = "SKIP large and not new (default mode)" if name == "continue" else WANT[name]
        assert got[name] == want, f"default mode: {name}: {got[name]}"
    print("PASS default mode skips continue and runs the new continue settled")

    got = check_finished(run(path, on_exit="new"), "new run instead of Continue")
    for name in ["continue", "continue settled"]:
        assert got[name].startswith("FAIL") and "a new run started, not a Continue" in got[name], got[name]
    print("PASS new run instead of Continue fails:", got["continue"])

    all_fail(check_finished(run(path, ignoreRestart=True), "restart ignored"), "restart timeout", "no new game after 600 updates")
    # probes' first press is Esau Jr., a swap: every scenario fails on its first press
    all_fail(check_finished(run(path, ignorePress=True), "press ignored"), "press ignored", "no new character, arms ")

    got = check_finished(run(path, noSpend=True), "no spend")
    for name in SCENARIOS:
        if name in SPEND_SEEN:
            assert got[name].startswith("FAIL") and SPEND_SEEN[name] in got[name], f"no spend: {name}: {got[name]}"
        else:
            assert got[name] == WANT[name], f"no spend: {name}: {got[name]}"
    print("PASS no spend fails where the presser stays:", ", ".join(SPEND_SEEN))

    got = check_finished(run(path, wrongFloor=True), "wrong floor")
    for name in SCENARIOS:
        if name in FLOOR_CHECKED:
            assert got[name].startswith("FAIL") and "on 'Wrong'" in got[name], f"wrong floor: {name}: {got[name]}"
        else:
            assert got[name] == WANT[name], f"wrong floor: {name}: {got[name]}"
    print("PASS a wrong ReHUD floor fails:", got["test3"][:90])
    print("PASS dry run")


if __name__ == "__main__":
    main(sys.argv[1])
