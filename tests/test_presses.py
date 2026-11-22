"""The real presses: the Clicker veto, a same-update type change, a Birthright Flip, the Clicker effect, same-seed forms, a press the
engine ignores and a use that spends nothing."""
import dry
from legacy_names import SCENARIOS, DISPUTES, NO_SWAP, ONLY_PICKED, full, expect_parts

WANT = {}  # no spec of its own: it plays every spec
STORED = "spent nothing: stored presser seen with no drop after its use"
# Every old scenario but NO_SWAP swaps, and each swap must FAIL without a spend: a stored presser (Esau Jr., Flip without Birthright) on
# its watched drop, a staying one (Clicker) on its charge, a card on its count.
SPEND_SEEN = {"probes": STORED, "test3": STORED, "birthright": STORED, "P3": STORED, "P4a": STORED, "P4c": STORED, "S4": STORED,
              "P1": "spent nothing: card count", "P2": "spent nothing: charge", "S3": STORED, "r1": STORED, "r1 mirror": STORED,
              "continue": STORED, "continue settled": STORED, "final A two Esau Jr. copies": STORED, "final B Esau Jr. dropped and picked up": STORED,
              "final C Tainted Lazarus Esau Jr.": STORED, "final E Soul of Jacob and Esau": "spent nothing: card count", "final F Flip partners": STORED,
              "final G Jacob and Esau Clicker split": "spent nothing: charge"}


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
    effect = full("obsx form uses Clicker effect")
    assert any(f"{effect} UseActiveItem Clicker type 29 -> 35 changed true primary 703 -> 703" in s for s in log)
    assert any(f"{effect} MC_USE_ITEM " in s and s.endswith("slot -1 charge n/a") for s in log)
    # each copy keeps the character it last swapped out (console 2026-11-22): after a D6 the fresh copy makes a new form first; as in obsx
    # runs 2-6, where the original's fresh copy brought a form on its first form's seed (B present true)
    expected = {"obsx original loses Esau Jr.": ["false", "true"], "obsx form uses Clicker effect": ["true", "false"]}
    for name in DISPUTES[-4:]:
        history = [s for s in log if s.startswith(f"PROBE INFO {full(name)} press #") and " A seed " in s]
        assert [s.rsplit(" ", 1)[1] for s in history] == expected.get(name, ["false", "false"]), history
    b_returns = [s for s in log if s.startswith(f"PROBE INFO {full('obsx original loses Esau Jr.')} press #") and " B seed " in s]
    assert [s.rsplit(" ", 1)[1] for s in b_returns] == ["true", "false"], b_returns
    print("PASS tags obsx, re-armed veto, same-update change, Birthright Flip, and controls")


def test_clicker_effect_ignored(path):
    log = dry.run(path, mode="tags obsx", ignoreClickerEffect=True)
    dry.finished(log, "Clicker effect does nothing", path)
    prefix = f"PROBE INFO {full('obsx form uses Clicker effect')} "
    assert any(s.startswith(prefix + "UseActiveItem Clicker type 29 -> 29 changed false") for s in log)
    assert not any(s.startswith(prefix + "press #") for s in log)
    print("PASS an unchanged Clicker effect stops its test")


def test_same_seed(path):
    # obsy b run 1: after a Continue, Esau Jr. made a new entity with the presser's seed and type, its items re-rolled
    name = full("obsy b continue after B loses Esau Jr.")
    log = dry.run(path, mode="tags continue-b-loses", jrSameSeed=True)
    got = dry.finished(log, "Esau Jr. keeps the seed", path)
    assert got[name] == dry.want()[name], got[name]
    same = [s for s in log if s.startswith(f"PROBE INFO {name} Esau Jr. #") and " new form, same seed " in s]
    assert len(same) == 4 and " items 4:1/1 703:1/1 -> 53:1/1 703:1/1, INPUT_ACTION charge+battery 1 -> 0" in same[0], same
    assert not any(s.startswith(f"PROBE INFO {name} ") and "never happened" in s for s in log)
    print("PASS a press that keeps the seed is logged as data:", same[0])
    # Only press #1 keeps the seed: its TIMING watch is dropped, not woken by #2's new seed under #1's label
    name = full("obsy b continue with A stored")
    log = dry.run(path, mode="tags continue-a-stored", jrSameSeed=1)
    got = dry.finished(log, "Esau Jr. #1 keeps the seed", path)
    assert got[name] == dry.want()[name], got[name]
    assert any(s.startswith(f"PROBE INFO {name} Esau Jr. #1 new form, same seed ") for s in log)
    assert any(s.startswith(f"PROBE INFO {name} TIMING Esau Jr. #2 frame ") for s in log)
    assert not any(s.startswith(f"PROBE INFO {name} TIMING Esau Jr. #1 frame ") for s in log), "stale TIMING watch woke"
    print("PASS a same-seed press leaves no TIMING watch behind")


def test_press_ignored(path):
    # probes' first press is Esau Jr., a swap: every test fails on its first press
    log = dry.run(path, ignorePress=True)
    assert any(f"{full('obsx form loses Esau Jr.')} 2 Esau Jr. never happened:" in s for s in log)
    assert not any(s == "PROBE CMD giveitem c105" for s in log)
    expect_parts(dry.finished(log, "press ignored", path), "press ignored", dry.expected(path),
                 {n: ("no new character, arms ", "test limit ") for n in SCENARIOS if n not in NO_SWAP and n not in ONLY_PICKED})
    stuck = [s for s in log if s.startswith("PROBE STUCK ")]
    assert stuck and stuck[0].endswith(" 60"), stuck[:1]
    assert dry.run.saved.startswith(f"tags all\nSTUCK {len(stuck)} ") and " | " in dry.run.saved, dry.run.saved
    print("PASS a stuck wait logs STUCK once and saves it under the tags line:", len(stuck), "stuck,", repr(dry.run.saved))


def test_no_spend(path):
    got = dry.finished(dry.run(path, noSpend=True), "no spend", path)
    expect_parts(got, "no spend", dry.expected(path), {n: SPEND_SEEN[n] for n in SCENARIOS if n not in NO_SWAP and n not in ONLY_PICKED})
    print("PASS no spend fails every swap:", got[full("test3")][:110])


TESTS = [test_obsx, test_clicker_effect_ignored, test_same_seed, test_press_ignored, test_no_spend]
