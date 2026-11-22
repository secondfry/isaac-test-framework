"""Dry checks of specs/revive.lua: the recon test's verdict and its death lines. The stub's Kill() removes the player with no revive
(shortcut), so the dry run ends after the first death."""
import dry

TEST = "revive > Lazarus with every revive dies until none is left"
WANT = {TEST: "RECORDED"}
MODE = "tags revive"


def test_revive(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    lines = dry.segment(log, TEST)
    held = "| c161 1 c311 1 c332 1 trinket 23 true card 89 1 | Kill() "
    assert any(f"INFO {TEST} REVIVE death 1 Kill() on type 8 " in s and held in s for s in lines), "Lazarus did not die holding every source"
    assert f"PROBE INFO {TEST} REVIVE ends: death 1 left no live player 0" in lines
    assert f"PROBE SNAP {TEST} | death 1 / type = no player 0" in lines and not any(s.startswith("PROBE ASSERT") for s in lines)
    print(f"PASS {MODE}: Lazarus dies holding every source, the death is logged and snapshotted")


TESTS = [test_revive]
