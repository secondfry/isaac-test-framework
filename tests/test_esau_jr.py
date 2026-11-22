"""Dry checks of specs/esau_jr.lua: its tests' verdicts and the checks of their own lines."""
import dry

COPIES, WALKED = "two Esau Jr. copies each bring back their own character", "Esau Jr. dropped and picked up brings Isaac back"
FLIP_TWINS = "Flip twins change after Esau Jr., then Clicker"
ASSERTING = {  # the tests with assertions: their PASS counts
    "Tainted Lazarus keeps one c4 through two Esau Jr. presses": 18, "Jacob's Esau Jr. character beside Esau gets character number 2": 29,
    COPIES: 46, WALKED: 25, "Tainted Lazarus's Esau Jr. character keeps its own items through Flips and presses": 39, FLIP_TWINS: 47,
}
CROSS = "Esau Jr. character turned Dead Tainted Lazarus, then Isaac, presses back"
PRESSES = [  # the strict snapshot tests of presses by each character and slot: each reaches its verdicts
    "Esau Jr. through the Schoolbag's second slot", "Esau Jr. through the Schoolbag with a Clicker press", "Esau Jr. character's Flips after losing Esau Jr.",
    "Isaac's Esau Jr. character uses Clicker's effect", "Esau Jr. presses by Jacob", "Esau Jr. presses by Esau", "Esau Jr. presses by The Forgotten and The Soul",
    "Esau Jr. presses by Tainted Forgotten", "Esau Jr. presses by Lazarus Risen", "Esau Jr. presses by Tainted Jacob", "Esau Jr. presses by Eden",
]
RECORDED = [  # the other snapshot tests
    CROSS, "Esau Jr. character turned Isaac presses back", "Esau Jr. character flips there and back, then presses back",
    "Esau Jr. character of a flipped-back Tainted Lazarus turned Dead Tainted Lazarus", "Birthright given and removed after Esau Jr.",
    "Esau Jr. with Birthright held from the start", "Clicker on the Esau Jr. character, then more presses",
    "Birthright on the Esau Jr. character, then it presses back", "Esau Jr. character turned Tainted Forgotten presses back",
    "Tainted Lazarus flips after an Esau Jr. round trip", "Birthright on the Esau Jr. character, then Flip",
    "Clicker on Tainted Lazarus back from its Esau Jr. character",
    "Clicker on a Birthright twin of the Esau Jr. character", "Clicker on Isaac's Esau Jr. character",
    "Tainted Lazarus's Esau Jr. character loses Esau Jr. and gets it back", "Tainted Lazarus's Esau Jr. character uses Clicker's effect",
    "Isaac's Esau Jr. character loses Esau Jr. and gets it back", "Tainted Lazarus loses Esau Jr. after a round trip, returns recorded",
    "Esau Jr. and Flip with Birthright twins", "Esau Jr. character of a flipped-back Tainted Lazarus flips, then turns Dead Tainted Lazarus",
    "Tainted Lazarus loses Esau Jr. after a round trip, verdict per press", *PRESSES,
]
# Each test's verdict under `tags all` when nothing fails, by "esau_jr > <test>"
RECON = "Esau Jr. press, press, Exit & Continue, press"
# The re-give adds no owned copy in the stub (tests/stub/characters.lua ChangePlayerType shortcut), so this test is cut there.
CUT = {"Clicker on the Esau Jr. character after its Flip": "RECORDED; unreached: 7 re-give c703 never happened, steps 8 Esau Jr. again to 11 settle skipped"}
WANT = {**{f"esau_jr > {n}": f"PASS {c} assertions" for n, c in ASSERTING.items()}, **{f"esau_jr > {n}": "RECORDED" for n in RECORDED},
        **{f"esau_jr > {n}": v for n, v in CUT.items()}, **dry.recon("esau_jr", RECON)}
MODE = "tags esau_jr"  # every test here, final F (opt-in) included


