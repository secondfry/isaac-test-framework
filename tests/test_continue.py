"""Dry checks of specs/continue.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
import dry

NAMES = {  # each legacy scenario moved here, by its old name: [the names of its tests in this spec]
    "obsy b continue with A stored": ["Esau Jr. character stored across Exit & Continue"],
    "obsy b continue after B loses Esau Jr.": ["Esau Jr. lost, then Exit & Continue"],
    "final N summoned Esau across Continue": ["temporary Esau and Strawman's Keeper across Exit & Continue"],
    "continue": ["Flip mid-settle, Exit & Continue, then ChangePlayerType"],
    "continue settled": ["Flip once settled, Exit & Continue, then ChangePlayerType"],
    "L1": ["item copies survive Exit & Continue"],
}
WANT = {  # each test's verdict under `tags all` when nothing fails, by "continue > <test>"
    "continue > Esau Jr. character stored across Exit & Continue": "RECORDED",
    "continue > Esau Jr. lost, then Exit & Continue": "RECORDED",
    "continue > temporary Esau and Strawman's Keeper across Exit & Continue": "RECORDED",
    "continue > Flip mid-settle, Exit & Continue, then ChangePlayerType": "PASS 14 assertions",
    "continue > Flip once settled, Exit & Continue, then ChangePlayerType": "PASS 20 assertions",
    "continue > item copies survive Exit & Continue": "PASS 30 assertions",
}
# Bug 7: VERDICT lines label characters by entity (GetPtrHash), not seed, so a same-seed new form reads "new", not "unchanged" (same
# seed configs). D2: the fixture's done poll is a step, so a failed step's index is one higher (a new run instead of the Continue).
ALLOW = [
    *(("bug 7", old, r"(?<= VERDICT ).*$") for old in ("obsy b continue with A stored", "obsy b continue after B loses Esau Jr.")),
    *(("D2", old, r"(?<=error in step )\d+") for old in ("continue", "continue settled", "L1")),
]
MODE = "tags continue"
STORED, LOST = (f"continue > {NAMES[old][0]}" for old in ("obsy b continue with A stored", "obsy b continue after B loses Esau Jr."))


def test_continue_lines(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    keeper = dry.segment(log, "continue > temporary Esau and Strawman's Keeper across Exit & Continue")
    assert any("HELPERS after Continue" in s and " type 14 parent index 0 " in s for s in keeper), "no Keeper after the Continue"
    for name, lines in dry.check_verdicts(log, [STORED, LOST]).items():
        assert sum(s.startswith("after Continue: player seeds ") for s in lines) == 1, name
    print(f"PASS {MODE}: {sum('continue' in t.tags for t in dry.plan(path))} tests, Keeper after the Continue, Esau Jr. verdicts and timing")


def test_same_seed(path):
    # obsy b run 1: after a Continue, Esau Jr. made a new entity with the presser's seed and type, its items re-rolled
    log = dry.run(path, mode="tags continue-b-loses", jrSameSeed=True)
    got = dry.finished(log, "Esau Jr. keeps the seed", path)
    assert got[LOST] == dry.want()[LOST], got[LOST]
    same = [s for s in log if s.startswith(f"PROBE INFO {LOST} Esau Jr. #") and " new form, same seed " in s]
    assert len(same) == 4 and " items 4:1/1 703:1/1 -> 53:1/1 703:1/1, INPUT_ACTION charge+battery 1 -> 0" in same[0], same
    assert not any(s.startswith(f"PROBE INFO {LOST} ") and "never happened" in s for s in log)
    print("PASS a press that keeps the seed is logged as data:", same[0])
    # Only press #1 keeps the seed: its TIMING watch is dropped, not woken by #2's new seed under #1's label
    log = dry.run(path, mode="tags continue-a-stored", jrSameSeed=1)
    got = dry.finished(log, "Esau Jr. #1 keeps the seed", path)
    assert got[STORED] == dry.want()[STORED], got[STORED]
    assert any(s.startswith(f"PROBE INFO {STORED} Esau Jr. #1 new form, same seed ") for s in log)
    assert any(s.startswith(f"PROBE INFO {STORED} TIMING Esau Jr. #2 frame ") for s in log)
    assert not any(s.startswith(f"PROBE INFO {STORED} TIMING Esau Jr. #1 frame ") for s in log), "stale TIMING watch woke"
    print("PASS a same-seed press leaves no TIMING watch behind")


TESTS = [test_continue_lines, test_same_seed]
