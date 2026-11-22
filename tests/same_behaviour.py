"""The refactored harness against HEAD df8ba84: each dry run played by both, logs compared line by line after normalising.
Run: python -B -I tests/same_behaviour.py main.lua. Temporary: deleted once the refactor is done (plan S6)."""
import os
import re
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dry  # noqa: E402
import test_legacy as legacy  # noqa: E402
from test_invariants import INVARIANT_MODES  # noqa: E402

BASE = "df8ba84"
WORKERS = 3  # a few cores only: all of them starve the machine (user, 2026-11-22)
REPO = os.path.join(dry.HERE, "..")
# Every run the dry test makes: (name, run keyword arguments), with the new harness's tags line as `mode`.
CONFIGS = [
    ("all", {}),
    ("tlazRoll 29", {"tlazRoll": 29}),
    ("no tags", {"mode": ""}),
    ("final", {"mode": legacy.FINAL_MODE}),
    ("final worst", {"mode": legacy.FINAL_MODE, "render_every": 10 ** 6}),
    ("obs", {"mode": f"tags obs\r\nSTUCK 3 {legacy.SPEC}obs mirror | settle"}),
    ("obsx veto", {"mode": "tags obsx", "ignoreFirstVetoPress": True, "birthrightDeadFirst": True}),
    ("obsx no effect", {"mode": "tags obsx", "ignoreClickerEffect": True}),
    ("obsx no restart", {"mode": "tags obsx", "ignoreRestart": True}),
    ("obsx slow render", {"mode": "tags obsx", "render_every": 200}),
    ("obsy a worst", {"mode": "tags obsy-a", "render_every": 10 ** 6}),
    ("obsy b worst", {"mode": "tags obsy-b", "render_every": 10 ** 6}),
    ("new run", {"on_exit": "new"}),
    ("late Continue", {"mode": "tags obsy-b", "continue_after": 615}),
    ("same seed", {"mode": "tags continue-b-loses", "jrSameSeed": True}),
    ("same seed once", {"mode": "tags continue-a-stored", "jrSameSeed": 1}),
    ("restart ignored", {"ignoreRestart": True}),
    ("press ignored", {"ignorePress": True}),
    ("no spend", {"noSpend": True}),
    ("wrong floor", {"wrongFloor": True}),
    *((f"{flag} ({mode})", {"mode": mode, flag: True}) for flag, mode, _, _ in INVARIANT_MODES),
]
# HEAD's mode for each tags line (D3: tags replace modes).
MODES = {"tags all": "regression", "": "", legacy.FINAL_MODE: "only final,S3,r1,P4c", "tags obs": "only obs", "tags obsx": "only obsx",
         "tags obsy-a": "only obsy a", "tags obsy-b": "only obsy b", "tags continue-b-loses": "only obsy b continue after B loses Esau Jr.",
         "tags continue-a-stored": "only obsy b continue with A stored"}
# Each old scenario's new tests, "<spec> > <test>"; a scenario split in S4 lists every part.
NAMES = {n: [legacy.SPEC + n] for n in legacy.SCENARIOS}
NEW_TO_OLD = {new: old for old, news in NAMES.items() for new in news}
NAME = re.compile("|".join(re.escape(n) for n in sorted(NEW_TO_OLD, key=len, reverse=True)))
# Each allowed difference, tagged with its bug or decision id (plan.md). VOCABULARY maps HEAD's lines onto the new ones; BOTH rewrites
# both logs; DROP removes new lines HEAD has no counterpart for; MASKS: (id, test, regex) masked in both from that test's start to its RESULT.
VOCABULARY = [
    ("D1", r"^PROBE SCENARIO START ", "PROBE TEST START "),
    ("D1", r"^PROBE CHECK FAIL ", "PROBE ASSERT FAIL "),
    ("D1", r"^PROBE OBS u", "PROBE TRACE u"),
    ("D1", r"^PROBE ROWS ", "PROBE NUMBERS "),
    ("D1", r" PASS (\d+) checks", r" PASS \1 assertions"),
    ("D1", r"; unobserved: ", "; unreached: "),
    ("D1", r"; late Continue mid-scenario$", "; late Continue mid-test"),
    ("D1", r"scenario ceiling", "test limit"),
    ("D1", r"obsx ceiling", "step limit"),
    ("D1", r"<at> expected ", "precondition: "),  # assert.pre replaces error("expected ...")
    ("D4", r" INFO data only", " RECORDED"),
    ("bug 4", r"\bsplit \((\d+) Clicker uses\)", r"no split in \1 Clicker uses"),
]
BOTH = [
    ("D3", r"^(PROBE HARNESS START \d+) [\s\S]*", r"\1"),  # tags and mod data replace the mode (HEAD's %q keeps a newline)
    ("D3", r"^(PROBE RESULT .*?) SKIP .*", r"\1 SKIP"),  # the tags' skip reasons replace the mode's
]
DROP = [("D4", r"^PROBE SNAP ")]  # snapshot lines are new
MASKS = [
    # its look is built once, not by a step: G's frames and trace updates come one update sooner
    ("D6", "final G Jacob and Esau Clicker split", r"frame \d+|TRACE u\d+"),
]
ALLOW = VOCABULARY + BOTH + DROP + MASKS
WHERE = re.compile(r'(\[string "[^"]*"\]|\S+\.lua):\d+: ')  # an error's file:line moves with the code
# The stub's fakeTrack lists stored characters by pairs() over table keys, so entry order varies between runs of HEAD itself (untagged
# mode): a block of ENTRY lines is compared as a set.
ENTRY = re.compile(r"^(PROBE (?:TRACE u\d+ after .*?: )?ENTRY )\d+ ")
PASSED = re.compile(r"^PROBE RESULT (.*) PASS (\d+) assertions")
# Runs whose HEAD logs differ between runs of HEAD itself beyond ENTRY order: only their RESULT lines are compared. Untagged keys share a
# seed, so which stored character an entry follows depends on that address order (final M, 6 of 12 runs).
VOLATILE = {f"untagged ({legacy.FINAL_MODE})"}


