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
# D2: each test starts from a fixture, whose done poll and trace start take two updates after its setup: absolute frames come two
# later, and a failed step's index is two higher.
ALLOW = [
    *(("D2", old, r"frame \d+") for old in ("obsy b continue with A stored", "obsy b continue after B loses Esau Jr.")),
    *(("D2", old, r"error in step \d+") for old in ("continue", "continue settled", "L1")),
]
MODE = "tags continue"


def test_continue_lines(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    keeper = dry.segment(log, "continue > temporary Esau and Strawman's Keeper across Exit & Continue")
    assert any("HELPERS after Continue" in s and " type 14 parent index 0 " in s for s in keeper), "no Keeper after the Continue"
    print(f"PASS {MODE}: {sum('continue' in t.tags for t in dry.plan(path))} tests, Keeper after the Continue")


TESTS = [test_continue_lines]
