"""Dry checks of specs/esau_jr.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
import dry

# Each legacy scenario moved here, by its old name: [the names of its tests in this spec]
NAMES = {
    "P4a": ["Tainted Lazarus keeps one c4 through two Esau Jr. presses"],
    "obs esaujr cross": ["Esau Jr. character turned Dead Tainted Lazarus, then Isaac, presses back"],
    "obs esaujr out": ["Esau Jr. character turned Isaac presses back"],
    "obs esaujr flip": ["Esau Jr. character flips there and back, then presses back"],
    "obs esaujr flipped cross": ["Esau Jr. character of a flipped-back Tainted Lazarus turned Dead Tainted Lazarus"],
    "obs esaujr birthright": ["Birthright given and removed after Esau Jr.", "Esau Jr. with Birthright held from the start"],
    "obs esaujr clicker": ["Clicker on the Esau Jr. character, then more presses"],
    "obs esaujr birthright keep": ["Birthright on the Esau Jr. character, then it presses back"],
    "obs esaujr cross35": ["Esau Jr. character turned Tainted Forgotten presses back"],
    "obs esaujr dead seed": ["Tainted Lazarus flips after an Esau Jr. round trip"],
    "obs esaujr birthright flip": ["Birthright on the Esau Jr. character, then Flip"],
    "obsx Clicker on returned original": ["Clicker on Tainted Lazarus back from its Esau Jr. character"],
    "obsx Clicker after Flip": ["Clicker on the Esau Jr. character after its Flip"],
    "obsx Clicker with Birthright": ["Clicker on a Birthright twin of the Esau Jr. character"],
    "obsx Isaac Esau Jr Clicker": ["Clicker on Isaac's Esau Jr. character"],
    "obsx form loses Esau Jr.": ["Tainted Lazarus's Esau Jr. character loses Esau Jr. and gets it back"],
    "obsx form uses Clicker effect": ["Tainted Lazarus's Esau Jr. character uses Clicker's effect"],
    "obsx Isaac form loses Esau Jr.": ["Isaac's Esau Jr. character loses Esau Jr. and gets it back"],
    "obsx original loses Esau Jr.": ["Tainted Lazarus loses Esau Jr. after a round trip, returns recorded"],
    "obsy a schoolbag": ["Esau Jr. through the Schoolbag's second slot"],
    "obsy a schoolbag Clicker": ["Esau Jr. through the Schoolbag with a Clicker press"],
    "obsy a Dead form after A lost": ["Esau Jr. character's Flips after losing Esau Jr."],
    "obsy a Isaac Clicker effect": ["Isaac's Esau Jr. character uses Clicker's effect"],
    "obsy a J&E by Jacob": ["Esau Jr. presses by Jacob"],
    "obsy a J&E by Esau": ["Esau Jr. presses by Esau"],
    "obsy a Forgotten and Soul": ["Esau Jr. presses by The Forgotten and The Soul"],
    "obsy a Tainted Forgotten": ["Esau Jr. presses by Tainted Forgotten"],
    "obsy a Lazarus Risen": ["Esau Jr. presses by Lazarus Risen"],
    "obsy b Tainted Jacob": ["Esau Jr. presses by Tainted Jacob"],
    "obsy b Eden": ["Esau Jr. presses by Eden"],
    "S4": ["Jacob's Esau Jr. character beside Esau gets character number 2"],
    "final A two Esau Jr. copies": ["two Esau Jr. copies each bring back their own character"],
    "final B Esau Jr. dropped and picked up": ["Esau Jr. dropped and picked up brings Isaac back"],
    "final C Tainted Lazarus Esau Jr.": ["Tainted Lazarus's Esau Jr. character keeps its own items through Flips and presses"],
    "final F Flip partners": ["Flip twins change after Esau Jr., then Clicker"],
    "final I Birthright twins Esau Jr.": ["Esau Jr. and Flip with Birthright twins"],
    "final L flipped cross": ["Esau Jr. character of a flipped-back Tainted Lazarus flips, then turns Dead Tainted Lazarus"],
    "final M original loses Esau Jr.": ["Tainted Lazarus loses Esau Jr. after a round trip, verdict per press"],
}
CHECKED = {  # the tests with assertions, by old name: their PASS counts (every other test here is RECORDED)
    "P4a": 18, "S4": 29, "final A two Esau Jr. copies": 46, "final B Esau Jr. dropped and picked up": 25, "final C Tainted Lazarus Esau Jr.": 39,
    "final F Flip partners": 47,
}
# Each test's verdict under `tags all` when nothing fails, by "esau_jr > <test>"
WANT = {f"esau_jr > {new}": f"PASS {CHECKED[old]} assertions" if old in CHECKED else "RECORDED" for old, news in NAMES.items() for new in news}
# D2: a checked test's fixture poll and done step add two updates before its steps, so ReHUD's settle count at its first look (and, in
# final B, at the stored Isaac's return) and final F's trace update numbers shift; the snapshot tests' fixtures wait for the settle in
# place of the old settle step, so their lines stay the same.
ALLOW = [
    *(("D2", old, r"after \d+ updates stored settling.*$") for old in ("P4a", "S4", "final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up")),
    ("D2", "final F Flip partners", r"TRACE u\d+"),
]
OBSY = [NAMES[old][0] for old in NAMES if old.startswith("obsy ")]
MODE = "tags esau_jr"  # every test here, final F (opt-in) included


def test_esau_jr(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))

    def infos(test):
        prefix = f"PROBE INFO esau_jr > {test} "
        return [s[len(prefix):] for s in log if s.startswith(prefix)]
    info = {test: infos(test) for test in OBSY}

    def has(test, text):
        return any(text in s for s in info[test])
    for test in OBSY:  # every obsy test reaches its last press and names who holds the pressed index
        assert has(test, "VERDICT ") and not has(test, "never happened"), test
    for test in OBSY:  # each Esau Jr. press logs its character's first update
        for v in (s for s in info[test] if s.startswith("VERDICT Esau Jr.")):
            if " -> unchanged" in v:  # a fresh copy's character on the presser's seed: its TIMING watch is dropped (same-seed press)
                continue
            label = v[len("VERDICT "):].split(" index ")[0]
            assert has(test, f"TIMING {label} frame ") and has(test, f"TIMING {label} pressed at frame "), v
    timing = [(test, s.split(" index ")[0]) for test in OBSY for s in info[test] if s.startswith("TIMING ") and " frame " in s and " pressed at " not in s]
    assert timing and len(timing) == len(set(timing)), "a TIMING frame logged twice"
    by_esau = "Esau Jr. presses by Esau"
    assert has(by_esau, "VERDICT Esau Jr. #1 index 1 B -> C new | 0:A(t19)=")
    assert has(by_esau, "index 1 type ") and has(by_esau, " primary 105 c703 owned 0")
    assert has("Esau Jr. through the Schoolbag's second slot", "Esau Jr. to primary after 61 updates by SwapActiveItems | primary 703 secondary 45")
    assert has("Esau Jr. presses by The Forgotten and The Soul", "switch to the Soul after 61 updates by ChangePlayerType 17")
    assert has("Esau Jr. through the Schoolbag with a Clicker press", "VERDICT Clicker index 0 B -> unchanged")
    print("PASS esau_jr obsy verdicts, timing, Schoolbag, Soul switch and Esau's presses")

    cross = NAMES["obs esaujr cross"][0]
    assert f"PROBE SNAP esau_jr > {cross} | 1 Esau Jr. / lineup = A" in log, "no SNAP line after the first step"
    assert any(s.startswith("PROBE NUMBERS esau_jr > ") and " LJ stored key 4294967" in s for s in log), "LJ never listed on its own key beside D"
    # A press that brings back a character on the presser's seed is the presser's stored drop, not the returned one's charge
    swaps = [s for s in log if s.startswith("PROBE SWAP Flip LJ -> D ")]
    assert swaps and all(" spent stored presser charge, " in s for s in swaps), swaps
    copies, walked = (f"esau_jr > {NAMES[old][0]}" for old in ("final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up"))
    assert any(s.startswith(f"PROBE INFO {copies} swap the Esau Jr. copies after ") and " by SwapActiveItems | " in s for s in log)
    hand = [s for s in log if s.startswith(f"PROBE INFO {walked} YOU: ")]
    assert len(hand) == 2, hand
    assert not any(s.startswith(f"PROBE STUCK {walked} ") for s in log), "a manual step logged STUCK"
    print(f"PASS {MODE}: SNAP, LJ's own number, stored presser spends, the copies' swap and the walks")


TESTS = [test_esau_jr]
