"""Dry checks of specs/base_change.lua: its tests' verdicts and the checks of their own lines."""
import dry

SPEC = "base_change"
MODE = f"tags {SPEC}"
P2 = "Clicker on Jacob and Esau until they split"
VETOED = ["a cancelled Clicker on the Esau Jr. character", "a cancelled Clicker, then ChangePlayerType in the same update"]
# Each test's verdict under `tags all` when nothing fails, by "base_change > <test>". P2 counts 8 or 9 per Clicker use: 22 here (the stub's
# Clicker splits on its second use), any number in game. A vetoed Clicker's one assertion: it fires no MC_USE_ITEM.
WANT = {
    f"{SPEC} > ChangePlayerType out of Tainted Lazarus merges the stored twin": "PASS 15 assertions",
    f"{SPEC} > {P2}": "PASS 22 assertions",
    f"{SPEC} > Clicker merges and splits Jacob and Esau holding Inner Eye": "PASS 18 assertions",
    f"{SPEC} > ChangePlayerType into Dead Tainted Lazarus with the twin stored, then Flip": "RECORDED",
    f"{SPEC} > {VETOED[0]}": "PASS 1 assertions",
    f"{SPEC} > {VETOED[1]}": "PASS 1 assertions",
    f"{SPEC} > ChangePlayerType into Tainted Lazarus merges the stored twin, then Flip at once": "RECORDED",
    f"{SPEC} > ChangePlayerType into Dead Tainted Lazarus merges the stored twin, then Esau Jr. at once": "RECORDED",
    **dry.recon(SPEC, "Clicker, then Exit & Continue"),
}


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
