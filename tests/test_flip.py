"""Dry checks of specs/flip.lua: its recon tests only record."""
import dry

# The stub puts Flip in no slot (where giveitem puts it on these characters is unobserved), so each press test notes that instead.
NOWHERE = "RECORDED; unreached: Flip in neither primary nor pocket: primary {} secondary 0 pocket 0"
WANT = {  # each test's verdict under `tags all` when nothing fails, by "flip > <test>"
    "flip > Isaac given Flip uses it": NOWHERE.format(0),
    "flip > Isaac given Flip uses it beside an item pedestal": NOWHERE.format(0),
    "flip > Isaac Jr. given Flip uses it": NOWHERE.format(703),
    "flip > Jacob given Flip uses it": NOWHERE.format(0),
    "flip > Missing No. with Flip across floors": "RECORDED",
}


def test_flip(path):
    mode = "tags flip"
    got = dry.finished(dry.run(path, mode=mode), mode, path)
    dry.expect_results(got, mode, dry.expected(path, mode))
    print("PASS flip:", ", ".join(f"{n} {got[n]}" for n in WANT))


TESTS = [test_flip]
