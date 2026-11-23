"""tools/auto-continue.ps1 -DryRun on a fake mod data file: a new WAIT marker prints one plan, the same marker rewritten none, a marker
already there at start none, and nothing is sent."""
import os
import shutil
import subprocess
import tempfile
import time

import dry

WANT = {}  # no spec of its own
SCRIPT = os.path.join(dry.HERE, "..", "tools", "auto-continue.ps1")


def session(first, *later):
    """The tool's stdout lines while the mod data file holds `first` at its start, then each of `later`, a second apart."""
    with tempfile.TemporaryDirectory() as tmp:
        data = os.path.join(tmp, "save1.dat")

        def write(text):
            with open(data, "w", newline="") as f:
                f.write(text)
        write(first)
        p = subprocess.Popen([shutil.which("pwsh"), "-NoProfile", "-File", SCRIPT, "-DryRun", "-File", data, "-Minutes", "0.05"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        for text in later:
            time.sleep(1)
            write(text)
        out, err = p.communicate(timeout=60)
    lines = out.splitlines()
    assert p.returncode == 0 and not err, (p.returncode, out, err)
    assert not any(s.startswith(("sent ", "not sent", "PARTIAL")) for s in lines), lines
    return lines


def test_auto_continue(_path):
    lines = session("tags x", "tags x\nWAIT exit-continue 1", "tags x\r\nWAIT exit-continue 1")  # then the same marker rewritten
    assert lines.count("act on WAIT exit-continue 1") == 1 and sum(s.startswith("plan: ") for s in lines) == 1, lines
    print("PASS auto-continue.ps1 -DryRun: one plan for a new marker, none for it rewritten, nothing sent")
    lines = session("tags x\nWAIT exit-continue 2", "tags x\r\nWAIT exit-continue 2")  # the last session's marker
    assert not any(s.startswith(("act on ", "plan: ")) for s in lines), lines
    print("PASS auto-continue.ps1 -DryRun: a marker already there at start is not acted on")


TESTS = [test_auto_continue]
