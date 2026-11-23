"""Dry checks of specs/regressions.lua: its tests' verdicts and the checks of their own lines."""
import dry

P4C_2 = "(P4c 2) Flip of the Esau Jr. character"
# Each test's verdict under `tags all` when nothing fails
WANT = {
    "regressions > (P4c 1) Esau Jr. character turned Isaac": "PASS 30 assertions",
    "regressions > (P4c 2) Flip of the Esau Jr. character": "PASS 31 assertions",
    "regressions > (P4c 3) crossing on a flipped one's Esau Jr. character": "PASS 26 assertions",
    "regressions > S3": "PASS 24 assertions",
    "regressions > r1": "PASS 29 assertions",
    "regressions > r1 mirror": "PASS 19 assertions",
}


def test_regressions_lines(path):
    mode = "tags regressions"
    log = dry.run(path, mode=mode)
    dry.expect_results(dry.finished(log, mode, path), mode, dry.expected(path, mode))
    # A press that brings back a character on the presser's seed is the presser's stored drop, not the returned one's charge
    swaps = [s for s in dry.segment(log, f"regressions > {P4C_2}") if s.startswith("PROBE SWAP Flip of the form ")]
    assert swaps and all(" spent stored presser charge, " in s for s in swaps), swaps
    print(f"PASS {mode}: verdicts, the Esau Jr. character's Flip spends its stored drop")


def test_tlaz_roll_29(path):
    # Clicker from the Dead form rolling 29 (run 8): S3's merge assertions with Flip kept, the rest unchanged
    got = dry.finished(dry.run(path, tlazRoll=29), "Clicker rolls 29", path)
    dry.expect_results(got, "Clicker rolls 29", {**dry.expected(path), "regressions > S3": "PASS 21 assertions"}, cut=True)
    print("PASS Clicker rolling 29:", got["regressions > S3"])


TESTS = [test_regressions_lines, test_tlaz_roll_29]
