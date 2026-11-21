"""Dry run of main.lua against tests/stub.lua. Run: python -I tests/test_harness.py main.lua (venv with lupa)."""
import os
import sys
from lupa.lua53 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "P4b", "P1", "P2", "continue"]
WANT = {"P4b": "INFO"}  # the rest: PASS


def run(path, on_exit="continue", ignore_restart=False, ignore_press=False, no_spend=False):
    """Plays the whole suite; on_exit is what the fake user does when asked to exit and Continue: "continue" or "new"."""
    lua = LuaRuntime()
    assert lua.eval("_VERSION") == "Lua 5.3", lua.eval("_VERSION")
    with open(os.path.join(HERE, "stub.lua"), encoding="utf-8") as f:
        lua.execute(f.read())
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())
    g = lua.globals()
    g.ignoreRestart, g.ignorePress, g.noSpend = ignore_restart, ignore_press, no_spend
    g.startRun(3, False)
    asked = False
    for _ in range(100000):
        if g.pendingStart is not None:
            t = g.pendingStart
            g.pendingStart = None
            g.startRun(t, False)
        g.engineInput()
        g.fakeTrack()
        g.fire(1)
        g.fire(2)
        log = list(g.LOG.values())
        if not asked and any("ACTION exit to the menu and Continue" in s for s in log):
            asked = True
            g.startRun(0, on_exit == "continue")
        if log[-1] == "PROBE HARNESS DONE":
            break
    return list(g.LOG.values())


def results(log):
    out = {}
    for s in log:
        if s.startswith("PROBE RESULT "):
            name, verdict = s[len("PROBE RESULT "):].split(" ", 1)
            assert name not in out, f"two RESULTs for {name}"
            out[name] = verdict
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
    got = check_finished(log, "full run")
    for name in SCENARIOS:
        print("RESULT", name, got[name])
        assert got[name].startswith(WANT.get(name, "PASS")), f"{name}: {got[name]}"
    assert any(s.startswith("PROBE GAME START") and s.endswith("continued true") for s in log), "continue did not resume"
    assert any(s.endswith("pocket press mode that swaps b") for s in log), "probes did not settle on mode b"
    print("PASS probes find pocket press mode b after a fails")
    presses = [s for s in log if s.startswith("PROBE PRESS ") and not s.startswith("PROBE PRESS Flip mode a")]  # a is meant to fail
    swaps = [s for s in log if s.startswith("PROBE SWAP ")]
    assert presses and len(presses) == len(swaps) and all(" spent " in s for s in swaps), (len(presses), len(swaps))
    print("PASS every swap spends:", len(swaps), "swaps")
    assert not any("split not reached" in s for s in log), "P2 never split"
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in log), "P2 never split"
    print("PASS P2 reaches the split")

    got = check_finished(run(path, on_exit="new"), "new run instead of Continue")
    assert got["continue"].startswith("FAIL") and "a new run started, not a Continue" in got["continue"], got["continue"]
    print("PASS new run instead of Continue fails:", got["continue"])

    all_fail(check_finished(run(path, ignore_restart=True), "restart ignored"), "restart timeout", "no new game after 600 updates")
    # probes' first press is Esau Jr., a swap: every scenario fails on its first press
    all_fail(check_finished(run(path, ignore_press=True), "press ignored"), "press ignored", "no new character, mode ")
    all_fail(check_finished(run(path, no_spend=True), "no spend"), "swap without a spend", "spent nothing")
    print("PASS dry run")


if __name__ == "__main__":
    main(sys.argv[1])
