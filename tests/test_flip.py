"""Dry checks of specs/flip.lua: its recon tests only record."""
import dry

WANT = {f"flip > {n}": "RECORDED" for n in (  # each test's verdict under `tags all` when nothing fails
    "Isaac given Flip uses it", "Isaac given Flip uses it beside an item pedestal", "Isaac Jr. given Flip uses it",
    "Jacob given Flip uses it", "Missing No. with Flip across floors")}


def test_flip(path):
    mode = "tags flip"
    got = dry.finished(dry.run(path, mode=mode), mode, path)
    dry.expect_results(got, mode, dry.expected(path, mode))
    print("PASS flip:", ", ".join(f"{n} {got[n]}" for n in WANT))


TESTS = [test_flip]
