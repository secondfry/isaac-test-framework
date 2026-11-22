"""tools/auto-continue.ps1 -DryRun on a fake mod data file: a new WAIT marker prints one plan, the same marker rewritten none, and
nothing is sent."""
import os
import shutil
import subprocess
import tempfile
import time

import dry

WANT = {}  # no spec of its own
SCRIPT = os.path.join(dry.HERE, "..", "tools", "auto-continue.ps1")


def test_auto_continue(_path):
    with tempfile.TemporaryDirectory() as tmp:
        data = os.path.join(tmp, "save1.dat")

        def write(text):
            with open(data, "w", newline="") as f:
                f.write(text)
        write("tags x")
        p = subprocess.Popen([shutil.which("pwsh"), "-NoProfile", "-File", SCRIPT, "-DryRun", "-File", data, "-Minutes", "0.05"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(1)
        write("tags x\nWAIT exit-continue 1")
        time.sleep(1)
        write("tags x\r\nWAIT exit-continue 1")  # the same marker rewritten
        out, err = p.communicate(timeout=60)
    lines = out.splitlines()
    assert p.returncode == 0 and not err, (p.returncode, out, err)
    assert lines.count("act on WAIT exit-continue 1") == 1 and sum(s.startswith("plan: ") for s in lines) == 1, lines
    assert not any(s.startswith(("sent ", "not sent")) for s in lines), lines
    print("PASS auto-continue.ps1 -DryRun: one plan for a new marker, none for it rewritten, nothing sent")


TESTS = [test_auto_continue]
