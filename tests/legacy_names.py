"""HEAD df8ba84's scenarios by their old names, the groups of them that test_presses, test_invariants and same_behaviour.py state facts
about, and where each scenario went. Frozen through S4: a spec's module registers where its scenarios went in its own NAMES
(test_<spec>.py), never here. Temporary: goes once those facts name the specs' tests (plan S4's last merge or S6)."""
import functools

import dry

SPEC = "legacy"  # a scenario no module claims still plays from specs/legacy.lua under its old name
OBS = ["obs esaujr cross", "obs esaujr out", "obs esaujr flip", "obs esaujr flipped cross", "obs esaujr birthright", "obs esaujr clicker", "obs mirror",
       "obs esaujr birthright keep", "obs esaujr cross35", "obs esaujr dead seed", "obs esaujr birthright flip"]
DISPUTES = [
    "obsx cancelled Clicker", "obsx cancelled Clicker then change", "obsx Clicker on returned original",
    "obsx Clicker after Flip", "obsx Clicker with Birthright", "obsx Isaac Esau Jr Clicker",
    "obsx merge 38 to 29 then Flip", "obsx merge 29 to 38 then Esau Jr.",
    "obsx form loses Esau Jr.", "obsx form uses Clicker effect", "obsx Isaac form loses Esau Jr.", "obsx original loses Esau Jr.",
]
OBSY_A = ["obsy a schoolbag", "obsy a schoolbag Clicker", "obsy a Dead form after A lost", "obsy a Isaac Clicker effect",
          "obsy a J&E by Jacob", "obsy a J&E by Esau", "obsy a Forgotten and Soul", "obsy a Tainted Forgotten", "obsy a Lazarus Risen"]
OBSY_B = ["obsy b Tainted Jacob", "obsy b Eden", "obsy b continue with A stored", "obsy b continue after B loses Esau Jr.", "obsy b identity"]
OBSY_LARGE = ["obsy b continue with A stored", "obsy b continue after B loses Esau Jr.", "obsy b identity"]  # exit-continue, not new
OBSY = OBSY_A + OBSY_B
OBS += DISPUTES + OBSY
FINAL = ["final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up", "final C Tainted Lazarus Esau Jr.", "final D Strawman",
         "final E Soul of Jacob and Esau", "final F Flip partners", "final G Jacob and Esau Clicker split"]
ONLY_PICKED = {"final F Flip partners", "final G Jacob and Esau Clicker split"}  # opt-in
FINAL_OBS = ["final I Birthright twins Esau Jr.", "final K tag through Flip", "final L flipped cross", "final M original loses Esau Jr.",
             "final J Strawman Keeper leaves", "final N summoned Esau across Continue"]  # recon tests
FINAL_MODE = "tags rehud-2.8"
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "P4c", *OBS, "S4", "P1", "P2", "S1", "S1b", "S2", "S3", "r1", "r1 mirror",
             *FINAL, *FINAL_OBS, "continue", "continue settled", "L1"]  # HEAD's play order
NO_SWAP = {"S1", "S1b", "S2", "L1", "final D Strawman", *OBS, *FINAL_OBS}  # an obs press that never swaps is data, not a fail
LOOKED = [n for n in SCENARIOS if n != "probes" and n not in OBS and n not in FINAL_OBS]  # every scenario with a look: the invariants run there


@functools.lru_cache(maxsize=None)
def names():
    """{old scenario: [its tests, "<spec> > <test>"]}: each module's NAMES ({old: [test names in that spec]}), else its legacy test."""
    claimed = {}
    for m in dry.modules():
        spec = m.__name__[len("test_"):]
        for old, news in getattr(m, "NAMES", {}).items():
            assert old in SCENARIOS, f"{m.__name__}: no old scenario {old!r}"
            claimed.setdefault(old, []).extend(f"{spec} > {n}" for n in news)
    return {old: claimed.get(old, [f"{SPEC} > {old}"]) for old in SCENARIOS}


def full(old):
    """The one test old scenario `old` became."""
    parts = names()[old]
    assert len(parts) == 1, f"{old} split into {parts}"
    return parts[0]


def hit(got, why):
    """The old scenarios, in HEAD's order, one of whose tests FAILs naming `why`."""
    return [old for old, parts in names().items() if any(dry.fails(got[n], why) for n in parts)]


def expect_parts(got, label, want, whys):
    """Each test of an old scenario in `whys` ({old: why or a tuple}) ends as `want` says or FAILs naming that why, and one of them at
    least FAILs so (a split scenario's other parts may not reach the cause); every other test in `want` ends as it says."""
    parts = names()
    why_of = {n: why for old, why in whys.items() for n in parts[old]}
    for name, verdict in want.items():
        assert got[name] == verdict or (name in why_of and dry.fails(got[name], why_of[name])), f"{label}: {name}: {got[name]}"
    for old, why in whys.items():
        assert any(dry.fails(got[n], why) for n in parts[old]), f"{label}: no test of {old} FAILs naming {why}: {[got[n] for n in parts[old]]}"
