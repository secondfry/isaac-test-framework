"""The invariants every settled look asserts: each one's negative stub mode fails exactly the tests it must, and a wrong floor fails every look."""
import dry

WANT = {}  # no spec of its own: it plays every spec
TEST3 = "base_change > ChangePlayerType out of Tainted Lazarus merges the stored twin"
P2 = "base_change > Clicker on Jacob and Esau until they split"
S3, R1, R1_MIRROR, P4C_2 = (f"regressions > {n}" for n in ("S3", "r1", "r1 mirror", "(P4c 2) Flip of the Esau Jr. character"))
MERGES = {TEST3, S3, "continue > Flip mid-settle, Exit & Continue, then ChangePlayerType",
          "continue > Flip once settled, Exit & Continue, then ChangePlayerType"}  # each merges a stored Dead form back
FINAL_C = "esau_jr > Tainted Lazarus's Esau Jr. character keeps its own items through Flips and presses"
FINAL_F = "esau_jr > Flip twins change after Esau Jr., then Clicker"
FINAL = {"esau_jr > two Esau Jr. copies each bring back their own character", "esau_jr > Esau Jr. dropped and picked up brings Isaac back",
         FINAL_C, FINAL_F, "characters > Strawman's Keeper is a character with his own items", "characters > temporary Esau has a number until he leaves",
         "base_change > Clicker merges and splits Jacob and Esau holding Inner Eye"}  # the rehud-2.8 tests outside regressions that look
NO_C4 = {"item_copies > Zodiac copy is clocked", "item_copies > 3 Dollar Bill copies are clocked",
         "item_copies > base character change learns the innate copy, clocked copies stay"}


def looked(path):
    """Every checked ReHUD test but the opt-in ones and engine's (they read the engine only): each settled look runs the invariants."""
    return {t.name for t in dry.plan(path) if not t.snapshot and "rehud" in t.tags and "opt-in" not in t.tags and not t.name.startswith("engine > ")}


# Each invariant's negative stub mode: (stub flag, tags line, the invariant's message, the tests it must fail on given the looked ones;
# the rest may fail on their own assertions).
INVARIANT_MODES = [
    ("missCopy", "tags all", "invariant engine counts: c4 of ", lambda looked: looked - NO_C4),
    ("dupCopy", "tags all", "invariant duplicates: c4 of ", lambda looked: looked - NO_C4),
    ("keepStored", "tags all", "invariant phantom stored forms: ", lambda _: MERGES),
    ("leaveNotMerge", "tags all", "invariant left entries: ", lambda _: MERGES | {P4C_2, P2, R1, R1_MIRROR}),
    # P2 and S3 list nothing after their last stage, so a next-floor name is still one they reached; S4's Esau Jr. form (holding c703) and
    # P1's summoned Esau do
    ("laterFloor", "tags all", "invariant floors: ", lambda looked: looked - {P2, S3}),
    # LJ and D share a seed: keyed by seed alone they share a row
    ("untagged", "tags rehud-2.8", "invariant characters: ", lambda _: {FINAL_C, FINAL_F}),
    ("phantomRow", "tags rehud-2.8", "invariant characters: ", lambda _: FINAL),
    # ReHUD's own esauJr flag exempts no row: only a character the harness saw Esau Jr. store
    ("phantomRow", "tags all", "invariant phantom stored forms: ", lambda looked: looked),
]


def test_wrong_floor(path):
    got = dry.finished(dry.run(path, wrongFloor=True), "wrong floor", path)
    # expectN names the wrong floor; a floor-filtered count names the floor it found too few on
    dry.expect_results(got, "wrong floor", dry.expected(path), ("on 'Wrong'", " on Floor"), looked(path))
    print("PASS a wrong ReHUD floor fails:", got[TEST3][:90])


def test_invariants(path):
    for flag, mode, why, names in INVARIANT_MODES:
        log = dry.run(path, mode=mode, **{flag: True})
        hits = {n for n, v in dry.finished(log, flag, path).items() if dry.fails(v, why)}
        assert hits == names(looked(path)), f"{flag} ({mode}): invariant fired in {sorted(hits)}"
        print(f"PASS {flag} ({mode}) fails the invariant in {len(hits)} tests")
        if flag == "missCopy":
            code, verdict = dry.report(log)
            reasons = verdict.removeprefix("NEEDS ANALYSIS: ").split("; ")
            assert code == 1 and verdict.startswith("NEEDS ANALYSIS: ") and f"{TEST3} FAIL" in reasons, (code, verdict)
            print("PASS report.py on a failing session:", verdict[:60])


TESTS = [test_wrong_floor, test_invariants]
