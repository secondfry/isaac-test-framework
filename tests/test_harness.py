"""Dry run of main.lua against the stub in tests/stub/. Run: python -B -I tests/test_harness.py main.lua [test ...] (venv with lupa); no test names runs
them all, in order."""
import os
import sys
from lupa.lua53 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
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
OBSY_LARGE = {"obsy b continue with A stored", "obsy b continue after B loses Esau Jr.", "obsy b identity"}  # kind "large", not new
FINAL_LARGE = {"final N summoned Esau across Continue"}
OBSY = OBSY_A + OBSY_B
OBS += DISPUTES + OBSY
FINAL = ["final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up", "final C Tainted Lazarus Esau Jr.", "final D Strawman",
         "final E Soul of Jacob and Esau", "final F Flip partners", "final G Jacob and Esau Clicker split"]
ONLY_PICKED = {"final F Flip partners", "final G Jacob and Esau Clicker split"}  # mirrors main.lua's onlyPicked flags
FINAL_OBS = ["final I Birthright twins Esau Jr.", "final K tag through Flip", "final L flipped cross", "final M original loses Esau Jr.",
             "final J Strawman Keeper leaves", "final N summoned Esau across Continue"]  # INFO only
FINAL_MODE = "only final,S3,r1,P4c"
FINAL_RUN = ["P4c", "S3", "r1", "r1 mirror", *FINAL, *FINAL_OBS]
SCENARIOS = ["probes", "test3", "birthright", "P3", "P4a", "P4c", *OBS, "S4", "P1", "P2", "S1", "S1b", "S2", "S3", "r1", "r1 mirror",
             *FINAL, *FINAL_OBS, "continue", "continue settled", "L1"]
NO_SWAP = {"S1", "S1b", "S2", "L1", "final D Strawman", *OBS, *FINAL_OBS}  # an obs press that never swaps is INFO, not a fail
NEW = {"continue", "continue settled", "L1"}  # mirrors main.lua's new = true flags
LARGE = NEW | OBSY_LARGE | FINAL_LARGE
# Scenario ceilings in updates (main.lua budget, obsScenario budget); the final mode's worst case is their sum.
BUDGET = {"P4c": 600, "S3": 200, "r1": 250, "r1 mirror": 200, "final A two Esau Jr. copies": 350, "final B Esau Jr. dropped and picked up": 1100,
          "final C Tainted Lazarus Esau Jr.": 350, "final D Strawman": 200, "final E Soul of Jacob and Esau": 350, "final F Flip partners": 450,
          "final G Jacob and Esau Clicker split": 750, **{n: 1000 if n in FINAL_LARGE else 445 for n in FINAL_OBS}}
# Exact verdicts: a lost check or note shows. Each look adds 5 invariant checks (a lookC 6). P2 counts 8 or 9 checks per Clicker use: 22 here
# (the stub's Clicker splits on its second use), any number in game.
WANT = {
    "probes": "PASS 10 checks",
    "test3": "PASS 15 checks",
    "birthright": "PASS 36 checks",
    "P3": "PASS 30 checks",
    "P4a": "PASS 18 checks",
    "P4c": "PASS 87 checks",
    "S4": "PASS 29 checks",
    "P1": "PASS 25 checks",
    "P2": "PASS 22 checks",
    "continue": "PASS 14 checks",
    "continue settled": "PASS 20 checks",
    "S1": "PASS 53 checks",
    "S1b": "PASS 37 checks",
    "S2": "PASS 29 checks",
    "S3": "PASS 24 checks",
    "r1": "PASS 27 checks",
    "r1 mirror": "PASS 18 checks",
    "L1": "PASS 30 checks",
    "final A two Esau Jr. copies": "PASS 46 checks",
    "final B Esau Jr. dropped and picked up": "PASS 25 checks",
    "final C Tainted Lazarus Esau Jr.": "PASS 39 checks",
    "final D Strawman": "PASS 22 checks",
    "final E Soul of Jacob and Esau": "PASS 15 checks",
    "final F Flip partners": "PASS 47 checks",
    "final G Jacob and Esau Clicker split": "PASS 18 checks",
    **{n: "INFO data only" for n in OBS + FINAL_OBS},
}
LOOKED = [n for n in SCENARIOS if n != "probes" and n not in OBS and n not in FINAL_OBS]  # every scenario with a look: the invariants run there
# Every scenario but NO_SWAP swaps, and each swap must FAIL without a spend: a stored presser (Esau Jr., Flip without Birthright) on its watched
# drop, a staying one (Clicker) on its charge, a card on its count.
STORED = "spent nothing: stored presser seen with no drop after its use"
SPEND_SEEN = {"probes": STORED, "test3": STORED, "birthright": STORED, "P3": STORED, "P4a": STORED, "P4c": STORED, "S4": STORED,
              "P1": "spent nothing: card count", "P2": "spent nothing: charge", "S3": STORED, "r1": STORED, "r1 mirror": STORED,
              "continue": STORED, "continue settled": STORED, "final A two Esau Jr. copies": STORED, "final B Esau Jr. dropped and picked up": STORED,
              "final C Tainted Lazarus Esau Jr.": STORED, "final E Soul of Jacob and Esau": "spent nothing: card count", "final F Flip partners": STORED,
              "final G Jacob and Esau Clicker split": "spent nothing: charge"}
