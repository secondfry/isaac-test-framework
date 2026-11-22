"""The refactored harness against HEAD df8ba84: each dry run played by both, logs compared line by line after normalising.
Run: python -B -I tests/same_behaviour.py main.lua. Temporary: deleted once the refactor is done (plan S6)."""
import os
import re
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_harness as dry  # noqa: E402

BASE = "df8ba84"
REPO = os.path.join(dry.HERE, "..")
# Every run the dry test makes: (name, run keyword arguments).
CONFIGS = [
    ("regression", {}),
    ("tlazRoll 29", {"tlazRoll": 29}),
    ("default", {"mode": ""}),
    ("final", {"mode": dry.FINAL_MODE}),
    ("final worst", {"mode": dry.FINAL_MODE, "render_every": 10 ** 6}),
    ("only obs", {"mode": "only obs\r\nSTUCK 3 obs mirror | settle"}),
    ("obsx veto", {"mode": "only obsx", "ignoreFirstVetoPress": True, "birthrightDeadFirst": True}),
    ("obsx no effect", {"mode": "only obsx", "ignoreClickerEffect": True}),
    ("obsx no restart", {"mode": "only obsx", "ignoreRestart": True}),
    ("obsx slow render", {"mode": "only obsx", "render_every": 200}),
    ("obsy a worst", {"mode": "only obsy a", "render_every": 10 ** 6}),
    ("obsy b worst", {"mode": "only obsy b", "render_every": 10 ** 6}),
    ("new run", {"on_exit": "new"}),
    ("late Continue", {"mode": "only obsy b", "continue_after": 615}),
    ("same seed", {"mode": "only obsy b continue after B loses Esau Jr.", "jrSameSeed": True}),
    ("same seed once", {"mode": "only obsy b continue with A stored", "jrSameSeed": 1}),
    ("restart ignored", {"ignoreRestart": True}),
    ("press ignored", {"ignorePress": True}),
    ("no spend", {"noSpend": True}),
    ("wrong floor", {"wrongFloor": True}),
    *((f"{flag} ({mode})", {"mode": mode, flag: True}) for flag, mode, _, _ in dry.INVARIANT_MODES),
]
# Each allowed difference, tagged with its bug or decision id (plan.md): (id, the test it starts in, a regex masked in both logs from
# that test's start on).
ALLOW = []
WHERE = re.compile(r'(\[string "[^"]*"\]|\S+\.lua):\d+: ')  # an error's file:line moves with the code
# The stub's fakeTrack lists stored characters by pairs() over table keys, so entry order varies between runs of HEAD itself (untagged
# mode): a block of ENTRY lines is compared as a set.
ENTRY = re.compile(r"^(PROBE (?:OBS u\d+ after .*?: )?ENTRY )\d+ ")
# Runs whose HEAD logs differ between runs of HEAD itself beyond ENTRY order: only their RESULT lines are compared. Untagged keys share a
# seed, so which stored character an entry follows depends on that address order (final M, 6 of 12 runs).
VOLATILE = {f"untagged ({dry.FINAL_MODE})"}


def show(path):
    return subprocess.run(["git", "-C", REPO, "show", f"{BASE}:{path}"], capture_output=True, text=True, encoding="utf-8", check=True).stdout


def load_base(lua, _path):
    lua.execute(show("tests/stub.lua"))
    lua.execute(show("main.lua"))


def normalise(log):
    out, masks = [], []
    for line in log:
        for _, test, regex in ALLOW:
            if line.startswith(f"PROBE SCENARIO START {test}"):
                masks.append(re.compile(regex))
        line = WHERE.sub("<at> ", line)
        for m in masks:
            line = m.sub("<allowed>", line)
        out.append(line)
    return sort_entries(out)


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
    return normalise(dry.run(path, loader=load_base if side == "base" else dry.load, **kwargs))


def first_difference(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return None if len(a) == len(b) else min(len(a), len(b))


def main(path):
    path = os.path.abspath(path)
    jobs = [(side, path, kwargs) for _, kwargs in CONFIGS for side in ("base", "new")]
    with ProcessPoolExecutor() as pool:
        logs = list(pool.map(play, jobs))
    failed = 0
    for k, (name, _) in enumerate(CONFIGS):
        base, new = logs[2 * k], logs[2 * k + 1]
        if name in VOLATILE:
            base, new = ([s for s in log if s.startswith("PROBE RESULT ")] for log in (base, new))
        i = first_difference(base, new)
        if i is None:
            print(f"SAME {name}: {len(new)} lines")
            continue
        failed += 1
        print(f"DIFF {name} at line {i + 1}:\n  base {base[i] if i < len(base) else '<end>'}\n  new  {new[i] if i < len(new) else '<end>'}")
    print(f"same_behaviour: {len(CONFIGS) - failed} of {len(CONFIGS)} runs the same, allowed {', '.join(a[0] for a in ALLOW) or 'nothing'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main(sys.argv[1])
