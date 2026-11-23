"""Dry checks of specs/revive.lua: one recon test per revive source, each dying until its own source has revived Lazarus once; each
ends at its source's revive, and a source that gives no revive reaches game over, whose death certificate waits for Space (session 3a). The stub revives in the order session 2 saw with every source held (players.lua shortcut)."""
import dry

# Each source's type after each death in the stub: Lazarus's own revive comes first, so a held item revives at the second.
DEATHS = {"Soul of Lazarus": ["8"], "his own revive only": ["11"], "Lazarus' Rags": ["11", "11"], "Ankh": ["11", "4"], "Judas' Shadow": ["11", "12"],
          "Missing Poster": ["11", "10"]}
NAMES = {source: f"revive > Lazarus with {source} dies until it revives him" for source in DEATHS}
CERT = "revive > restart from the death certificate"
POSTER = NAMES["Missing Poster"]
WANT = {**{name: "RECORDED" for name in NAMES.values()}, CERT: "RECORDED"}
MODE = "tags revive"
POSTER_KEPT = "Missing Poster gave no revive, Poster kept: The Lost likely locked"


def test_revive(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    for source, types in DEATHS.items():
        name = NAMES[source]
        lines = dry.segment(log, name)
        assert f"PROBE INFO {name} REVIVE ends: source used by death {len(types)} | " in "\n".join(lines), (name, lines)
        assert any(s.startswith(f"PROBE INFO {name} restart 8 start seed ") for s in lines), f"{name}: its fixture did not restart"
        assert not any(s.startswith("PROBE ASSERT") or f"death {len(types) + 1} " in s or " CERT " in s for s in lines), name
        for n, t in enumerate(types, 1):
            for want in (f"type = {t}", "hash kept = true", "alive after 240 updates = true"):
                assert f"PROBE SNAP {name} | death {n} / {want}" in lines, (name, n, want)
    assert f"PROBE SNAP {POSTER} | death 2 / sources = c161 0 c311 0 c332 0 card 89 0 trinket 23 false" in dry.segment(log, POSTER)
    print(f"PASS {MODE}: {len(NAMES)} tests die until their own source revives Lazarus, none to game over")
    # the stub keeps updating on the certificate (players.lua shortcut), so the restart goes out after 120 updates dead
    lines = dry.segment(log, CERT)
    for want in ("CERT at update dead for 30 updates, 30 renders, frame ", "CERT at restart dead for 120 updates, 120 renders, frame ",
                 "restart from the certificate: new game after "):
        assert any(s.startswith(f"PROBE INFO {CERT} {want}") for s in lines), (want, lines)
    assert any(s.endswith("IsDead true") for s in lines) and not any("press Space" in s for s in lines), lines
    print(f"PASS {MODE}: Isaac's restart from the death certificate starts a new game")


def test_poster_locked(path):
    # Missing Poster gives no revive and stays held: the test restarts from the certificate itself and ends SKIP at the new game
    log = dry.run(path, mode=MODE, posterLocked=True)
    want = {**dry.expected(path, MODE), POSTER: f"SKIP {POSTER_KEPT}"}
    dry.expect_results(dry.finished(log, MODE, path), MODE, want)
    lines = dry.segment(log, POSTER)
    for want in (f"{POSTER_KEPT} | death 2", "CERT at restart dead for 120 updates, ","restart from the certificate: new game after "):
        assert any(s.startswith(f"PROBE INFO {POSTER} {want}") for s in lines), (want, lines)
    assert f"PROBE SNAP {POSTER} | death 2 / sources = c161 0 c311 0 c332 0 card 89 0 trinket 23 true" in lines, lines
    assert f"PROBE SNAP {POSTER} | death 1 / type = 11" in lines and not any("unexpected game start" in s for s in log), lines
    print(f"PASS {MODE}: a Missing Poster kept through a game over ends SKIP after the harness's own restart")


TESTS = [test_revive, test_poster_locked]