ASK = "ACTION exit to the menu and Continue now by type"
FINAL_C4 = ["final A two Esau Jr. copies", "final B Esau Jr. dropped and picked up", "final C Tainted Lazarus Esau Jr.", "final D Strawman",
            "final E Soul of Jacob and Esau"]  # F and G run only when picked by only; G holds no c4
HOLDS_C4 = ["test3", "birthright", "P3", "P4a", "P4c", "S4", "P1", "P2", "S1", "S3", "r1", "r1 mirror", *FINAL_C4, "continue", "continue settled", "L1"]
CHECKED_FINAL = [n for n in FINAL_RUN if n not in FINAL_OBS]
# Each invariant's negative stub mode: (stub flag, run mode, the invariant's message, the scenarios it must fail on; the rest may fail on
# their own checks).
INVARIANT_MODES = [
    ("missCopy", "regression", "invariant engine counts: c4 of ", HOLDS_C4),
    ("dupCopy", "regression", "invariant duplicates: c4 of ", HOLDS_C4),
    ("keepStored", "regression", "invariant phantom stored forms: ", ["test3", "S3", "continue", "continue settled"]),
    ("leaveNotMerge", "regression", "invariant left entries: ", ["test3", "P4c", "P2", "S3", "r1", "r1 mirror", "continue", "continue settled"]),
    # P2 and S3 list nothing after their last stage, so a next-floor name is still one they reached; S4's Esau Jr. form (holding c703) and
    # P1's summoned Esau do
    ("laterFloor", "regression", "invariant floors: ", ["test3", "birthright", "P3", "P4a", "P4c", "S4", "P1", "S1", "S1b", "S2", "r1", "r1 mirror",
                                                         *(n for n in FINAL if n not in ONLY_PICKED), "continue", "continue settled", "L1"]),
    # LJ and D share a seed: keyed by seed alone they share a row
    ("untagged", FINAL_MODE, "invariant characters: ", ["final C Tainted Lazarus Esau Jr.", "final F Flip partners"]),
    ("phantomRow", FINAL_MODE, "invariant characters: ", FINAL),
    # ReHUD's own esauJr flag exempts no row: only a character the harness saw Esau Jr. store
    ("phantomRow", "regression", "invariant phantom stored forms: ", [n for n in LOOKED if n not in ONLY_PICKED]),
]
PEDESTAL = {"yum-heart": 45, "Esau Jr.": 703}  # the fake user's target, by the YOU: line's wording
STUB_FILES = ["api.lua", "players.lua", "characters.lua", "input.lua", "console.lua", "rehud.lua"]  # load order: rehud.lua registers its update first


def load(lua, path):
    """The stub, the game's include() over the mod folder (each call runs the file again), then the mod's main.lua at `path`."""
    for name in STUB_FILES:
        with open(os.path.join(HERE, "stub", name), encoding="utf-8") as f:
            lua.execute(f.read())
    root = os.path.dirname(os.path.abspath(path)).replace("\\", "/") + "/"
    lua.execute("local root = ... function include(name) return dofile(root .. name:gsub('%.', '/') .. '.lua') end", root)
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())


