"""Dry checks of specs/item_copies.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
import dry

S1 = "one icon per owned, innate and wisp copy, the oldest lost first"
ZODIAC, BILL = "Zodiac copy is clocked", "3 Dollar Bill copies are clocked"
S2 = "base character change learns the innate copy, clocked copies stay"
NAMES = {"S1": [S1], "S1b": [ZODIAC, BILL], "S2": [S2]}  # each legacy scenario moved here, by its old name: [the names of its tests in this spec]
# each test's verdict under `tags all` when nothing fails, by "item_copies > <test>"; S1b's 37 split 20 + 17
WANT = {
    f"item_copies > {S1}": "PASS 53 assertions",
    f"item_copies > {ZODIAC}": "PASS 20 assertions",
    f"item_copies > {BILL}": "PASS 17 assertions",
    f"item_copies > {S2}": "PASS 29 assertions",
}
# D2: the fresh run is a fixture now, whose setup and done poll take 2 updates before the first look, so it settles 2 updates sooner
ALLOW = [("D2", old, r"SETTLED start after \d+ updates") for old in ("S1", "S2")]


def test_item_copies(path):
    mode = "tags item_copies"
    got = dry.finished(dry.run(path, mode=mode), mode, path)
    dry.expect_results(got, mode, dry.expected(path, mode))
    print("PASS item_copies:", ", ".join(f"{n} {got[n]}" for n in WANT))


TESTS = [test_item_copies]
