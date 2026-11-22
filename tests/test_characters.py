"""Dry checks of specs/characters.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
import dry

MODE = "tags characters"
BIRTHRIGHT_IDS = "ids of the Birthright twins through Flip, Esau Jr. and Exit & Continue"
TEMPORARY_ESAU = "temporary Esau has a number until he leaves"
NAMES = {  # each legacy scenario moved here, by its old name: [the names of its tests in this spec]
    "birthright": ["Birthright twins keep their items through two Flips and a new floor"],
    "P3": ["removing Birthright stores Dead Tainted Lazarus, and Flip brings him back"],
    "P1": ["temporary Esau from Soul of Jacob and Esau keeps his own items"],
    "final D Strawman": ["Strawman's Keeper is a character with his own items"],
    "final E Soul of Jacob and Esau": [TEMPORARY_ESAU],
    "final K tag through Flip": ["harness tag on Tainted Lazarus through Flip"],
    "final J Strawman Keeper leaves": ["Strawman's Keeper killed"],
    "obsy b identity": [BIRTHRIGHT_IDS],
}
# Each test's verdict under `tags all` when nothing fails, by "characters > <test>". The stub never takes the temporary Esau away on a
# room change (unobserved), so his test ends with a note and without its two assertions on his leaving.
WANT = {
    "characters > Birthright twins keep their items through two Flips and a new floor": "PASS 36 assertions",
    "characters > removing Birthright stores Dead Tainted Lazarus, and Flip brings him back": "PASS 30 assertions",
    "characters > temporary Esau from Soul of Jacob and Esau keeps his own items": "PASS 25 assertions",
    "characters > Strawman's Keeper is a character with his own items": "PASS 22 assertions",
    f"characters > {TEMPORARY_ESAU}": "PASS 13 assertions; unreached: summoned Esau never left",
    "characters > harness tag on Tainted Lazarus through Flip": "RECORDED",
    "characters > Strawman's Keeper killed": "RECORDED",
    f"characters > {BIRTHRIGHT_IDS}": "RECORDED",
}
# Decided behaviour changes (same_behaviour.py). Bug 3: final E no longer kills the summoned Esau at 60 updates (a wiki claim); it
# records the room change and whether he leaves, so its lines and its assertion count (masked on its RESULT) differ from HEAD's.
# Bug 7: VERDICT lines label characters by entity (GetPtrHash), not seed. D2: the fixture's done poll is a step, so a failed step's index
# is one higher (press ignored, no spend).
ALLOW = [
    ("bug 3", "final E Soul of Jacob and Esau", None),
    ("bug 3", "final E Soul of Jacob and Esau", r"PASS \d+ assertions"),
    ("bug 7", "obsy b identity", r"(?<= VERDICT ).*$"),
    *(("D2", old, r"(?<=error in step )\d+") for old in ("P3", "P1")),
]


def test_characters(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    lines = dry.segment(log, f"characters > {TEMPORARY_ESAU}")
    assert not any(" Kill()" in s for s in lines), "the temporary Esau was killed"
    assert any(" leave the room: StartRoomTransition " in s for s in lines), "no room change tried"
    info = dry.check_verdicts(log, [f"characters > {BIRTHRIGHT_IDS}"])[f"characters > {BIRTHRIGHT_IDS}"]
    assert any(s.startswith("VERDICT Flip after Continue index 0 A -> B moved from 1 |") for s in info), info
    assert sum(s.startswith("after Continue: player seeds ") for s in info) == 1, info
    ids = [s for s in info if s.startswith("IDS ")]
    assert len(ids) == 7 * 2 - 1 and all(" InitSeed " in s and " OtherTwin " in s and " MainTwin " in s for s in ids), ids  # one player after Esau Jr. #1
    # A Birthright twin's fresh copy stores presser and twin (obsyb1-2): the presser's spend is its watched drop, never a twin's seed
    swaps = [s for s in dry.segment(log, f"characters > {BIRTHRIGHT_IDS}") if s.startswith("PROBE SWAP Esau Jr. #")]
    assert " players 2 -> 1 " in swaps[0] and " players 1 -> 2 " in swaps[1], swaps
    assert all(" spent stored presser charge, " in s for s in swaps), swaps
    print(f"PASS {MODE}: verdicts, the temporary Esau's room change, the Birthright twins' ids and Esau Jr. spends")


TESTS = [test_characters]