def run(path, mode="regression", on_exit="continue", render_every=1, continue_after=0, loader=load, **flags):
    """Plays the whole suite; on_exit is what the fake user does when asked to exit and Continue: "continue" or "new"; continue_after
    delays that answer by this many updates. A YOU: line is answered by walking player 0 onto the pedestal it names. `loader(lua, path)`
    loads the stub and the mod."""
    lua = LuaRuntime()
    assert lua.eval("_VERSION") == "Lua 5.3", lua.eval("_VERSION")
    loader(lua, path)
    g = lua.globals()
    g.modData = mode
    for k, v in flags.items():
        g[k] = v
    g.startRun(3, False)
    seen, late = 0, []
    for update in range(1, 200001):
        if g.pendingStart is not None:
            t = g.pendingStart
            g.pendingStart = None
            g.startRun(t, False)
        ask = g.HARNESS.ask
        if ask and ask.startswith("YOU:"):
            g.fakeUserWalk(next(id for word, id in PEDESTAL.items() if word in ask))
        g.engineInput()
        g.fire(1)
        if update % render_every == 0:
            g.fire(2)
        log = g.LOG
        size = len(log)
        if any(ASK in log[i] for i in range(seen + 1, size + 1)):
            late.append(update + continue_after)
        while late and late[0] <= update:
            late.pop(0)
            g.startRun(0, on_exit == "continue")
        seen = size
        if log[size] == "PROBE HARNESS DONE":
            break
    run.saved, run.updates = g.SAVED, update
    return list(g.LOG.values())


def results(log):
    out = {}
    for s in log:
        if s.startswith("PROBE RESULT "):
            rest = s[len("PROBE RESULT "):]
            name = next(n for n in sorted(SCENARIOS, key=len, reverse=True) if rest.startswith(n + " "))
            assert name not in out, f"two RESULTs for {name}"
            out[name] = rest[len(name) + 1:]
    return out


def check_finished(log, label):
    assert log[-1] == "PROBE HARNESS DONE", f"{label}: run did not finish"
    assert not any("HARNESS ERROR" in s for s in log), f"{label}: harness error"
    got = results(log)
    assert list(got) == SCENARIOS, f"{label}: RESULTs {list(got)}"
    return got


def wanted(mode):
    """Each scenario's verdict in `mode` when nothing fails: WANT, or the SKIP that mode logs."""
    line = mode.splitlines()[0].strip() if mode else ""
    only = line[5:] if line.startswith("only ") else None
    label = "regression" if line == "regression" else f"only {only}" if only else "default"
    out = {}
    for n in SCENARIOS:
        if only is not None:
            out[n] = WANT[n] if any(n.startswith(p) for p in only.split(",")) else f"SKIP not {only} ({label} mode)"
        elif n in ONLY_PICKED:
            out[n] = f"SKIP run only when picked by only ({label} mode)"
        elif n in LARGE and n not in NEW and label != "regression":
            out[n] = f"SKIP large and not new ({label} mode)"
        else:
            out[n] = WANT[n]
    return out


def expect_results(got, label, mode="regression", why=None, names=(), want=None):
    """Every scenario in `names` FAILs naming `why` (or one of a tuple); the rest end as `want` (default: wanted(mode))."""
    want = want or wanted(mode)
    for name in SCENARIOS:
        if name in names:
            assert got[name].startswith("FAIL") and any(w in got[name] for w in (why if isinstance(why, tuple) else (why,))), f"{label}: {name}: {got[name]}"
        else:
            assert got[name] == want[name], f"{label}: {name}: {got[name]}"


def segment(log, name):
    """The lines of scenario `name`, SCENARIO START to RESULT."""
    i = log.index(f"PROBE SCENARIO START {name}")
    return log[i:next(k for k in range(i, len(log)) if log[k].startswith(f"PROBE RESULT {name} ")) + 1]