def show(path):
    return subprocess.run(["git", "-C", REPO, "show", f"{BASE}:{path}"], capture_output=True, text=True, encoding="utf-8", check=True).stdout


def load_base(lua, _path):
    lua.execute(show("tests/stub.lua"))
    lua.execute(show("main.lua"))


def walk_base(g):
    """HEAD's fake user: a YOU: line names the pedestal to walk onto."""
    ask = g.HARNESS.ask
    return next(i for word, i in {"yum-heart": 45, "Esau Jr.": 703}.items() if word in ask) if ask and ask.startswith("YOU:") else None


def base_mode(mode):
    first, sep, rest = mode.partition("\r\n")
    return MODES[first] + sep + rest.replace(legacy.SPEC, "")


def normalise(log, side):
    out, masks = [], {}
    rewrites = [(re.compile(r), s) for _, r, s in (VOCABULARY if side == "base" else []) + BOTH]
    drops = [re.compile(r) for _, r in DROP] if side == "new" else []
    for line in log:
        line = WHERE.sub("<at> ", line)
        if any(d.match(line) for d in drops):
            continue
        if side == "new":
            line = NAME.sub(lambda m: NEW_TO_OLD[m.group(0)], line)
        for r, s in rewrites:
            line = r.sub(s, line)
        for _, test, regex in MASKS:
            if line.startswith(f"PROBE TEST START {test}"):
                masks[test] = re.compile(regex)
        for m in masks.values():
            line = m.sub("<allowed>", line)
        out.append(line)
        for test in [t for t in masks if line.startswith(f"PROBE RESULT {t} ")]:
            del masks[test]
    return sort_entries(out)


def assertion_sums(base, new):
    """Each old scenario whose PASS count differs from the sum of its new tests' counts (both logs normalised to old names)."""
    def counts(log):
        out = {}
        for m in filter(None, map(PASSED.match, log)):
            out[m[1]] = out.get(m[1], 0) + int(m[2])
        return out
    b, n = counts(base), counts(new)
    return [f"{old}: {b[old]} assertions, new {n.get(old, 0)}" for old in NAMES if old in b and b[old] != n.get(old, 0)]


def sort_entries(log):
    out, block, prefix = [], [], None
    for line in log + [""]:
        m = ENTRY.match(line)
        if m and m.group(1) == prefix:
            block.append(ENTRY.sub(r"\1", line))
            continue
        out += sorted(block)
        block, prefix = ([ENTRY.sub(r"\1", line)], m.group(1)) if m else ([], None)
        if not m and line:
            out.append(line)
    return out


def play(job):
    side, path, kwargs = job
    kwargs = {"mode": "tags all", **kwargs}
    if side == "base":
        kwargs.update(mode=base_mode(kwargs["mode"]), loader=load_base, walk=walk_base)
    return normalise(dry.run(path, **kwargs), side)


def first_difference(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return None if len(a) == len(b) else min(len(a), len(b))


def main(path):
    path = os.path.abspath(path)
    jobs = [(side, path, kwargs) for _, kwargs in CONFIGS for side in ("base", "new")]
    with ProcessPoolExecutor(max_workers=WORKERS) as pool:
        logs = list(pool.map(play, jobs))
    failed = 0
    for k, (name, _) in enumerate(CONFIGS):
        base, new = logs[2 * k], logs[2 * k + 1]
        sums = assertion_sums(base, new)
        if name in VOLATILE:
            base, new = ([s for s in log if s.startswith("PROBE RESULT ")] for log in (base, new))
        i = first_difference(base, new)
        if i is None and not sums:
            print(f"SAME {name}: {len(new)} lines")
            continue
        failed += 1
        if sums:
            print(f"DIFF {name} assertion counts: {'; '.join(sums)}")
        if i is not None:
            print(f"DIFF {name} at line {i + 1}:\n  base {base[i] if i < len(base) else '<end>'}\n  new  {new[i] if i < len(new) else '<end>'}")
    print(f"same_behaviour: {len(CONFIGS) - failed} of {len(CONFIGS)} runs the same, allowed {', '.join(sorted({a[0] for a in ALLOW}))}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main(sys.argv[1])
