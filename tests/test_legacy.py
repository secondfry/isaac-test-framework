"""Temporary: the verdicts of the tests still in specs/legacy.lua and the checks of their own lines. Plan S4 moves each test's WANT line
and checks into its spec's test_<spec>.py; the checks name tests by legacy_names.full, so they hold wherever a test plays."""
import dry
from legacy_names import FINAL, FINAL_MODE, OBSY, OBSY_LARGE, full, names

# Exact verdicts: a lost assertion or note shows. Each look adds 5 invariant assertions (a lookC 6). P2 counts 8 or 9 per Clicker use: 22
# here (the stub's Clicker splits on its second use), any number in game.
WANT = {
    "legacy > probes": "PASS 10 assertions",
    "legacy > test3": "PASS 15 assertions",
    "legacy > P4a": "PASS 18 assertions",
    "legacy > P4c": "PASS 87 assertions",
    "legacy > obs esaujr cross": "RECORDED",
    "legacy > obs esaujr out": "RECORDED",
    "legacy > obs esaujr flip": "RECORDED",
    "legacy > obs esaujr flipped cross": "RECORDED",
    "legacy > obs esaujr birthright": "RECORDED",
    "legacy > obs esaujr clicker": "RECORDED",
    "legacy > obs mirror": "RECORDED",
    "legacy > obs esaujr birthright keep": "RECORDED",
    "legacy > obs esaujr cross35": "RECORDED",
    "legacy > obs esaujr dead seed": "RECORDED",
    "legacy > obs esaujr birthright flip": "RECORDED",
    "legacy > obsx cancelled Clicker": "RECORDED",
    "legacy > obsx cancelled Clicker then change": "RECORDED",
    "legacy > obsx Clicker on returned original": "RECORDED",
    "legacy > obsx Clicker after Flip": "RECORDED",
    "legacy > obsx Clicker with Birthright": "RECORDED",
    "legacy > obsx Isaac Esau Jr Clicker": "RECORDED",
    "legacy > obsx merge 38 to 29 then Flip": "RECORDED",
    "legacy > obsx merge 29 to 38 then Esau Jr.": "RECORDED",
    "legacy > obsx form loses Esau Jr.": "RECORDED",
    "legacy > obsx form uses Clicker effect": "RECORDED",
    "legacy > obsx Isaac form loses Esau Jr.": "RECORDED",
    "legacy > obsx original loses Esau Jr.": "RECORDED",
    "legacy > obsy a schoolbag": "RECORDED",
    "legacy > obsy a schoolbag Clicker": "RECORDED",
    "legacy > obsy a Dead form after A lost": "RECORDED",
    "legacy > obsy a Isaac Clicker effect": "RECORDED",
    "legacy > obsy a J&E by Jacob": "RECORDED",
    "legacy > obsy a J&E by Esau": "RECORDED",
    "legacy > obsy a Forgotten and Soul": "RECORDED",
    "legacy > obsy a Tainted Forgotten": "RECORDED",
    "legacy > obsy a Lazarus Risen": "RECORDED",
    "legacy > obsy b Tainted Jacob": "RECORDED",
    "legacy > obsy b Eden": "RECORDED",
    "legacy > obsy b continue with A stored": "RECORDED",
    "legacy > obsy b continue after B loses Esau Jr.": "RECORDED",
    "legacy > S4": "PASS 29 assertions",
    "legacy > P2": "PASS 22 assertions",
    "legacy > S1": "PASS 53 assertions",
    "legacy > S1b": "PASS 37 assertions",
    "legacy > S2": "PASS 29 assertions",
    "legacy > S3": "PASS 24 assertions",
    "legacy > r1": "PASS 27 assertions",
    "legacy > r1 mirror": "PASS 18 assertions",
    "legacy > final A two Esau Jr. copies": "PASS 46 assertions",
    "legacy > final B Esau Jr. dropped and picked up": "PASS 25 assertions",
    "legacy > final C Tainted Lazarus Esau Jr.": "PASS 39 assertions",
    "legacy > final F Flip partners": "PASS 47 assertions",
    "legacy > final G Jacob and Esau Clicker split": "PASS 18 assertions",
    "legacy > final I Birthright twins Esau Jr.": "RECORDED",
    "legacy > final L flipped cross": "RECORDED",
    "legacy > final M original loses Esau Jr.": "RECORDED",
    "legacy > final N summoned Esau across Continue": "RECORDED",
    "legacy > continue": "PASS 14 assertions",
    "legacy > continue settled": "PASS 20 assertions",
    "legacy > L1": "PASS 30 assertions",
}


def infos(log, old):
    """The INFO lines of the test old scenario `old` became, after its `PROBE INFO <test> `."""
    prefix = f"PROBE INFO {full(old)} "
    return [s[len(prefix):] for s in log if s.startswith(prefix)]


