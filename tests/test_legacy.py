"""Temporary: the tests of specs/legacy.lua, their verdicts and tags, and the checks that read their own lines (plan S4 moves each into
its spec's test module)."""
import dry

SPEC = "legacy > "  # every test still lives in specs/legacy.lua
OBS = ["obs esaujr cross", "obs esaujr out", "obs esaujr flip", "obs esaujr flipped cross", "obs esaujr birthright", "obs esaujr clicker", "obs mirror",
       "obs esaujr birthright keep", "obs esaujr cross35", "obs esaujr dead seed", "obs esaujr birthright flip"]
DISPUTES = [
    "obsx cancelled Clicker", "obsx cancelled Clicker then change", "obsx Clicker on returned original",
    "obsx Clicker after Flip", "obsx Clicker with Birthright", "obsx Isaac Esau Jr Clicker",
    "obsx merge 38 to 29 then Flip", "obsx merge 29 to 38 then Esau Jr.",
    "obsx form loses Esau Jr.", "obsx form uses Clicker effect", "obsx Isaac form loses Esau Jr.", "obsx original loses Esau Jr.",
]
OBSY_A = ["obsy a schoolbag", "obsy a schoolbag Clicker", "obsy a Dead form after A lost", "obsy a Isaac Clicker effect",
          "obsy a J&E by Jacob", "obsy a J&E by Esau", "obsy a Forgotten and Soul", "obsy a Tainted Forgotten", "obsy a Lazarus Risen"]
OBSY_B = ["obsy b Tainted Jacob", "obsy b Eden", "obsy b continue with A stored", "obsy b continue after B loses Esau Jr.", "obsy b identity"]
OBSY_LARGE = {"obsy b continue with A stored", "obsy b continue after B loses Esau Jr.", "obsy b identity"}  # exit-continue, not new
FINAL_LARGE = {"final N summoned Esau across Continue"}
OBSY = OBSY_A + OBSY_B
OBS += DISPUTES + OBSY
FINAL = ["final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up", "final C Tainted Lazarus Esau Jr.", "final D Strawman",
         "final E Soul of Jacob and Esau", "final F Flip partners", "final G Jacob and Esau Clicker split"]
ONLY_PICKED = {"final F Flip partners", "final G Jacob and Esau Clicker split"}  # mirrors legacy.lua's opt-in tags
FINAL_OBS = ["final I Birthright twins Esau Jr.", "final K tag through Flip", "final L flipped cross", "final M original loses Esau Jr.",
             "final J Strawman Keeper leaves", "final N summoned Esau across Continue"]  # recon tests
FINAL_MODE = "tags rehud-2.8"
FINAL_RUN = ["P4c", "S3", "r1", "r1 mirror", *FINAL, *FINAL_OBS]
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "P4c", *OBS, "S4", "P1", "P2", "S1", "S1b", "S2", "S3", "r1", "r1 mirror",
             *FINAL, *FINAL_OBS, "continue", "continue settled", "L1"]
FULL = [SPEC + n for n in SCENARIOS]
NO_SWAP = {"S1", "S1b", "S2", "L1", "final D Strawman", *OBS, *FINAL_OBS}  # an obs press that never swaps is data, not a fail
NEW = {"continue", "continue settled", "L1"}  # mirrors legacy.lua's new tags
LARGE = NEW | OBSY_LARGE | FINAL_LARGE
# Test limits in updates (legacy.lua budget, obsScenario budget); rehud-2.8's worst case is their sum.
BUDGET = {"P4c": 600, "S3": 200, "r1": 250, "r1 mirror": 200, "final A two Esau Jr. copies": 350, "final B Esau Jr. dropped and picked up": 1100,
          "final C Tainted Lazarus Esau Jr.": 350, "final D Strawman": 200, "final E Soul of Jacob and Esau": 350, "final F Flip partners": 450,
          "final G Jacob and Esau Clicker split": 750, **{n: 1000 if n in FINAL_LARGE else 445 for n in FINAL_OBS}}
