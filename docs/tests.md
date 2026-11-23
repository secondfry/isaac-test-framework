# Writing tests

How a spec, a test, its fixture and its steps fit together. The building blocks themselves: [helpers.md](helpers.md). Commands run from the repo root.

## Repository layout

- `main.lua`: only wires the specs to the runner and the runner to the game's callbacks. `SPECS` sets the play order (`exit-continue` tests move to the end).
- `scripts\`: the runner and the shared steps, fixtures and assertions ([helpers.md](helpers.md)).
- `specs\<spec>.lua`: one spec's tests; `specs\<spec>.snap.txt`: its snapshots, written by `report.py`.
- `tests\`: the dry tests; `tests\stub\` the fake engine ([dry-tests.md](dry-tests.md)).
- `tools\`: `report.py`, `vanilla-session.ps1`, `auto-continue.ps1`, `stuck-shots.ps1`.
- `docs\engine-facts.md`: the engine behaviour the code relies on, each fact with the session that showed it.

Labels in comments ("session 3c", "run 8", "obsyb1") name in-game sessions; [engine-facts.md](engine-facts.md) lists them.

## Specs

A spec is `specs\<name>.lua` returning `{ name = "<name>", tests = { ... } }`; add its name to `SPECS` in `main.lua`. Tag each test with its spec's name ([tags.md](tags.md)), add its verdict to `WANT` in `tests\test_<spec>.py` and checks of its own lines to that module's `TESTS` ([dry-tests.md](dry-tests.md)).

## Tests

A test: `name`, `tags`, `fixture`, `steps`; optional:

- `limit` (updates): a test with assertions FAILs there; a snapshot test at its limit ends RECORDED with a `test limit` note, writes no snapshot, and the report says NEEDS ANALYSIS.
- `snapshot = true`.
- `onStepError = "skip"` or `"end"`: a table step that errors or passes its own `limit` is logged as never happened, then skipped, or the test ends.
- `onUpdate(ctx)`: runs first on every update the test plays (`record.watchLineup`, `record.innerWatch`); `onRender(ctx)`, each render frame while the test plays, also where updates stop (session 3c); it may return one line, drawn last.
- `traceUpdates`: log a `TRACE` line on each update the state changed.
- `leftOk`: the invariants allow ReHUD entries marked left.

`snapshot.test` sets `snapshot`, `traceUpdates`, `onStepError` and, when strict, `limit` for you.

## Steps

Steps run in order, one at a time, each for as many updates as it asks. Steps may nest lists. A step is:

- `function(ctx)`: returning `"again"` runs it again next update; anything else moves on. Most helpers return such a function.
- `{ label, run, limit, when, manual }`: `run` is the function. `label` names it in `RESULT` notes and `TRACE` lines, `limit` caps its updates, and `when(ctx)` false skips it; the runner honours these three only in a test with `onStepError`. `manual` makes the runner show the step's prompt on screen (the `manual.lua` steps carry it).

An error in a step FAILs the test (`error in step <n>: <why>`), or under `onStepError` makes it never happen; `assert.pre` FAILs it as `precondition: <why>`; `runner.abort` FAILs it past any policy.

## Fixtures

A fixture: `{ name, setup = { steps }, done = function(ctx) return ok, why end, teardown }`. The setup runs, `done` is polled for up to 120 updates (still false: `FAIL precondition: <why>`), then the steps; `teardown` runs exactly once however the test ends. Shared ones are in `scripts\fixtures.lua` ([helpers.md](helpers.md#fixtureslua)); `freshRun` restarts on the fixed seed `9SZM 3P3S`, after one `seed` command when the run is on another, and a restart off the fixed seed fails the test. Each restart logs its start seed, type and frame, and every fixture logs `start seed` when done.

## Limits

Updates run 30 a second. A test without `limit` has no cap of its own: each of its waits gives up after at most 600 updates (`wait.TIMEOUT`), an Exit & Continue after 9000. Each wait's own ceiling is in [helpers.md](helpers.md). A strict snapshot test caps each step at 120 updates and the test at 445 (twelve such tests fit three minutes) unless given another limit. What a tags line costs in the worst case: [tags.md](tags.md#what-each-line-plays).

## Recon and snapshot tests

- A test **with assertions** (`assert.lua`) passes or fails on them.
- A **snapshot test** (`snapshot.test`) records the game state after each step as `SNAP` lines, never ReHUD's; `report.py` stores the first passing session's values and compares later sessions against them ([results.md](results.md#snapshots)). A test may also record single values with `record.snap`.
- A snapshot test whose values are not stored yet is a **recon test**: it only records. Engine behaviour starts as a recon test, with no assertions on it, until a played session has shown it; then record it in [engine-facts.md](engine-facts.md) with that session. Engine behaviour enters the dry tests' stub, like the code, only on the same terms.

## Testing ReHUD, or your own mod

The `rehud` tests read ReHUD through its `ReHUD.dbg` debug hook (ReHUD a97424c or later, on the ReHUD fork's branch `feat/multiple-copies`, https://github.com/secondfry/ReHUD PR #4), only through `scripts\rehud.lua`. Without the hook each `rehud` test with assertions ends `SKIP ReHUD.dbg not loaded`; the `rehud` snapshot tests, which record game state only, still play. For your own mod, expose its state in a global table and read it from the steps the same way.
