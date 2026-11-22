"""Dry checks of specs/characters.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
import dry

MODE = "tags characters"
BIRTHRIGHT_IDS = "ids of the Birthright twins through Flip, Esau Jr. and Exit & Continue"
TEMPORARY_ESAU = "temporary Esau has a number until he leaves"
CARDS = "Strawman, Soul of Jacob and Esau, Soul of the Forgotten, then Exit & Continue"
SWITCH = "switch between body and soul"
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
    **dry.recon("characters", CARDS),
    **dry.recon("characters", SWITCH, ("The Forgotten", "Tainted Forgotten")),
    **dry.recon("characters", "Birthright and Flip", ("Tainted Lazarus",)),
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
    recon = [f"characters > {c}: {CARDS}" for c in dry.RECON] + [f"characters > {c}: {SWITCH}" for c in ("The Forgotten", "Tainted Forgotten")]
    assert not any("never happened" in s for n in recon + ["characters > Tainted Lazarus: Birthright and Flip"] for s in dry.segment(log, n))
    def esau_added(s):  # "UseCard 97 players <n> -> <m> in the call"
        w = s.split()
        return s.startswith("UseCard 97 players ") and s.endswith(" in the call") and int(w[5]) == int(w[3]) + 1
    assert all(any(esau_added(s) for s in dry.infos(log, n)) for n in recon[:len(dry.RECON)]), "Soul of Jacob and Esau added no Esau"
    # bug 8: The Forgotten's drop press switches him to The Soul and back (stub: obsya1, the way back a shortcut); Tainted Forgotten's does
    # nothing in the stub (unobserved), logged as such
    forgotten, tainted = (dry.infos(log, f"characters > {c}: {SWITCH}") for c in ("The Forgotten", "Tainted Forgotten"))
    assert [s.split(" | ")[0] for s in forgotten if " drop press: " in s] == [f"{w} drop press: changed after 1 updates" for w in ("switch", "switch back")]
    assert sum(" drop press: nothing changed in 30 updates " in s and s.endswith("| polled true") for s in tainted) == 2, tainted
    print(f"PASS {MODE} recon: cards used, the body and soul switch by a real drop press, Birthright and Flip")


TESTS = [test_characters]
