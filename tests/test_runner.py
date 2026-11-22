"""The runner contract: the whole session, tags, limits, the worst cases, Exit & Continue answered late or with a new run, STUCK,
fixtures (teardown once, setup throw, precondition) and which steps prompt the user. Spec-agnostic: the tests, their tags and limits
come from the runner (dry.plan), their verdicts from every module's WANT."""
import dry
from legacy_names import FINAL_MODE

ASK = "PROBE ACTION exit to the menu and Continue now by type"

# A spec played in place of specs/hello.lua: each fixture case, and a step whose label names Continue without being manual (bug 2).
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


def tagged(path, tag):
    return [t for t in dry.plan(path) if tag in t.tags]


def test_all(path):
    log = dry.run(path)
    plan = dry.plan(path)
    got = dry.finished(log, "tags all", path)
    for name, verdict in got.items():
        print("RESULT", name, verdict)
    dry.expect_results(got, "tags all", dry.expected(path))
    assert f"PROBE HARNESS START {len(plan)} tests, tags 'tags all', update snapshots no, mod data 'tags all'" in log, "tags not logged"
    last = [t.name for t in plan if "exit-continue" in t.tags]
    assert [t.name for t in plan[len(plan) - len(last):]] == last, "an Exit & Continue test plays before another test (D7)"
    asks, resumed = sum(s.startswith(ASK) for s in log), sum(s.startswith("PROBE GAME START") and s.endswith("continued true") for s in log)
    assert asks == resumed >= sum("opt-in" not in t.tags for t in tagged(path, "exit-continue")), ("the continues did not resume", asks, resumed)
    presses = [s for s in log if s.startswith("PROBE PRESS ")]
    swaps = [s for s in log if s.startswith("PROBE SWAP ")]
    stored = [s for s in swaps if " spent stored presser charge, " in s]
    same = [s for s in log if s.startswith("PROBE INFO ") and " new form, same seed " in s]  # a fresh copy's form on its presser's seed
    assert presses and len(presses) == len(swaps) + len(same) and stored, (len(presses), len(swaps), len(same), len(stored))
    assert not any("(seed holds no" in s for s in swaps)
    print("PASS every swap logged a spend:", len(swaps), "swaps,", len(stored), "by a stored presser")
    assert dry.report(log) == (0, "ALL PASS"), dry.report(log)
    print(f"PASS tags all: {len(plan)} tests, Exit & Continue ones last, report.py ALL PASS")


def test_fixtures(path):
    prompts = []

    def watch(g):  # every update's prompt, with the test it came in
        S = g.HARNESS.session
        if S.manual:
            prompts.append((S.ctx.name, S.manual.kind))
        return dry.walk_target(g)
    lua = {}

    def loader(l, p):
        dry.load(l, p, {"hello": RUNNER_SPEC})
        lua["g"] = l.globals()
    log = dry.run(path, mode="tags runner", loader=loader, walk=watch)
    assert log[-1] == "PROBE HARNESS DONE" and not any("HARNESS ERROR" in s for s in log), "runner spec: run did not finish"
    got = {name: verdict for name, verdict in dry.results(log).items() if name.startswith("runner > ")}
    assert list(got) == RUNNER, list(got)
    assert all(v.startswith("SKIP ") for name, v in dry.results(log).items() if name not in got), "another spec's test ran"
    for name, want in WANT.items():
        assert got[name].startswith(want) if want.endswith(": ") else got[name] == want, (name, got[name])
    assert "setup broke" in got["runner > setup throws"], got["runner > setup throws"]
    downs = dict(lua["g"].DOWNS.items())
    assert downs == {"setup throws": 1, "precondition": 1, "fixture done": 1}, downs
    assert sum(s.startswith("PROBE TEARDOWN FAIL runner > teardown throws ") and "teardown broke" in s for s in log) == 1
    assert set(prompts) == {("runner > manual step", "continue")}, set(prompts)
    print("PASS fixtures: teardown once (setup throw, precondition, TEARDOWN FAIL), preconditions, only manual steps prompt")


def test_no_tags(path):
    dry.expect_results(dry.finished(dry.run(path, mode=""), "no tags", path), "no tags", dry.expected(path, ""))
    print("PASS no tags runs every test but the exit-continue ones not new, and skips the opt-in ones")


def test_tags_obs(path):
    mode = "tags obs\r\nSTUCK 3 obs mirror | settle"  # a STUCK line left in the file keeps the tags
    log = dry.run(path, mode=mode)
    dry.expect_results(dry.finished(log, "tags obs", path), "tags obs", dry.expected(path, mode))
    assert any(s.startswith("PROBE HARNESS START") and "tags 'tags obs'" in s for s in log), "tags not logged"
    print("PASS tags obs runs just the obs tests")


def worst_case(path, tests):
    """The session's updates when each of `tests` stalls to its limit: their limits, one SKIP update per other test, HARNESS DONE."""
    assert all(t.limit for t in tests), [t.name for t in tests if not t.limit]
    return sum(t.limit for t in tests) + len(dry.plan(path)) - len(tests) + 1