def check_obsy(log):
    """The obsy lines a log reader decides on, as the stub plays them."""
    info = [s[len("PROBE INFO "):] for s in log if s.startswith("PROBE INFO obsy ")]
    def has(name, text):
        return any(s.startswith(name + " ") and text in s for s in info)
    for name in OBSY:  # every scenario reaches its last press and names who holds the pressed index
        assert has(name, "VERDICT ") and not has(name, "never happened"), name
    verdicts = [s for s in info if " VERDICT Esau Jr." in s]
    for v in verdicts:  # each Esau Jr. press logs the form's first update
        name, label = v.split(" VERDICT ")[0], v.split(" VERDICT ")[1].split(" index ")[0]
        if " -> unchanged" in v:  # a fresh copy's form on the presser's seed: its TIMING watch is dropped (same-seed press)
            continue
        assert has(name, f"TIMING {label} frame ") and has(name, f"TIMING {label} pressed at frame "), v
    assert has("obsy a J&E by Esau", "VERDICT Esau Jr. #1 index 1 B -> C new | 0:A(t19)=")
    timing = [s.split(" index ")[0] for s in info if " TIMING " in s and " frame " in s and " pressed at " not in s]
    assert timing and len(timing) == len(set(timing)), "a TIMING frame logged twice"
    assert has("obsy a schoolbag", "Esau Jr. to primary after 61 updates by SwapActiveItems | primary 703 secondary 45")
    assert has("obsy a Forgotten and Soul", "switch to the Soul after 61 updates by ChangePlayerType 17")
    assert has("obsy a schoolbag Clicker", "VERDICT Clicker index 0 B -> unchanged")
    assert has("obsy a J&E by Esau", "index 1 type ") and has("obsy a J&E by Esau", " primary 105 c703 owned 0")
    assert has("obsy b identity", "VERDICT Flip after Continue index 0 A -> B moved from 1 |")
    assert sum(" after Continue: player seeds " in s for s in info) == len(OBSY_LARGE)
    ids = [s for s in info if s.startswith("obsy b identity IDS ")]
    assert len(ids) == 7 * 2 - 1 and all(" InitSeed " in s and " OtherTwin " in s and " MainTwin " in s for s in ids), ids  # one player after Esau Jr. #1
    # A Birthright twin's fresh copy stores presser and twin (obsyb1-2): the presser's spend is its watched drop, never a twin's seed
    swaps = [s for s in segment(log, "obsy b identity") if s.startswith("PROBE SWAP Esau Jr. #")]
    assert " players 2 -> 1 " in swaps[0] and " players 1 -> 2 " in swaps[1], swaps
    assert all(" spent stored presser charge, " in s for s in swaps), swaps
    print("PASS obsy verdicts, timing, Schoolbag, Soul switch, Continue, ids and Birthright twin lines")


def test_regression(path):
    log = run(path)
    got = check_finished(log, "regression mode")
    for name in SCENARIOS:
        print("RESULT", name, got[name])
    expect_results(got, "regression mode")
    assert any(s.startswith("PROBE HARNESS START") and "regression mode" in s for s in log), "mode not logged"
    assert sum(s.startswith("PROBE GAME START") and s.endswith("continued true") for s in log) == 3 + len(OBSY_LARGE) + len(FINAL_LARGE), "the continues did not resume"
    presses = [s for s in log if s.startswith("PROBE PRESS ")]
    swaps = [s for s in log if s.startswith("PROBE SWAP ")]
    stored = [s for s in swaps if " spent stored presser charge, " in s]
    same = [s for s in log if s.startswith("PROBE INFO ") and " new form, same seed " in s]  # a fresh copy's form on its presser's seed
    assert presses and len(presses) == len(swaps) + len(same) and stored, (len(presses), len(swaps), len(same), len(stored))
    assert not any("(seed holds no" in s for s in swaps)
    print("PASS every swap logged a spend:", len(swaps), "swaps,", len(stored), "by a stored presser")
    assert any(s.startswith("PROBE SWAP Clicker") and "players 1 -> 2" in s for s in log), "P2 never split"
    print("PASS P2 reaches the split")
    check_obsy(log)


def test_tlaz_roll_29(path):
    # Clicker from the Dead form rolling 29 (run 8): S3's merge checks with Flip kept, the rest unchanged
    got = check_finished(run(path, tlazRoll=29), "Clicker rolls 29")
    expect_results(got, "Clicker rolls 29", want={**wanted("regression"), "S3": "PASS 21 checks"})
    print("PASS Clicker rolling 29:", got["S3"])


def test_default(path):
    expect_results(check_finished(run(path, mode=""), "default mode"), "default mode", mode="")
    print("PASS default mode runs small and new large scenarios, skips the rest and F, G")


