"""Dry checks of specs/item_copies.lua: its tests' verdicts."""
import dry

S1 = "one icon per owned, innate and wisp copy, the oldest lost first"
ZODIAC, BILL = "Zodiac copy is clocked", "3 Dollar Bill copies are clocked"
S2 = "base character change learns the innate copy, clocked copies stay"
# each test's verdict under `tags all` when nothing fails, by "item_copies > <test>"
WANT = {
    f"item_copies > {S1}": "PASS 53 assertions",
    f"item_copies > {ZODIAC}": "PASS 20 assertions",
    f"item_copies > {BILL}": "PASS 17 assertions",
    f"item_copies > {S2}": "PASS 29 assertions",
}


def test_item_copies(path):
    mode = "tags item_copies"
    got = dry.finished(dry.run(path, mode=mode), mode, path)
    dry.expect_results(got, mode, dry.expected(path, mode))
    print("PASS item_copies:", ", ".join(f"{n} {got[n]}" for n in WANT))


TESTS = [test_item_copies]
