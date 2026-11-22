"""The invariants every settled look asserts: each one's negative stub mode fails exactly the tests it must, and a wrong floor fails every look."""
import dry
from legacy_names import FINAL, FINAL_MODE, ONLY_PICKED, LOOKED, full, hit, expect_parts

WANT = {}  # no spec of its own: it plays every spec
FINAL_C4 = ["final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up", "final C Tainted Lazarus Esau Jr.", "final D Strawman",
            "final E Soul of Jacob and Esau"]  # F and G run only when tagged; G holds no c4
HOLDS_C4 = ["test3", "birthright", "P3", "P4a", "P4c", "S4", "P1", "P2", "S1", "S3", "r1", "r1 mirror", *FINAL_C4, "continue", "continue settled", "L1"]
# Each invariant's negative stub mode: (stub flag, tags line, the invariant's message, the tests it must fail on; the rest may fail on
# their own assertions).
INVARIANT_MODES = [
    ("missCopy", "tags all", "invariant engine counts: c4 of ", HOLDS_C4),
    ("dupCopy", "tags all", "invariant duplicates: c4 of ", HOLDS_C4),
    ("keepStored", "tags all", "invariant phantom stored forms: ", ["test3", "S3", "continue", "continue settled"]),
    ("leaveNotMerge", "tags all", "invariant left entries: ", ["test3", "P4c", "P2", "S3", "r1", "r1 mirror", "continue", "continue settled"]),
    # P2 and S3 list nothing after their last stage, so a next-floor name is still one they reached; S4's Esau Jr. form (holding c703) and
    # P1's summoned Esau do
    ("laterFloor", "tags all", "invariant floors: ", ["test3", "birthright", "P3", "P4a", "P4c", "S4", "P1", "S1", "S1b", "S2", "r1", "r1 mirror",
                                                       *(n for n in FINAL if n not in ONLY_PICKED), "continue", "continue settled", "L1"]),
    # LJ and D share a seed: keyed by seed alone they share a row
    ("untagged", FINAL_MODE, "invariant characters: ", ["final C Tainted Lazarus Esau Jr.", "final F Flip partners"]),
    ("phantomRow", FINAL_MODE, "invariant characters: ", FINAL),
    # ReHUD's own esauJr flag exempts no row: only a character the harness saw Esau Jr. store
    ("phantomRow", "tags all", "invariant phantom stored forms: ", [n for n in LOOKED if n not in ONLY_PICKED]),
]


def test_wrong_floor(path):
    got = dry.finished(dry.run(path, wrongFloor=True), "wrong floor", path)
    # expectN names the wrong floor; a floor-filtered count names the floor it found too few on
    expect_parts(got, "wrong floor", dry.expected(path), {n: ("on 'Wrong'", " on Floor") for n in LOOKED if n not in ONLY_PICKED})
    print("PASS a wrong ReHUD floor fails:", got[full("test3")][:90])


def test_invariants(path):
    for flag, mode, why, names in INVARIANT_MODES:
        log = dry.run(path, mode=mode, **{flag: True})
        hits = hit(dry.finished(log, flag, path), why)
        assert hits == names, f"{flag} ({mode}): invariant fired in {hits}"
        print(f"PASS {flag} ({mode}) fails the invariant in {len(hits)} old scenarios")
        if flag == "missCopy":
            code, verdict = dry.report(log)
            reasons = verdict.removeprefix("NEEDS ANALYSIS: ").split("; ")
            assert code == 1 and verdict.startswith("NEEDS ANALYSIS: ") and f"{full('test3')} FAIL" in reasons, (code, verdict)
            print("PASS report.py on a failing session:", verdict[:60])


TESTS = [test_wrong_floor, test_invariants]