def test_final(path):
    log = run(path, mode=FINAL_MODE)
    expect_results(check_finished(log, FINAL_MODE), FINAL_MODE, mode=FINAL_MODE)
    rows = [s for s in log if s.startswith("PROBE ROWS final ")]
    assert any(" LJ stored key 4294967" in s for s in rows), "LJ never listed on its own key beside D"
    # A press that brings back a character on the presser's seed is the presser's stored drop, not the returned one's charge
    for label in ("Flip LJ -> D", "Flip of the form"):
        swaps = [s for s in log if s.startswith(f"PROBE SWAP {label} ")]
        assert swaps and all(" spent stored presser charge, " in s for s in swaps), (label, swaps)
    assert any(s.startswith("PROBE INFO final A two Esau Jr. copies swap the Esau Jr. copies after ") and " by SwapActiveItems | " in s for s in log)
    hand = [s for s in log if s.startswith("PROBE INFO final B Esau Jr. dropped and picked up YOU: ")]
    assert len(hand) == 2, hand
    assert not any(s.startswith("PROBE STUCK final B") for s in log), "a hand step logged STUCK"
    assert any("HELPERS after Continue" in s and " type 14 parent index 0 " in s for s in log), "no Keeper after the Continue"
    print(f"PASS {FINAL_MODE}: {len(FINAL_RUN)} scenarios, {run.updates} updates in the stub")


def test_final_worst(path):
    # The final mode's worst case: no console command ever runs, so every scenario stalls to its ceiling, a checked one FAILing.
    log = run(path, mode=FINAL_MODE, render_every=10 ** 6)
    got = check_finished(log, "final worst case")
    expect_results(got, "final worst case", FINAL_MODE, "scenario ceiling ", CHECKED_FINAL)
    for name in CHECKED_FINAL:
        assert got[name] == f"FAIL scenario ceiling {BUDGET[name]} updates", (name, got[name])
    assert all(f"PROBE INFO {n} scenario ceiling {BUDGET[n]} updates" in log for n in FINAL_OBS)
    worst = sum(BUDGET.values()) + len(SCENARIOS) - len(BUDGET) + 1
    assert run.updates == worst, (run.updates, worst)
    print(f"PASS {FINAL_MODE} worst case: {worst} updates ({worst / 30 / 60:.1f} minutes of updates)")


def test_only_obs(path):
    mode = "only obs\r\nSTUCK 3 obs mirror | settle"  # a STUCK line left in the file keeps the mode
    log = run(path, mode=mode)
    expect_results(check_finished(log, "only obs mode"), "only obs mode", mode=mode)
    assert any(s.startswith("PROBE HARNESS START") and "only obs mode" in s for s in log), "only mode not logged"
    print("PASS only obs runs just the obs scenarios")


def test_obsx(path):
    log = run(path, mode="only obsx", ignoreFirstVetoPress=True, birthrightDeadFirst=True)
    expect_results(check_finished(log, "only obsx mode"), "only obsx mode", mode="only obsx")
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
    assert any("obsx form uses Clicker effect UseActiveItem Clicker type 29 -> 35 changed true primary 703 -> 703" in s for s in log)
    assert any("obsx form uses Clicker effect MC_USE_ITEM " in s and s.endswith("slot -1 charge n/a") for s in log)
    # each copy keeps the character it last swapped out (console 2026-11-22): after a D6 the fresh copy makes a new form first; as in obsx
    # runs 2-6, where the original's fresh copy brought a form on its first form's seed (B present true)
    expected = {"obsx original loses Esau Jr.": ["false", "true"], "obsx form uses Clicker effect": ["true", "false"]}
    for name in DISPUTES[-4:]:
        history = [s for s in log if s.startswith(f"PROBE INFO {name} press #") and " A seed " in s]
        assert [s.rsplit(" ", 1)[1] for s in history] == expected.get(name, ["false", "false"]), history
    b_returns = [s for s in log if s.startswith("PROBE INFO obsx original loses Esau Jr. press #") and " B seed " in s]
    assert [s.rsplit(" ", 1)[1] for s in b_returns] == ["true", "false"], b_returns
    print("PASS only obsx, re-armed veto, same-update change, Birthright Flip, and controls")


