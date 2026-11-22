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
    # the stub's seed command does nothing (shortcut), so each waits out its 50 updates
    assert sum(" seed command: no game start in 50 updates" in s for s in recon) == 2, recon
    assert sum(" SEEDS after " in s for s in recon) == 5 and not any(s.startswith("PROBE ASSERT") for s in recon)
    trace = [s for s in recon if s.startswith("PROBE TRACE ")]
    assert trace and not any(": ROSTER " in s or ": ENTRY " in s for s in trace), "the trace read ReHUD"
    print(f"PASS {MODE} without ReHUD: Clicker roll snapshot, seed command logged twice")


TESTS = [test_hello_vanilla]
