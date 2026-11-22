"""Dry checks of specs/base_change.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
import dry

SPEC = "base_change"
MODE = f"tags {SPEC}"
P2 = "Clicker on Jacob and Esau until they split"
VETOED = ["a cancelled Clicker on the Esau Jr. character", "a cancelled Clicker, then ChangePlayerType in the same update"]
NAMES = {  # each legacy scenario moved here, by its old name: [the names of its tests in this spec]
    "test3": ["ChangePlayerType out of Tainted Lazarus merges the stored twin"],
    "P2": [P2],
    "final G Jacob and Esau Clicker split": ["Clicker merges and splits Jacob and Esau holding Inner Eye"],
    "obs mirror": ["ChangePlayerType into Dead Tainted Lazarus with the twin stored, then Flip"],
    "obsx cancelled Clicker": [VETOED[0]],
    "obsx cancelled Clicker then change": [VETOED[1]],
    "obsx merge 38 to 29 then Flip": ["ChangePlayerType into Tainted Lazarus merges the stored twin, then Flip at once"],
    "obsx merge 29 to 38 then Esau Jr.": ["ChangePlayerType into Dead Tainted Lazarus merges the stored twin, then Esau Jr. at once"],
}
# Each test's verdict under `tags all` when nothing fails, by "base_change > <test>". P2 counts 8 or 9 per Clicker use: 22 here (the stub's
# Clicker splits on its second use), any number in game.
WANT = {
    f"{SPEC} > {NAMES['test3'][0]}": "PASS 15 assertions",
    f"{SPEC} > {P2}": "PASS 22 assertions",
    f"{SPEC} > {NAMES['final G Jacob and Esau Clicker split'][0]}": "PASS 18 assertions",
    f"{SPEC} > {NAMES['obs mirror'][0]}": "RECORDED",
    f"{SPEC} > {VETOED[0]}": "PASS 1 assertions",
    f"{SPEC} > {VETOED[1]}": "PASS 1 assertions",
    f"{SPEC} > {NAMES['obsx merge 38 to 29 then Flip'][0]}": "RECORDED",
    f"{SPEC} > {NAMES['obsx merge 29 to 38 then Esau Jr.'][0]}": "RECORDED",
    **dry.recon(SPEC, "Clicker, then Exit & Continue"),
}
# The plan's first fired assertion, "a vetoed Clicker fires no MC_USE_ITEM", adds an INFO line and turns RECORDED into PASS. D2: the
# fixture's done poll is a step, so a failed step's index is one higher (press ignored, no spend).
ALLOW = [("plan fired", "obsx cancelled Clicker", None), ("plan fired", "obsx cancelled Clicker then change", None),
         ("D2", "P2", r"(?<=error in step )\d+")]


def test_base_change_lines(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    p2 = dry.segment(log, f"{SPEC} > {P2}")
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in p2), "P2 never split"
    for name in VETOED:
        line = f"PROBE INFO {SPEC} > {name} vetoed Clicker: callback 3 with 482 fired 0"
        assert line in dry.segment(log, f"{SPEC} > {name}"), name
    print("PASS base_change: P2 reaches the split, a vetoed Clicker fires no MC_USE_ITEM")
    for c in dry.RECON:
        info = dry.infos(log, f"{SPEC} > {c}: Clicker, then Exit & Continue")
        assert any(s.startswith("VERDICT Clicker index 0 ") for s in info) and not any("never happened" in s for s in info), (c, info)
    print("PASS base_change recon: every character's Clicker press reaches its verdict")


TESTS = [test_base_change_lines]