def test_esau_jr(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))

    info = dry.check_verdicts(log, [f"esau_jr > {test}" for test in PRESSES] + [f"esau_jr > {c}: {RECON}" for c in dry.RECON])

    def has(test, text):
        return any(text in s for s in info[f"esau_jr > {test}"])
    by_esau = "Esau Jr. presses by Esau"
    assert has(by_esau, "VERDICT Esau Jr. #1 index 1 B -> C new | 0:A(t19)=")
    assert has(by_esau, "index 1 type ") and has(by_esau, " primary 105 c703 owned 0")
    # bug 8: the drop press, as obsya1 saw it, swaps the Schoolbag's slots and turns The Forgotten into The Soul in 1 update
    assert has("Esau Jr. through the Schoolbag's second slot", "Esau Jr. to primary after 1 updates by drop press | primary 703 secondary 45")
    assert has("Esau Jr. presses by The Forgotten and The Soul", "switch to the Soul after 1 updates by drop press")
    assert has("Esau Jr. through the Schoolbag with a Clicker press", "VERDICT Clicker index 0 B -> unchanged")
    print("PASS esau_jr press and recon verdicts, timing, Schoolbag, Soul switch and Esau's presses")

    assert f"PROBE SNAP esau_jr > {CROSS} | 1 Esau Jr. / lineup = A" in log, "no SNAP line after the first step"
    recon = f"PROBE SNAP esau_jr > Isaac: {RECON} | 1 Esau Jr. #1 / TIMING Esau Jr. #1 +0 = index 0 type 0 c703 "
    assert any(s.startswith(recon) for s in log), "a recon test's TIMING frames are not in its snapshot"
    assert any(s.startswith("PROBE NUMBERS esau_jr > ") and " LJ stored key 4294967" in s for s in log), "LJ never listed on its own key beside D"
    # A press that brings back a character on the presser's seed is the presser's stored drop, not the returned one's charge
    swaps = [s for s in log if s.startswith("PROBE SWAP Flip LJ -> D ")]
    assert swaps and all(" spent stored presser charge, " in s for s in swaps), swaps
    copies, walked = f"esau_jr > {COPIES}", f"esau_jr > {WALKED}"
    assert any(s.startswith(f"PROBE INFO {copies} swap the Esau Jr. copies after 1 updates by drop press | ") for s in log)
    hand = [s for s in log if s.startswith(f"PROBE INFO {walked} YOU: ")]
    assert len(hand) == 2, hand
    assert not any(s.startswith(f"PROBE STUCK {walked} ") for s in log), "a manual step logged STUCK"
    traced = dry.segment(log, f"esau_jr > {FLIP_TWINS}")
    first_start = next(i for i, s in enumerate(traced) if s.startswith("PROBE GAME START "))
    assert not any(s.startswith("PROBE TRACE ") for s in traced[:first_start]), "final F's trace records the previous test's run"
    print(f"PASS {MODE}: SNAP, LJ's own number, stored presser spends, the copies' swap and the walks")


def test_drop_fallback(path):
    # a drop press the engine ignores: each drop step takes its fallback at 60 updates
    mode = "tags drop"
    log = dry.run(path, mode=mode, ignoreDrop=True)
    dry.expect_results(dry.finished(log, mode, path), mode, dry.expected(path, mode))
    for test, line in (("Esau Jr. through the Schoolbag's second slot", "Esau Jr. to primary after 61 updates by SwapActiveItems | primary 703 secondary 45"),
                       ("Esau Jr. presses by The Forgotten and The Soul", "switch to the Soul after 61 updates by ChangePlayerType 17")):
        assert any(s.startswith(line) for s in dry.infos(log, f"esau_jr > {test}")), line
    print(f"PASS {mode} with the drop press ignored: SwapActiveItems and ChangePlayerType fallbacks")


TESTS = [test_esau_jr, test_drop_fallback]