def check_obsy(log):
    """The obsy lines a log reader decides on, as the stub plays them."""
    info = {old: infos(log, old) for old in OBSY}

    def has(old, text):
        return any(text in s for s in info[old])
    for old in OBSY:  # every test reaches its last press and names who holds the pressed index
        assert has(old, "VERDICT ") and not has(old, "never happened"), old
    for old in OBSY:  # each Esau Jr. press logs the form's first update
        for v in (s for s in info[old] if s.startswith("VERDICT Esau Jr.")):
            if " -> unchanged" in v:  # a fresh copy's form on the presser's seed: its TIMING watch is dropped (same-seed press)
                continue
            label = v[len("VERDICT "):].split(" index ")[0]
            assert has(old, f"TIMING {label} frame ") and has(old, f"TIMING {label} pressed at frame "), v
    assert has("obsy a J&E by Esau", "VERDICT Esau Jr. #1 index 1 B -> C new | 0:A(t19)=")
    timing = [(old, s.split(" index ")[0]) for old in OBSY for s in info[old] if s.startswith("TIMING ") and " frame " in s and " pressed at " not in s]
    assert timing and len(timing) == len(set(timing)), "a TIMING frame logged twice"
    assert has("obsy a schoolbag", "Esau Jr. to primary after 61 updates by SwapActiveItems | primary 703 secondary 45")
    assert has("obsy a Forgotten and Soul", "switch to the Soul after 61 updates by ChangePlayerType 17")
    assert has("obsy a schoolbag Clicker", "VERDICT Clicker index 0 B -> unchanged")
    assert has("obsy a J&E by Esau", "index 1 type ") and has("obsy a J&E by Esau", " primary 105 c703 owned 0")
    assert sum(s.startswith("after Continue: player seeds ") for old in OBSY for s in info[old]) == len(OBSY_LARGE)
    print("PASS obsy verdicts, timing, Schoolbag, Soul switch, Continue, ids and Birthright twin lines")


def test_legacy_lines(path):
    log = dry.run(path)
    dry.finished(log, "tags all", path)
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in log), "P2 never split"
    print("PASS P2 reaches the split")
    check_obsy(log)
    snaps = [s for s in log if s.startswith("PROBE SNAP ")]
    assert f"PROBE SNAP {full('obs esaujr cross')} | 1 Esau Jr. / lineup = A" in snaps, snaps[:3]
    assert not any(s.startswith(f"PROBE SNAP {n} ") for n in names()["probes"] for s in snaps), "SNAP lines in a test without a snapshot"
    print("PASS SNAP lines for snapshot tests only:", len(snaps))


def test_tlaz_roll_29(path):
    # Clicker from the Dead form rolling 29 (run 8): S3's merge assertions with Flip kept, the rest unchanged
    got = dry.finished(dry.run(path, tlazRoll=29), "Clicker rolls 29", path)
    dry.expect_results(got, "Clicker rolls 29", {**dry.expected(path), full("S3"): "PASS 21 assertions"})
    print("PASS Clicker rolling 29:", got[full("S3")])


def test_final(path):
    log = dry.run(path, mode=FINAL_MODE)
    dry.expect_results(dry.finished(log, FINAL_MODE, path), FINAL_MODE, dry.expected(path, FINAL_MODE))
    rows = [s for s in log for n in FINAL if s.startswith(f"PROBE NUMBERS {full(n)} ")]
    assert any(" LJ stored key 4294967" in s for s in rows), "LJ never listed on its own key beside D"
    # A press that brings back a character on the presser's seed is the presser's stored drop, not the returned one's charge
    for label in ("Flip LJ -> D", "Flip of the form"):
        swaps = [s for s in log if s.startswith(f"PROBE SWAP {label} ")]
        assert swaps and all(" spent stored presser charge, " in s for s in swaps), (label, swaps)
    final_a, final_b = full("final A two Esau Jr. copies"), full("final B Esau Jr. dropped and picked up")
    assert any(s.startswith(f"PROBE INFO {final_a} swap the Esau Jr. copies after ") and " by SwapActiveItems | " in s for s in log)
    hand = [s for s in log if s.startswith(f"PROBE INFO {final_b} YOU: ")]
    assert len(hand) == 2, hand
    assert not any(s.startswith(f"PROBE STUCK {final_b} ") for s in log), "a manual step logged STUCK"
    assert any("HELPERS after Continue" in s and " type 14 parent index 0 " in s for s in log), "no Keeper after the Continue"
    print(f"PASS {FINAL_MODE}: {sum('rehud-2.8' in t.tags for t in dry.plan(path))} tests, {dry.run.updates} updates in the stub")


TESTS = [test_legacy_lines, test_tlaz_roll_29, test_final]
