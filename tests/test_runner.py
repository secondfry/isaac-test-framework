"""The runner contract: tags, limits, the worst cases, Exit & Continue answered late or with a new run, STUCK, fixtures (teardown once,
setup throw, precondition) and which steps prompt the user."""
import dry
import test_legacy as legacy
from test_legacy import SPEC, SCENARIOS, ONLY_PICKED, OBSY_A, OBSY_B, OBSY_LARGE, DISPUTES, OBSY, FINAL_OBS, BUDGET, CHECKED_FINAL, \
    FINAL_MODE, NEW

WANT_LEGACY = legacy.WANT

# A spec played in place of specs/legacy.lua: each fixture case, and a step whose label names Continue without being manual (bug 2).
RUNNER_SPEC = """
local console, wait, assert_ = include("scripts.console"), include("scripts.wait"), include("scripts.assert")
DOWNS = {}
local function down(name) return function() DOWNS[name] = (DOWNS[name] or 0) + 1 end end
local function isaac() return Isaac.GetPlayer(0):GetPlayerType() == 0, "player 0 is not Isaac" end
local function waits(label, n) return wait.act(label, function() end, function(ctx) return ctx.t >= n end) end
return { name = "runner", tests = {
	{ name = "setup throws", tags = { "runner" }, steps = {},
		fixture = { name = "throws", setup = { function() error("setup broke") end }, done = isaac, teardown = down("setup throws") } },
	{ name = "precondition", tags = { "runner" }, steps = {},
		fixture = { name = "never", setup = {}, done = function() return false, "Clicker held" end, teardown = down("precondition") } },
	{ name = "teardown throws", tags = { "runner" }, steps = {},
		fixture = { name = "isaac", setup = { console.fresh(0) }, done = isaac, teardown = function() error("teardown broke") end } },
	{ name = "fixture done", tags = { "runner" }, fixture = { name = "isaac", setup = { console.fresh(0) }, done = isaac, teardown = down("fixture done") },
		steps = { function(ctx) assert_.expect(ctx, "player 0 type", Isaac.GetPlayer(0):GetPlayerType(), 0) end } },
	{ name = "pre fails", tags = { "runner" }, steps = { function() assert_.pre(false, "a held Clicker") end } },
	{ name = "Continue in a label", tags = { "runner" }, steps = { waits("Flip after Continue", 5) } },
	{ name = "manual step", tags = { "runner" }, steps = { { manual = { kind = "continue" }, run = waits("YOU: wait", 5) } } },
} }
"""
RUNNER = [f"runner > {n}" for n in ("setup throws", "precondition", "teardown throws", "fixture done", "pre fails", "Continue in a label",
                                    "manual step")]
WANT = {
    "runner > setup throws": "FAIL error in step 1: ",
    "runner > precondition": "FAIL precondition: Clicker held",
    "runner > teardown throws": "PASS 0 assertions",
    "runner > fixture done": "PASS 1 assertions",
    "runner > pre fails": "FAIL precondition: a held Clicker",
    "runner > Continue in a label": "PASS 0 assertions",
    "runner > manual step": "PASS 0 assertions",
}


def test_fixtures(path):
    prompts = []

    def watch(g):  # every update's prompt, with the test it came in
        S = g.HARNESS.session
        if S.manual:
            prompts.append((S.ctx.name, S.manual.kind))
        return dry.walk_target(g)
    lua = {}

    def loader(l, p):
        dry.load(l, p, {"legacy": RUNNER_SPEC})
        lua["g"] = l.globals()
    log = dry.run(path, mode="tags runner", loader=loader, walk=watch)
    got = dry.check_finished(log, "runner spec", RUNNER)
    for name, want in WANT.items():
        assert got[name].startswith(want) if want.endswith(": ") else got[name] == want, (name, got[name])
    assert "setup broke" in got["runner > setup throws"], got["runner > setup throws"]
    downs = dict(lua["g"].DOWNS.items())
    assert downs == {"setup throws": 1, "precondition": 1, "fixture done": 1}, downs
    assert sum(s.startswith("PROBE TEARDOWN FAIL runner > teardown throws ") and "teardown broke" in s for s in log) == 1
    assert set(prompts) == {("runner > manual step", "continue")}, set(prompts)
    print("PASS fixtures: teardown once (setup throw, precondition, TEARDOWN FAIL), preconditions, only manual steps prompt")


def test_no_tags(path):
    want = dry.wanted("", legacy.TESTS_TAGS)
    dry.expect_results(legacy.finished(dry.run(path, mode=""), "no tags"), "no tags", want)
    print("PASS no tags runs every test but the exit-continue ones not new, and skips the opt-in F, G")


def test_tags_obs(path):
    mode = f"tags obs\r\nSTUCK 3 {SPEC}obs mirror | settle"  # a STUCK line left in the file keeps the tags
    log = dry.run(path, mode=mode)
    dry.expect_results(legacy.finished(log, "tags obs"), "tags obs", legacy.wanted(mode))
    assert any(s.startswith("PROBE HARNESS START") and "tags 'tags obs'" in s for s in log), "tags not logged"
    print("PASS tags obs runs just the obs tests")


