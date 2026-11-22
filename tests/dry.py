"""The dry run: main.lua played against the stub in tests/stub/, and the helpers every test module reads its log with."""
import os
import re
import subprocess
import sys
import tempfile
from lupa.lua53 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
REPORT = os.path.join(HERE, "..", "tools", "report.py")
STUB_FILES = ["api.lua", "players.lua", "characters.lua", "input.lua", "console.lua", "rehud.lua"]  # load order: rehud.lua registers its update first
RESULT = re.compile(r"^PROBE RESULT (.+?) (PASS \d+ assertions|FAIL |RECORDED|SKIP )")


def load(lua, path, specs=None):
    """The stub, the game's include() over the mod folder (each call runs the file again), then the mod's main.lua at `path`. `specs`
    maps a spec name to Lua code returning that spec, played in place of the file of that name."""
    for name in STUB_FILES:
        with open(os.path.join(HERE, "stub", name), encoding="utf-8") as f:
            lua.execute(f.read())
    root = os.path.dirname(os.path.abspath(path)).replace("\\", "/") + "/"
    lua.execute("local root = ... function include(name) return dofile(root .. name:gsub('%.', '/') .. '.lua') end", root)
    for name, code in (specs or {}).items():
        lua.execute("local name, code = ... local real = include "
                    "function include(n) if n == 'specs.' .. name then return load(code)() end return real(n) end", name, code)
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())


def walk_target(g):
    """The pedestal item a started manual walk step asks the user to walk onto, or None."""
    m = g.HARNESS.session.manual
    return m.target if m and m.kind == "walk" else None


def run(path, mode="tags all", on_exit="continue", render_every=1, continue_after=0, loader=load, walk=walk_target, **flags):
    """Plays the whole session; `mode` is the mod data; on_exit is what the fake user does when asked to exit and Continue: "continue" or
    "new"; continue_after delays that answer by this many updates. A manual walk is answered by walking player 0 onto the pedestal
    `walk(g)` names. `loader(lua, path)` loads the stub and the mod."""
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
        target = walk(g)
        if target:
            g.fakeUserWalk(target)
        g.engineInput()
        g.fire(1)
        if update % render_every == 0:
            g.fire(2)
        log = g.LOG
        size = len(log)
        if any("ACTION exit to the menu and Continue now by type" in log[i] for i in range(seen + 1, size + 1)):
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
    """Each RESULT's verdict by full test name ("<spec> > <test>"), in play order."""
    out = {}
    for s in log:
        m = RESULT.match(s)
        if m:
            assert m[1] not in out, f"two RESULTs for {m[1]}"
            out[m[1]] = s[len("PROBE RESULT ") + len(m[1]) + 1:]
    return out


def check_finished(log, label, names):
    """The RESULTs of a session that ended with HARNESS DONE, no HARNESS ERROR, one RESULT per test in `names`, in that order."""
    assert log[-1] == "PROBE HARNESS DONE", f"{label}: run did not finish"
    assert not any("HARNESS ERROR" in s for s in log), f"{label}: harness error"
    got = results(log)
    assert list(got) == names, f"{label}: RESULTs {list(got)}"
    return got


def wanted(mode, tests):
    """Each test's verdict under the tags line `mode` when nothing fails, as the runner picks: `tests` maps a name to (verdict, its tags)."""
    line = mode.splitlines()[0].strip() if mode else ""
    tags = line[len("tags"):].replace(",", " ").split() if line.startswith("tags") else []
    out = {}
    for name, (want, own) in tests.items():
        opt_in = "opt-in" in own
        if not tags:
            skip = "opt-in" if opt_in else "exit-continue and not new" if "exit-continue" in own and "new" not in own else None
        elif any((t == "all" and not opt_in) or (t != "opt-in" and t in own) for t in tags):
            skip = None
        else:
            skip = "opt-in" if opt_in else "not tagged"
        out[name] = f"SKIP {skip} (tags '{line}')" if skip else want
    return out


def expect_results(got, label, want, why=None, names=()):
    """Every test in `names` FAILs naming `why` (or one of a tuple); every other test in `want` ends as it says."""
    for name in want:
        if name in names:
            assert got[name].startswith("FAIL") and any(w in got[name] for w in (why if isinstance(why, tuple) else (why,))), f"{label}: {name}: {got[name]}"
        else:
            assert got[name] == want[name], f"{label}: {name}: {got[name]}"


def segment(log, name):
    """The lines of test `name` (its full name), TEST START to RESULT."""
    i = log.index(f"PROBE TEST START {name}")
    return log[i:next(k for k in range(i, len(log)) if log[k].startswith(f"PROBE RESULT {name} ")) + 1]


def report(log):
    """tools/report.py on these lines: (exit code, verdict line). Its traces, report.json and snapshot folder are a temp folder's, so a dry
    log is never compared with a played session's snapshots."""
    with tempfile.TemporaryDirectory() as out:
        path = os.path.join(out, "log.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(log) + "\n")
        p = subprocess.run([sys.executable, "-B", "-I", REPORT, path, "--out", out, "--specs", out], capture_output=True, text=True)
    assert not p.stderr, p.stderr
    return p.returncode, p.stdout.splitlines()[-1]
