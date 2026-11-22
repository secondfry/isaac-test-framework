"""Dry checks of specs/hello.lua: its tests' verdicts, played without ReHUD as in a vanilla session."""
import dry

SPEC = "hello"
WANT = {  # each test's verdict under `tags all` when nothing fails, by "hello > <test>"
    f"{SPEC} > fresh Isaac on a fixed seed": "RECORDED",
    f"{SPEC} > Clicker on Isaac": "PASS 3 assertions",
    f"{SPEC} > fresh run on a fixed seed": "RECORDED",
}
MODE = "tags vanilla"


def test_hello_vanilla(path):
    log = dry.run(path, mode=MODE, ReHUD=None)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    assert not any("ReHUD.dbg missing" in s for s in log), "a vanilla test read ReHUD"
    assert f"PROBE SNAP {SPEC} > Clicker on Isaac | Clicker roll / type = 19" in log, "no Clicker roll snapshot"
    recon = dry.segment(log, f"{SPEC} > fresh run on a fixed seed")
    # the stub's seed command restarts on its seed (session 1), and every fixture starts on the fixed one
    assert sum(" seed command: game start after 1 updates, continued false" in s for s in recon) == 2, recon
    assert all(" start seed 9SZM 3P3S " in s for s in recon if " SEEDS after " in s), recon
    assert sum(" SEEDS after " in s for s in recon) == 5 and not any(s.startswith("PROBE ASSERT") for s in recon)
    seeded = [s for s in log if s.startswith("PROBE INFO ") and " start seed " in s and " SEEDS " not in s]
    assert seeded and all(s.endswith(" start seed 9SZM 3P3S") for s in seeded), seeded
    assert sum(s == "PROBE CMD seed 9SZM 3P3S" for s in log) == 1 + 2, "the first fixture's seed command, then only the recon test's two"
    trace = [s for s in recon if s.startswith("PROBE TRACE ")]
    assert trace and not any(": ROSTER " in s or ": ENTRY " in s for s in trace), "the trace read ReHUD"
    print(f"PASS {MODE} without ReHUD: Clicker roll snapshot, seed command logged twice")


TESTS = [test_hello_vanilla]
