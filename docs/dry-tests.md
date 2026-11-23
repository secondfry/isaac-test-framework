# Dry tests

Tests of the harness itself, outside the game. Commands run from the repo root.

## Running

    python -m venv .venv
    .venv\Scripts\pip install lupa
    .venv\Scripts\python -B -I tests\test_harness.py main.lua [test function ...]
    .venv\Scripts\python -B -I tests\test_report.py

`-I` ignores user site-packages, so install lupa into the virtual environment, not with `pip install --user`. Run one suite at a time. The full dry run takes about 8 minutes; name test functions to run a few. The tool tests need `pwsh`.

## What they cover

The dry run plays `main.lua` under lupa (Lua 5.3) against `tests\stub\`, a fake engine, input and ReHUD whose `shortcut:` comments say what it does not model, with a fake player who continues and walks. It checks:

- every test's verdict under each tags line it plays (`WANT` in `tests\test_<spec>.py`, plus each module's checks of its own lines);
- the runner (`test_runner.py`): tags, limits and worst cases, a late Continue or a new run instead, STUCK, fixture teardown and preconditions, which steps prompt;
- the presses' spends (`test_presses.py`);
- each invariant against its negative stub flag (`test_invariants.py`);
- `auto-continue.ps1 -DryRun` (`test_auto_continue.py`) and `vanilla-session.ps1` (`test_vanilla_session.py`), both needing `pwsh`;
- `report.py` on dry logs; `test_report.py` checks its verdicts, snapshots, log guard and JSON.

## WANT

A new test needs its expected verdict in `WANT` in `tests\test_<spec>.py`: the dry run fails on a planned test without one. Add checks of the test's own log lines to that module's `TESTS`.

Engine behaviour enters the stub, like the code, only once a played session has shown it.
