"""Dry checks of specs/revive.lua: one recon test per revive source, each dying until its game over, and the next test restarting
from the game the stub starts. The stub revives in the order session 2 saw with every source held (players.lua shortcut)."""
import dry

SOURCES = ("Soul of Lazarus", "his own revive only", "Lazarus' Rags", "Ankh", "Judas' Shadow", "Missing Poster")
NAMES = [f"revive > Lazarus with {s} dies until game over" for s in SOURCES]
WANT = {name: "RECORDED" for name in NAMES}
MODE = "tags revive"
# Each death's SNAP lines in the stub: a type after a revive, game over at the last death.
DEATHS = {
    "Soul of Lazarus": ["8", "11", None],
    "Ankh": ["11", "4", None],
}


def test_revive(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    assert not any("unexpected game start" in s for s in log), "a game over's new game was not expected"
    for name in NAMES:
        lines = dry.segment(log, name)
        assert any(s.startswith(f"PROBE INFO {name} REVIVE ends: death ") and " game over, new game type " in s for s in lines), name
        assert any(s.startswith(f"PROBE INFO {name} restart 8 start seed ") for s in lines), f"{name}: its fixture did not restart"
        assert not any(s.startswith("PROBE ASSERT") for s in lines), name
    for source, deaths in DEATHS.items():
        name = f"revive > Lazarus with {source} dies until game over"
        for n, t in enumerate(deaths, 1):
            want = f"PROBE SNAP {name} | death {n} / " + (f"type = {t}" if t else "game over = true")
            assert want in log, want
    print(f"PASS {MODE}: {len(NAMES)} tests die until game over, each next one restarts")


TESTS = [test_revive]
