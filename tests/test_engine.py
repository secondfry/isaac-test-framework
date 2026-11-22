"""Dry checks of specs/engine.lua: its tests' verdicts and the checks of their own lines."""
import dry

WANT = {  # each test's verdict under `tags all` when nothing fails, by "engine > <test>"
    "engine > MaxCharges reads pre-REP+ charges": "PASS 3 assertions",
    "engine > Esau Jr. takes one press": "PASS 1 assertions",
    "engine > Clicker stays held after a real press": "PASS 1 assertions",
    "engine > a card beside Flip sits in pocket slot 1": "PASS 1 assertions",
    "engine > Flip takes 4 charges and one press": "PASS 4 assertions",
}
MODE = "tags engine"


def test_engine(path):
    log = dry.run(path, mode=MODE)
    dry.expect_results(dry.finished(log, MODE, path), MODE, dry.expected(path, MODE))
    assert not any(s.startswith(f"PROBE SNAP {n} ") for n in WANT for s in log), "SNAP lines in a test without a snapshot"
    print(f"PASS {MODE}: {len(WANT)} tests, no SNAP lines")


TESTS = [test_engine]