# Exact verdicts: a lost assertion or note shows. Each look adds 5 invariant assertions (a lookC 6). P2 counts 8 or 9 per Clicker use: 22
# here (the stub's Clicker splits on its second use), any number in game.
WANT = {
    "probes": "PASS 10 assertions",
    "test3": "PASS 15 assertions",
    "birthright": "PASS 36 assertions",
    "P3": "PASS 30 assertions",
    "P4a": "PASS 18 assertions",
    "P4c": "PASS 87 assertions",
    "S4": "PASS 29 assertions",
    "P1": "PASS 25 assertions",
    "P2": "PASS 22 assertions",
    "continue": "PASS 14 assertions",
    "continue settled": "PASS 20 assertions",
    "S1": "PASS 53 assertions",
    "S1b": "PASS 37 assertions",
    "S2": "PASS 29 assertions",
    "S3": "PASS 24 assertions",
    "r1": "PASS 27 assertions",
    "r1 mirror": "PASS 18 assertions",
    "L1": "PASS 30 assertions",
    "final A two Esau Jr. copies": "PASS 46 assertions",
    "final B Esau Jr. dropped and picked up": "PASS 25 assertions",
    "final C Tainted Lazarus Esau Jr.": "PASS 39 assertions",
    "final D Strawman": "PASS 22 assertions",
    "final E Soul of Jacob and Esau": "PASS 15 assertions",
    "final F Flip partners": "PASS 47 assertions",
    "final G Jacob and Esau Clicker split": "PASS 18 assertions",
    **{n: "RECORDED" for n in OBS + FINAL_OBS},
}
# The tests each of legacy.lua's own tags picks.
TAGGED = {"obs": set(OBS), "obsx": set(DISPUTES), "obsy-a": set(OBSY_A), "obsy-b": set(OBSY_B), "rehud-2.8": set(FINAL_RUN),
          "continue-a-stored": {"obsy b continue with A stored"}, "continue-b-loses": {"obsy b continue after B loses Esau Jr."}}


def tags_of(n):
    own = {"legacy", "rehud", *(t for t, names in TAGGED.items() if n in names)}
    return own | {t for t, on in (("exit-continue", n in LARGE), ("new", n in NEW), ("opt-in", n in ONLY_PICKED)) if on}


TESTS_TAGS = {n: (WANT[n], tags_of(n)) for n in SCENARIOS}
LOOKED = [n for n in SCENARIOS if n != "probes" and n not in OBS and n not in FINAL_OBS]  # every test with a look: the invariants run there
STORED = "spent nothing: stored presser seen with no drop after its use"
CHECKED_FINAL = [n for n in FINAL_RUN if n not in FINAL_OBS]


def finished(log, label):
    """The RESULTs of a finished session, by the test names above (without the spec)."""
    return {k[len(SPEC):]: v for k, v in dry.check_finished(log, label, FULL).items()}


def wanted(mode):
    return dry.wanted(mode, TESTS_TAGS)


def expect_results(got, label, mode="tags all", why=None, names=(), want=None):
    dry.expect_results(got, label, want or wanted(mode), why, names)


def check_obsy(log):
    """The obsy lines a log reader decides on, as the stub plays them."""
    info = [s[len("PROBE INFO " + SPEC):] for s in log if s.startswith("PROBE INFO " + SPEC + "obsy ")]

    def has(name, text):
        return any(s.startswith(name + " ") and text in s for s in info)
    for name in OBSY:  # every test reaches its last press and names who holds the pressed index
        assert has(name, "VERDICT ") and not has(name, "never happened"), name
    verdicts = [s for s in info if " VERDICT Esau Jr." in s]
    for v in verdicts:  # each Esau Jr. press logs the form's first update
        name, label = v.split(" VERDICT ")[0], v.split(" VERDICT ")[1].split(" index ")[0]
        if " -> unchanged" in v:  # a fresh copy's form on the presser's seed: its TIMING watch is dropped (same-seed press)
            continue
        assert has(name, f"TIMING {label} frame ") and has(name, f"TIMING {label} pressed at frame "), v
    assert has("obsy a J&E by Esau", "VERDICT Esau Jr. #1 index 1 B -> C new | 0:A(t19)=")
    timing = [s.split(" index ")[0] for s in info if " TIMING " in s and " frame " in s and " pressed at " not in s]
    assert timing and len(timing) == len(set(timing)), "a TIMING frame logged twice"
    assert has("obsy a schoolbag", "Esau Jr. to primary after 61 updates by SwapActiveItems | primary 703 secondary 45")
    assert has("obsy a Forgotten and Soul", "switch to the Soul after 61 updates by ChangePlayerType 17")
    assert has("obsy a schoolbag Clicker", "VERDICT Clicker index 0 B -> unchanged")
    assert has("obsy a J&E by Esau", "index 1 type ") and has("obsy a J&E by Esau", " primary 105 c703 owned 0")
    assert has("obsy b identity", "VERDICT Flip after Continue index 0 A -> B moved from 1 |")
    assert sum(" after Continue: player seeds " in s for s in info) == len(OBSY_LARGE)
    ids = [s for s in info if s.startswith("obsy b identity IDS ")]
    assert len(ids) == 7 * 2 - 1 and all(" InitSeed " in s and " OtherTwin " in s and " MainTwin " in s for s in ids), ids  # one player after Esau Jr. #1
    # A Birthright twin's fresh copy stores presser and twin (obsyb1-2): the presser's spend is its watched drop, never a twin's seed
    swaps = [s for s in dry.segment(log, SPEC + "obsy b identity") if s.startswith("PROBE SWAP Esau Jr. #")]
    assert " players 2 -> 1 " in swaps[0] and " players 1 -> 2 " in swaps[1], swaps
    assert all(" spent stored presser charge, " in s for s in swaps), swaps
    print("PASS obsy verdicts, timing, Schoolbag, Soul switch, Continue, ids and Birthright twin lines")