def test_obsx_limits(path):
    log = run(path, mode="only obsx", ignoreClickerEffect=True)
    check_finished(log, "Clicker effect does nothing")
    prefix = "PROBE INFO obsx form uses Clicker effect "
    assert any(s.startswith(prefix + "UseActiveItem Clicker type 29 -> 29 changed false") for s in log)
    assert not any(s.startswith(prefix + "press #") for s in log)
    log = run(path, mode="only obsx", ignoreRestart=True)
    got = check_finished(log, "obsx setup step times out")
    assert all(got[name] == WANT[name] for name in DISPUTES)
    assert sum(s.endswith("never happened: obsx ceiling 120 updates: no new game") for s in log) == len(DISPUTES)
    log = run(path, mode="only obsx", render_every=200)
    got = check_finished(log, "obsx scenario times out")
    assert all(got[name] == WANT[name] for name in DISPUTES)
    assert sum(s.endswith("scenario ceiling 445 updates") for s in log) == len(DISPUTES)
    assert run.updates == 445 * len(DISPUTES) + len(SCENARIOS) - len(DISPUTES) + 1 < 3 * 60 * 30, run.updates
    print("PASS obsx unchanged effect stops, setup step and scenario limits, and total update budget")


def test_obsy_worst(path):
    # Each obsy mode's worst case: no console command ever runs, so every scenario stalls to its ceiling.
    for mode, names in (("a", OBSY_A), ("b", OBSY_B)):
        log = run(path, mode=f"only obsy {mode}", render_every=10 ** 6)
        expect_results(check_finished(log, f"only obsy {mode}"), f"only obsy {mode}", mode=f"only obsy {mode}")
        budget = {n: 1000 if n in OBSY_LARGE else 445 for n in names}
        assert all(f"PROBE INFO {n} scenario ceiling {b} updates" in log for n, b in budget.items()), mode
        worst = sum(budget.values()) + len(SCENARIOS) - len(names) + 1
        assert run.updates == worst < 3 * 60 * 30, (mode, run.updates, worst)
        print(f"PASS only obsy {mode}: worst case {worst} updates")


def test_new_run_instead_of_continue(path):
    log = run(path, on_exit="new")
    got = check_finished(log, "new run instead of Continue")
    for name in NEW:
        assert got[name].startswith("FAIL") and "a new run started, not a Continue" in got[name], got[name]
    for name in OBSY_LARGE:  # INFO only: the Continue step is logged as never happened and ends the scenario
        assert got[name] == WANT[name] and any(s.startswith(f"PROBE INFO {name} ") and " exit and Continue never happened: " in s and s.endswith("a new run started, not a Continue") for s in log), name
    print("PASS new run instead of Continue fails:", got["continue"])


def test_late_continue(path):
    # The user continues after the 600-update Continue step gave up: logged, and the next scenario runs on
    log = run(path, mode="only obsy b", continue_after=615)  # lands in the next scenario before its own Continue step
    got = check_finished(log, "late Continue")
    note = "; late Continue mid-scenario"
    assert all(got[name].removesuffix(note) == WANT[name] for name in OBSY_B), got
    late = [s for s in log if s.endswith(" late Continue, ignored")]
    assert late and not any("unexpected game start" in s for s in log), late
    in_b = [s for s in late if any(s.startswith(f"PROBE INFO {n} ") for n in OBSY_B)]  # a later one can land while later scenarios SKIP
    assert sum(got[name].endswith(note) for name in OBSY_B) == len(in_b), got
    print("PASS a late Continue is ignored and noted:", len(late), "times")


