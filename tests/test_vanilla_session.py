"""tools/vanilla-session.ps1 on a fake mods folder: -Start disables every mod but the harness, twice is the same as once, and -End,
after an interrupted -Start too, restores exactly the folders' previous disable.it files."""
import os
import shutil
import subprocess
import tempfile

import dry

WANT = {}  # no spec of its own
SCRIPT = os.path.join(dry.HERE, "..", "tools", "vanilla-session.ps1")
FOLDERS = ["isaac_test_framework", "[REP+] reHUD [Forked]_3843066104", "plain mod", "off by the user"]


def disabled(mods):
    return {d: open(os.path.join(mods, d, "disable.it")).read() for d in FOLDERS if os.path.exists(os.path.join(mods, d, "disable.it"))}


def test_vanilla_session(_path):
    with tempfile.TemporaryDirectory() as tmp:
        mods, state = os.path.join(tmp, "mods"), os.path.join(tmp, "state.txt")
        for d in FOLDERS:
            os.makedirs(os.path.join(mods, d))
        with open(os.path.join(mods, FOLDERS[3], "disable.it"), "w") as f:
            f.write("the user's")
        before = disabled(mods)

        def session(switch):
            p = subprocess.run([shutil.which("pwsh"), "-NoProfile", "-File", SCRIPT, switch, "-Mods", mods, "-State", state],
                               capture_output=True, text=True)
            assert p.returncode == 0 and not p.stderr, (switch, p.stdout, p.stderr)
        session("-Start")
        assert disabled(mods) == {**before, FOLDERS[1]: "", FOLDERS[2]: ""}, disabled(mods)
        session("-Start")
        assert disabled(mods) == {**before, FOLDERS[1]: "", FOLDERS[2]: ""} and len(open(state).read().splitlines()) == 2, open(state).read()
        os.remove(os.path.join(mods, FOLDERS[2], "disable.it"))  # recorded, then interrupted before it was written
        session("-End")
        assert disabled(mods) == before and not os.path.exists(state), disabled(mods)
        session("-End")
    print("PASS vanilla-session.ps1: harness kept, run twice, interrupted -Start, previous state restored")


TESTS = [test_vanilla_session]