def test_final_worst(path):
    # rehud-2.8's worst case: no console command ever runs, so every test stalls to its limit, a checked one FAILing.
    log = dry.run(path, mode=FINAL_MODE, render_every=10 ** 6)
    got = legacy.finished(log, "final worst case")
    dry.expect_results(got, "final worst case", legacy.wanted(FINAL_MODE), "test limit ", CHECKED_FINAL)
    for name in CHECKED_FINAL:
        assert got[name] == f"FAIL test limit {BUDGET[name]} updates", (name, got[name])
    assert all(f"PROBE INFO {SPEC}{n} test limit {BUDGET[n]} updates" in log for n in FINAL_OBS)
    worst = sum(BUDGET.values()) + len(SCENARIOS) - len(BUDGET) + 1
    assert dry.run.updates == worst, (dry.run.updates, worst)
    print(f"PASS {FINAL_MODE} worst case: {worst} updates ({worst / 30 / 60:.1f} minutes of updates)")


def test_obsx_limits(path):
    log = dry.run(path, mode="tags obsx", ignoreRestart=True)
    got = legacy.finished(log, "obsx setup step times out")
    assert all(got[name] == WANT_LEGACY[name] for name in DISPUTES)
    assert sum(s.endswith("never happened: step limit 120 updates: no new game") for s in log) == len(DISPUTES)
    log = dry.run(path, mode="tags obsx", render_every=200)
    got = legacy.finished(log, "obsx test times out")
    assert all(got[name] == WANT_LEGACY[name] for name in DISPUTES)
    assert sum(s.endswith("test limit 445 updates") for s in log) == len(DISPUTES)
    assert dry.run.updates == 445 * len(DISPUTES) + len(SCENARIOS) - len(DISPUTES) + 1 < 3 * 60 * 30, dry.run.updates
    print("PASS obsx setup step and test limits, and total update budget")


def test_obsy_worst(path):
    # Each obsy tag's worst case: no console command ever runs, so every test stalls to its limit.
    for tag, names in (("a", OBSY_A), ("b", OBSY_B)):
        mode = f"tags obsy-{tag}"
        log = dry.run(path, mode=mode, render_every=10 ** 6)
        dry.expect_results(legacy.finished(log, mode), mode, legacy.wanted(mode))
        budget = {n: 1000 if n in OBSY_LARGE else 445 for n in names}
        assert all(f"PROBE INFO {SPEC}{n} test limit {b} updates" in log for n, b in budget.items()), mode
        worst = sum(budget.values()) + len(SCENARIOS) - len(names) + 1
        assert dry.run.updates == worst < 3 * 60 * 30, (mode, dry.run.updates, worst)
        print(f"PASS {mode}: worst case {worst} updates")


def test_new_run_instead_of_continue(path):
    log = dry.run(path, on_exit="new")
    got = legacy.finished(log, "new run instead of Continue")
    for name in NEW:
        assert got[name].startswith("FAIL") and "a new run started, not a Continue" in got[name], got[name]
    for name in OBSY_LARGE:  # a recon test: the Continue step is logged as never happened and ends the test
        assert got[name] == WANT_LEGACY[name] and any(s.startswith(f"PROBE INFO {SPEC}{name} ") and " exit and Continue never happened: " in s
                                                      and s.endswith("a new run started, not a Continue") for s in log), name
    print("PASS new run instead of Continue fails:", got["continue"])


def test_late_continue(path):
    # The user continues after the 600-update Continue step gave up: logged, and the next test runs on
    log = dry.run(path, mode="tags obsy-b", continue_after=615)  # lands in the next test before its own Continue step
    got = legacy.finished(log, "late Continue")
    note = "; late Continue mid-test"
    assert all(got[name].removesuffix(note) == WANT_LEGACY[name] for name in OBSY_B), got
    late = [s for s in log if s.endswith(" late Continue, ignored")]
    assert late and not any("unexpected game start" in s for s in log), late
    in_b = [s for s in late if any(s.startswith(f"PROBE INFO {SPEC}{n} ") for n in OBSY_B)]  # a later one can land while later tests SKIP
    assert sum(got[name].endswith(note) for name in OBSY_B) == len(in_b), got
    print("PASS a late Continue is ignored and noted:", len(late), "times")


def test_restart_ignored(path):
    # a test limit of 600 or less ends the test first
    got = legacy.finished(dry.run(path, ignoreRestart=True), "restart ignored")
    dry.expect_results(got, "restart timeout", legacy.wanted("tags all"), ("no new game after 600 updates", "test limit "),
                       [n for n in SCENARIOS if n not in DISPUTES and n not in OBSY and n not in FINAL_OBS and n not in ONLY_PICKED])
    print("PASS a restart that never comes fails every test but the soft recon ones")


TESTS = [test_fixtures, test_no_tags, test_tags_obs, test_final_worst, test_obsx_limits, test_obsy_worst, test_new_run_instead_of_continue,
         test_late_continue, test_restart_ignored]
