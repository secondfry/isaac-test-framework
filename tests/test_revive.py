"""Dry checks of specs/revive.lua: one recon test per revive source, each dying until its own source has revived Lazarus once, never
to game over. The stub revives in the order session 2 saw with every source held (players.lua shortcut)."""
import dry

# Each source's type after each death in the stub: Lazarus's own revive comes first, so a held item revives at the second.
DEATHS = {"Soul of Lazarus": ["8"], "his own revive only": ["11"], "Lazarus' Rags": ["11", "11"], "Ankh": ["11", "4"], "Judas' Shadow": ["11", "12"]}
NAMES = {source: f"revive > Lazarus with {source} dies until it revives him" for source in DEATHS}
WANT = {name: "RECORDED" for name in NAMES.values()}
MODE = "tags revive"


def test_revive(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    for source, types in DEATHS.items():
        name = NAMES[source]
        lines = dry.segment(log, name)
        assert f"PROBE INFO {name} REVIVE ends: source used by death {len(types)} | " in "\n".join(lines), (name, lines)
        assert any(s.startswith(f"PROBE INFO {name} restart 8 start seed ") for s in lines), f"{name}: its fixture did not restart"
        assert not any(s.startswith("PROBE ASSERT") or f"death {len(types) + 1} " in s for s in lines), name
        for n, t in enumerate(types, 1):
            for want in (f"type = {t}", "hash kept = true", f"alive after 240 updates = true"):
                assert f"PROBE SNAP {name} | death {n} / {want}" in lines, (name, n, want)
    print(f"PASS {MODE}: {len(NAMES)} tests die until their own source revives Lazarus, none to game over")


TESTS = [test_revive]
