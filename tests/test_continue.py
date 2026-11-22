"""Dry checks of specs/continue.lua: its tests' verdicts and the checks of their own lines."""
import dry

STORED, LOST = "continue > Esau Jr. character stored across Exit & Continue", "continue > Esau Jr. lost, then Exit & Continue"
WANT = {  # each test's verdict under `tags all` when nothing fails, by "continue > <test>"
    STORED: "RECORDED",
    LOST: "RECORDED",
    "continue > temporary Esau and Strawman's Keeper across Exit & Continue": "RECORDED",
    "continue > Flip mid-settle, Exit & Continue, then ChangePlayerType": "PASS 14 assertions",
    "continue > Flip once settled, Exit & Continue, then ChangePlayerType": "PASS 20 assertions",
    "continue > item copies survive Exit & Continue": "PASS 30 assertions",
    **dry.recon("continue", "start, then Exit & Continue"),
}
MODE = "tags continue"


def test_continue_lines(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    keeper = dry.segment(log, "continue > temporary Esau and Strawman's Keeper across Exit & Continue")
    assert any("HELPERS after Continue" in s and " type 14 parent index 0 " in s for s in keeper), "no Keeper after the Continue"
    for name, lines in dry.check_verdicts(log, [STORED, LOST]).items():
        assert sum(s.startswith("after Continue: player seeds ") for s in lines) == 1, name
    for c in dry.RECON:
        lines = dry.segment(log, f"continue > {c}: start, then Exit & Continue")
        assert not any("never happened" in s for s in lines) and sum(" IDS after Continue " in s for s in lines) >= 1, c
    print(f"PASS {MODE}: {sum('continue' in t.tags for t in dry.plan(path))} tests, Keeper after the Continue, Esau Jr. verdicts and timing")


def test_locked_character(path):
    # a restart that brings another character (a locked one may) fails each recon test of that character as a precondition
    mode = "tags recon"
    got = dry.finished(dry.run(path, mode=mode, lockedType=21), "locked Tainted Isaac", path)
    locked = [n for n in got if n.split(" > ")[1].startswith("Tainted Isaac: ")]
    want = "FAIL precondition: Tainted Isaac (type 21) cannot be started, locked on this save? player 0 is type 0, want 21"
    assert len(locked) == 4 and all(got[n] == want for n in locked), {n: got[n] for n in locked}
    dry.expect_results(got, mode, {n: v for n, v in dry.expected(path, mode).items() if n not in locked})
    print("PASS a locked recon character fails its tests as a precondition:", want)


def test_same_seed(path):
    # obsy b run 1: after a Continue, Esau Jr. made a new entity with the presser's seed and type, its items re-rolled
    log = dry.run(path, mode=MODE, jrSameSeed=True)
    got = dry.finished(log, "Esau Jr. keeps the seed", path)
    assert got[LOST] == dry.want()[LOST], got[LOST]
    same = [s for s in log if s.startswith(f"PROBE INFO {LOST} Esau Jr. #") and " new form, same seed " in s]
    assert len(same) == 4 and " items 4:1/1 703:1/1 -> 53:1/1 703:1/1, INPUT_ACTION charge+battery 1 -> 0" in same[0], same
    assert not any(s.startswith(f"PROBE INFO {LOST} ") and "never happened" in s for s in log)
    print("PASS a press that keeps the seed is logged as data:", same[0])
    # Only press #1 keeps the seed: its TIMING watch is dropped, not woken by #2's new seed under #1's label
    log = dry.run(path, mode=MODE, jrSameSeed=1)  # STORED plays the session's first Esau Jr. press
    got = dry.finished(log, "Esau Jr. #1 keeps the seed", path)
    assert got[STORED] == dry.want()[STORED], got[STORED]
    assert any(s.startswith(f"PROBE INFO {STORED} Esau Jr. #1 new form, same seed ") for s in log)
    assert any(s.startswith(f"PROBE INFO {STORED} TIMING Esau Jr. #2 frame ") for s in log)
    assert not any(s.startswith(f"PROBE INFO {STORED} TIMING Esau Jr. #1 frame ") for s in log), "stale TIMING watch woke"
    print("PASS a same-seed press leaves no TIMING watch behind")


TESTS = [test_continue_lines, test_same_seed, test_locked_character]
