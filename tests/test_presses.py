"""The real presses: the Clicker veto, a same-update type change, a Birthright Flip, the Clicker effect, a press the engine ignores and
a use that spends nothing."""
import dry

WANT = {}  # no spec of its own: it plays every spec
# The checked tests (not opt-in) that never swap; every other one swaps, and each swap must FAIL without a spend: a stored presser
# (Esau Jr., Flip without Birthright) on its watched drop, a staying one (Clicker) on its charge, a card on its count.
NO_SWAP = {"engine > MaxCharges reads pre-REP+ charges", "engine > a card beside Flip sits in pocket slot 1",
           "characters > Strawman's Keeper is a character with his own items", "continue > item copies survive Exit & Continue"}
CHARGE = {"hello > Clicker on Isaac", "engine > Clicker stays held after a real press", "base_change > Clicker on Jacob and Esau until they split"}
CARD = {"characters > temporary Esau from Soul of Jacob and Esau keeps his own items", "characters > temporary Esau has a number until he leaves"}
EFFECT = "esau_jr > Tainted Lazarus's Esau Jr. character uses Clicker's effect"
VETOED = ["base_change > a cancelled Clicker on the Esau Jr. character", "base_change > a cancelled Clicker, then ChangePlayerType in the same update"]


def swapping(path):
    """The checked tests a press swaps in, every one but the opt-in ones, NO_SWAP and item_copies (no press there)."""
    return [t.name for t in dry.plan(path) if not t.snapshot and "opt-in" not in t.tags and t.name not in NO_SWAP
            and not t.name.startswith("item_copies > ")]


def spend_why(name):
    return "spent nothing: charge" if name in CHARGE else "spent nothing: card count" if name in CARD else \
        "spent nothing: stored presser seen with no drop after its use"


def test_obsx(path):
    log = dry.run(path, mode="tags obsx", ignoreFirstVetoPress=True, birthrightDeadFirst=True)
    dry.expect_results(dry.finished(log, "tags obsx", path), "tags obsx", dry.expected(path, "tags obsx"))
    cancelled = [s for s in log if " cancelled Clicker update " in s]
    assert len(cancelled) == 2, cancelled
    for s in cancelled:
        before, after = s.split(" type ")[1].split(" charge ")[0].split(" -> ")
        assert before == after and s.endswith("charge 6 -> 0 MC_PRE_USE_ITEM calls 1 MC_USE_ITEM calls 0"), s
    crossed = [s for s in log if "same-update ChangePlayerType update " in s]
    assert len(crossed) == 1, crossed
    assert crossed[0].endswith("type 35"), crossed
    assert crossed[0].rsplit(" update ", 1)[1].split()[0] == cancelled[1].rsplit(" update ", 1)[1].split()[0], (crossed, cancelled)
    assert any(s.startswith("PROBE SWAP put type 29 in player 0 ") for s in log), "conditional Birthright Flip did not complete"
    assert any(f"{EFFECT} UseActiveItem Clicker type 29 -> 35 changed true primary 703 -> 703" in s for s in log)
    assert any(f"{EFFECT} MC_USE_ITEM " in s and s.endswith("slot -1 charge n/a") for s in log)
    # each copy keeps the character it last swapped out (console 2026-11-22): after a D6 the fresh copy makes a new form first; as in obsx
    # runs 2-6, where the original's fresh copy brought a form on its first form's seed (B present true); A present per press
    original = "esau_jr > Tainted Lazarus loses Esau Jr. after a round trip, returns recorded"
    expected = {"esau_jr > Tainted Lazarus's Esau Jr. character loses Esau Jr. and gets it back": ["false", "false"], EFFECT: ["true", "false"],
                "esau_jr > Isaac's Esau Jr. character loses Esau Jr. and gets it back": ["false", "false"], original: ["false", "true"]}
    for name, want in expected.items():
        history = [s for s in log if s.startswith(f"PROBE INFO {name} press #") and " A seed " in s]
        assert [s.rsplit(" ", 1)[1] for s in history] == want, history
    b_returns = [s for s in log if s.startswith(f"PROBE INFO {original} press #") and " B seed " in s]
    assert [s.rsplit(" ", 1)[1] for s in b_returns] == ["true", "false"], b_returns
    print("PASS tags obsx, re-armed veto, same-update change, Birthright Flip, and controls")


def test_clicker_effect_ignored(path):
    log = dry.run(path, mode="tags obsx", ignoreClickerEffect=True)
    dry.finished(log, "Clicker effect does nothing", path)
    prefix = f"PROBE INFO {EFFECT} "
    assert any(s.startswith(prefix + "UseActiveItem Clicker type 29 -> 29 changed false") for s in log)
    assert not any(s.startswith(prefix + "press #") for s in log)
    print("PASS an unchanged Clicker effect stops its test")


def unswapped(path):
    """The verdicts when no swap completes: a snapshot test whose assertion follows its first press only records."""
    return {**dry.expected(path), **{n: "RECORDED" for n in VETOED}}


def test_press_ignored(path):
    # every swapping test fails on its first press
    log = dry.run(path, ignorePress=True)
    assert any("esau_jr > Tainted Lazarus's Esau Jr. character loses Esau Jr. and gets it back 2 Esau Jr. never happened:" in s for s in log)
    assert not any(s == "PROBE CMD giveitem c105" for s in log)
    got = dry.finished(log, "press ignored", path)
    dry.expect_results(got, "press ignored", unswapped(path), ("no new character, arms ", "test limit "), swapping(path), cut=True)
    stuck = [s for s in log if s.startswith("PROBE STUCK ")]
    assert stuck and stuck[0].endswith(" 60"), stuck[:1]
    assert dry.run.saved.startswith(f"tags all\nSTUCK {len(stuck)} ") and " | " in dry.run.saved, dry.run.saved
    print("PASS a stuck wait logs STUCK once and saves it under the tags line:", len(stuck), "stuck,", repr(dry.run.saved))


def test_no_spend(path):
    got = dry.finished(dry.run(path, noSpend=True), "no spend", path)
    swaps = swapping(path)
    for name, verdict in unswapped(path).items():
        assert dry.fails(got[name], spend_why(name)) if name in swaps else dry.reached(got[name]) == dry.reached(verdict), f"no spend: {name}: {got[name]}"
    print("PASS no spend fails every swap:", got[swaps[0]][:110])


TESTS = [test_obsx, test_clicker_effect_ignored, test_press_ignored, test_no_spend]