def test_all(path):
    log = dry.run(path)
    got = finished(log, "tags all")
    for name in SCENARIOS:
        print("RESULT", name, got[name])
    expect_results(got, "tags all")
    assert f"PROBE HARNESS START {len(SCENARIOS)} tests, tags 'tags all', update snapshots no, mod data 'tags all'" in log, "tags not logged"
    assert sum(s.startswith("PROBE GAME START") and s.endswith("continued true") for s in log) == 3 + len(OBSY_LARGE) + len(FINAL_LARGE), "the continues did not resume"
    presses = [s for s in log if s.startswith("PROBE PRESS ")]
    swaps = [s for s in log if s.startswith("PROBE SWAP ")]
    stored = [s for s in swaps if " spent stored presser charge, " in s]
    same = [s for s in log if s.startswith("PROBE INFO ") and " new form, same seed " in s]  # a fresh copy's form on its presser's seed
    assert presses and len(presses) == len(swaps) + len(same) and stored, (len(presses), len(swaps), len(same), len(stored))
    assert not any("(seed holds no" in s for s in swaps)
    print("PASS every swap logged a spend:", len(swaps), "swaps,", len(stored), "by a stored presser")
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in log), "P2 never split"
    print("PASS P2 reaches the split")
    check_obsy(log)
    snaps = [s for s in log if s.startswith("PROBE SNAP ")]
    assert f"PROBE SNAP {SPEC}obs esaujr cross | 1 Esau Jr. / lineup = A" in snaps, snaps[:3]
    assert not any(s.startswith(f"PROBE SNAP {SPEC}probes ") for s in snaps), "SNAP lines in a test without a snapshot"
    print("PASS SNAP lines for snapshot tests only:", len(snaps))


def test_tlaz_roll_29(path):
    # Clicker from the Dead form rolling 29 (run 8): S3's merge assertions with Flip kept, the rest unchanged
    got = finished(dry.run(path, tlazRoll=29), "Clicker rolls 29")
    expect_results(got, "Clicker rolls 29", want={**wanted("tags all"), "S3": "PASS 21 assertions"})
    print("PASS Clicker rolling 29:", got["S3"])


def test_final(path):
    log = dry.run(path, mode=FINAL_MODE)
    expect_results(finished(log, FINAL_MODE), FINAL_MODE, mode=FINAL_MODE)
    rows = [s for s in log if s.startswith(f"PROBE NUMBERS {SPEC}final ")]
    assert any(" LJ stored key 4294967" in s for s in rows), "LJ never listed on its own key beside D"
    # A press that brings back a character on the presser's seed is the presser's stored drop, not the returned one's charge
    for label in ("Flip LJ -> D", "Flip of the form"):
        swaps = [s for s in log if s.startswith(f"PROBE SWAP {label} ")]
        assert swaps and all(" spent stored presser charge, " in s for s in swaps), (label, swaps)
    assert any(s.startswith(f"PROBE INFO {SPEC}final A two Esau Jr. copies swap the Esau Jr. copies after ") and " by SwapActiveItems | " in s for s in log)
    hand = [s for s in log if s.startswith(f"PROBE INFO {SPEC}final B Esau Jr. dropped and picked up YOU: ")]
    assert len(hand) == 2, hand
    assert not any(s.startswith(f"PROBE STUCK {SPEC}final B") for s in log), "a manual step logged STUCK"
    assert any("HELPERS after Continue" in s and " type 14 parent index 0 " in s for s in log), "no Keeper after the Continue"
    print(f"PASS {FINAL_MODE}: {len(FINAL_RUN)} tests, {dry.run.updates} updates in the stub")


TESTS = [test_all, test_tlaz_roll_29, test_final]