def test_final_worst(path):
    # rehud-2.8's worst case: no console command ever runs, so every test stalls to its limit, a checked one FAILing.
    log = dry.run(path, mode=FINAL_MODE, render_every=10 ** 6)
    got = dry.finished(log, "final worst case", path)
    final = tagged(path, "rehud-2.8")
    checked = [t for t in final if not t.snapshot]
    dry.expect_results(got, "final worst case", dry.expected(path, FINAL_MODE), "test limit ", [t.name for t in checked])
    for t in checked:
        assert got[t.name] == f"FAIL test limit {t.limit} updates", (t.name, got[t.name])
    assert all(f"PROBE INFO {t.name} test limit {t.limit} updates" in log for t in final if t.snapshot)
    worst = worst_case(path, final)
    assert dry.run.updates == worst, (dry.run.updates, worst)
    print(f"PASS {FINAL_MODE} worst case: {worst} updates ({worst / 30 / 60:.1f} minutes of updates)")


def test_obsx_limits(path):
    obsx = tagged(path, "obsx")
    want = dry.expected(path, "tags obsx")
    log = dry.run(path, mode="tags obsx", ignoreRestart=True)
    got = dry.finished(log, "obsx setup step times out", path)
    assert all(got[t.name] == want[t.name] for t in obsx)
    assert sum(s.endswith("never happened: step limit 120 updates: no new game") for s in log) == len(obsx)
    log = dry.run(path, mode="tags obsx", render_every=200)
    got = dry.finished(log, "obsx test times out", path)
    assert all(got[t.name] == want[t.name] for t in obsx)
    assert sum(s.endswith("test limit 445 updates") for s in log) == len(obsx)
    assert dry.run.updates == worst_case(path, obsx) < 3 * 60 * 30, dry.run.updates
    print("PASS obsx setup step and test limits, and total update budget")


def test_obsy_worst(path):
    # Each obsy tag's worst case: no console command ever runs, so every test stalls to its limit.
    for tag in ("obsy-a", "obsy-b"):
        mode = f"tags {tag}"
        log = dry.run(path, mode=mode, render_every=10 ** 6)
        dry.expect_results(dry.finished(log, mode, path), mode, dry.expected(path, mode))
        tests = tagged(path, tag)
        assert all(f"PROBE INFO {t.name} test limit {t.limit} updates" in log for t in tests), mode
        worst = worst_case(path, tests)
        assert dry.run.updates == worst < 3 * 60 * 30, (mode, dry.run.updates, worst)
        print(f"PASS {mode}: worst case {worst} updates")


def test_new_run_instead_of_continue(path):
    log = dry.run(path, on_exit="new")
    got = dry.finished(log, "new run instead of Continue", path)
    want = dry.expected(path)
    asked = [t for t in tagged(path, "exit-continue") if "opt-in" not in t.tags]
    for t in asked:
        if not t.snapshot:
            assert got[t.name].startswith("FAIL") and "a new run started, not a Continue" in got[t.name], got[t.name]
            continue
        # a recon test: the Continue step is logged as never happened and ends the test
        assert got[t.name] == want[t.name] and any(s.startswith(f"PROBE INFO {t.name} ") and " exit and Continue never happened: " in s
                                                   and s.endswith("a new run started, not a Continue") for s in log), t.name
    print("PASS new run instead of Continue fails:", next(got[t.name] for t in asked if not t.snapshot))


def test_late_continue(path):
    # The user continues after the 600-update Continue step gave up: logged, and the next test runs on
    log = dry.run(path, mode="tags obsy-b", continue_after=615)  # lands in the next test before its own Continue step
    got = dry.finished(log, "late Continue", path)
    want = dry.expected(path, "tags obsy-b")
    names = [t.name for t in tagged(path, "obsy-b")]
    note = "; late Continue mid-test"
    assert all(got[name].removesuffix(note) == want[name] for name in names), got
    late = [s for s in log if s.endswith(" late Continue, ignored")]
    assert late and not any("unexpected game start" in s for s in log), late
    in_b = [s for s in late if any(s.startswith(f"PROBE INFO {n} ") for n in names)]  # a later one can land while later tests SKIP
    assert sum(got[name].endswith(note) for name in names) == len(in_b), got
    print("PASS a late Continue is ignored and noted:", len(late), "times")


def test_restart_ignored(path):
    # a test limit of 600 or less ends the test first; a test whose step errors end it (recon, onStepError "end") logs them instead
    got = dry.finished(dry.run(path, ignoreRestart=True), "restart ignored", path)
    dry.expect_results(got, "restart timeout", dry.expected(path), ("no new game after 600 updates", "test limit "),
                       [t.name for t in dry.plan(path) if t.soft != "end" and "opt-in" not in t.tags])
    print("PASS a restart that never comes fails every test but the soft recon ones")


TESTS = [test_all, test_fixtures, test_no_tags, test_tags_obs, test_final_worst, test_obsx_limits, test_obsy_worst,
         test_new_run_instead_of_continue, test_late_continue, test_restart_ignored]