def test_same_seed(path):
    # obsy b run 1: after a Continue, Esau Jr. made a new entity with the presser's seed and type, its items re-rolled
    name = "obsy b continue after B loses Esau Jr."
    log = run(path, mode="only " + name, jrSameSeed=True)
    got = check_finished(log, "Esau Jr. keeps the seed")
    assert got[name] == WANT[name], got[name]
    same = [s for s in log if s.startswith(f"PROBE INFO {name} Esau Jr. #") and " new form, same seed " in s]
    assert len(same) == 4 and " items 4:1/1 703:1/1 -> 53:1/1 703:1/1, INPUT_ACTION charge+battery 1 -> 0" in same[0], same
    assert not any(s.startswith(f"PROBE INFO {name} ") and "never happened" in s for s in log)
    print("PASS a press that keeps the seed is logged as data:", same[0])
    # Only press #1 keeps the seed: its TIMING watch is dropped, not woken by #2's new seed under #1's label
    name = "obsy b continue with A stored"
    log = run(path, mode="only " + name, jrSameSeed=1)
    got = check_finished(log, "Esau Jr. #1 keeps the seed")
    assert got[name] == WANT[name], got[name]
    assert any(s.startswith(f"PROBE INFO {name} Esau Jr. #1 new form, same seed ") for s in log)
    assert any(s.startswith(f"PROBE INFO {name} TIMING Esau Jr. #2 frame ") for s in log)
    assert not any(s.startswith(f"PROBE INFO {name} TIMING Esau Jr. #1 frame ") for s in log), "stale TIMING watch woke"
    print("PASS a same-seed press leaves no TIMING watch behind")


def test_engine_stalls(path):
    # a scenario ceiling of 600 or less ends the scenario first
    expect_results(check_finished(run(path, ignoreRestart=True), "restart ignored"), "restart timeout", why=("no new game after 600 updates", "scenario ceiling "),
                   names=[n for n in SCENARIOS if n not in DISPUTES and n not in OBSY and n not in FINAL_OBS and n not in ONLY_PICKED])
    # probes' first press is Esau Jr., a swap: every scenario fails on its first press
    log = run(path, ignorePress=True)
    assert any("obsx form loses Esau Jr. 2 Esau Jr. never happened:" in s for s in log)
    assert not any(s == "PROBE CMD giveitem c105" for s in log)
    expect_results(check_finished(log, "press ignored"), "press ignored", why=("no new character, arms ", "scenario ceiling "),
                   names=[n for n in SCENARIOS if n not in NO_SWAP and n not in ONLY_PICKED])
    stuck = [s for s in log if s.startswith("PROBE STUCK ")]
    assert stuck and stuck[0].endswith(" 60"), stuck[:1]
    assert run.saved.startswith(f"regression\nSTUCK {len(stuck)} ") and " | " in run.saved, run.saved
    print("PASS a stuck wait logs STUCK once and saves it under the mode line:", len(stuck), "stuck,", repr(run.saved))


def test_no_spend(path):
    got = check_finished(run(path, noSpend=True), "no spend")
    want = wanted("regression")
    for name in SCENARIOS:
        if name in NO_SWAP or name in ONLY_PICKED:
            assert got[name] == want[name], f"no spend: {name}: {got[name]}"
        else:
            assert got[name].startswith("FAIL") and SPEND_SEEN[name] in got[name], f"no spend: {name}: {got[name]}"
    print("PASS no spend fails every swap:", got["test3"][:110])


def test_wrong_floor(path):
    got = check_finished(run(path, wrongFloor=True), "wrong floor")
    want = wanted("regression")
    for name in SCENARIOS:
        if name in LOOKED and name not in ONLY_PICKED:
            # expectN names the wrong floor; a floor-filtered count names the floor it found too few on
            assert got[name].startswith("FAIL") and ("on 'Wrong'" in got[name] or " on Floor" in got[name]), f"wrong floor: {name}: {got[name]}"
        else:
            assert got[name] == want[name], f"wrong floor: {name}: {got[name]}"
    print("PASS a wrong ReHUD floor fails:", got["test3"][:90])


def test_invariants(path):
    for flag, mode, why, names in INVARIANT_MODES:
        log = run(path, mode=mode, **{flag: True})
        got = check_finished(log, flag)
        hit = [n for n in SCENARIOS if got[n].startswith("FAIL") and why in got[n]]
        assert hit == names, f"{flag} ({mode}): invariant fired in {hit}"
        print(f"PASS {flag} ({mode}) fails the invariant in {len(hit)} scenarios")


TESTS = [test_regression, test_tlaz_roll_29, test_default, test_final, test_final_worst, test_only_obs, test_obsx, test_obsx_limits, test_obsy_worst,
         test_new_run_instead_of_continue, test_late_continue, test_same_seed, test_engine_stalls, test_no_spend, test_wrong_floor, test_invariants]


def main(path, names):
    by_name = {t.__name__: t for t in TESTS}
    for name in names or by_name:
        by_name[name](path)
    print("PASS dry run")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
