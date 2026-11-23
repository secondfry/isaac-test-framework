# rehud_test_harness

An in-game test mod for Binding of Isaac: Repentance+. On the first new run after launch it plays its tests by itself, one step per game update, and logs `PROBE` lines to `log.txt`; `tools\report.py` reads them back. Tests tagged `rehud` read ReHUD through its `ReHUD.dbg` hook (ReHUD cf965b0 or later); the `vanilla` ones need no other mod.

`main.lua` only wires the specs to the runner and the game's callbacks; `scripts\` holds the runner and the shared steps, fixtures and assertions; `specs\<spec>.lua` one spec's tests and `specs\<spec>.snap.txt` its snapshots; `tests\` the offline tests; `tools\` the report reader and session helpers.

## Install

With the game closed, from the workspace root (`<game>` = `C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth`):

    robocopy isaac-test-harness "<game>\mods\rehud_test_harness" main.lua metadata.xml
    robocopy isaac-test-harness\scripts "<game>\mods\rehud_test_harness\scripts" *.lua
    robocopy isaac-test-harness\specs "<game>\mods\rehud_test_harness\specs" *.lua

Never `tests\`, `tools\` or `*.snap.txt`. Delete a file there that the repo no longer has. Delete `disable.it` in that folder to run the harness; put it back after the session.

## A session

1. Game closed: write the tags line (below), install, delete `disable.it` in `mods\rehud_test_harness`, then `pwsh -File isaac-test-harness\tools\vanilla-session.ps1 -Start`.
2. Launch, load save slot 1, start a new run: the session starts there (a Continue first only logs `HARNESS idle`).
3. Hands off, except the manual steps the screen asks for.
4. At `HARNESS: DONE` (or a game over outside `tags revive`), exit to the menu (that flushes `log.txt`) and copy `log.txt`.
5. Game closed: `vanilla-session.ps1 -End`, then steps 2-4 again with the same tags line and the user's play mod set.
6. Read each copy with `tools\report.py` (Results), the vanilla one first.
7. Game closed: put `disable.it` back in `mods\rehud_test_harness`.

A game start the harness did not ask for (hold-R, a new run) fails the current test. Unlocked on save slot 1: Cain, Eve, Samson, Lazarus, Lilith, and every recon character (Isaac, Tainted Isaac, Jacob and Esau, The Forgotten, Tainted Forgotten, Tainted Lazarus, Tainted Jacob; session 2), Eden (obsyb1). A test of a locked character fails as a precondition (`cannot be started, locked on this save?`) or, in a snapshot test, ends at its restart (`character locked?`).

## Picking tests: tags

Line 1 of `data\rehud_test_harness\save<slot>.dat` in the game folder (the vanilla `SaveData` file of the save slot played), written before launch:

- `tags a,b` (commas or spaces): every test that has one of the tags; `tags all`: every test but the `opt-in` ones.
- Empty line, or no file: every test but the `opt-in` ones and the `exit-continue` ones not tagged `new`.
- An `opt-in` test plays only when one of its other tags is named.
- `--update-snapshots` anywhere on the line lets `report.py` replace the snapshots that differ.

`HARNESS START` logs the line; a skipped test logs `RESULT <spec> > <test> SKIP <why> (tags '<line>')` and takes no update. The lines below line 1 are the harness's own (`WAIT`, `STUCK`) and never change the tags.

The tags: one per spec (`hello`, `engine`, `continue`, `characters`, `esau_jr`, `base_change`, `item_copies`, `regressions`, `revive`); `vanilla` (no ReHUD needed) or `rehud`; `exit-continue` (asks for an Exit & Continue; these tests play last, back to back); `walk` (asks for pedestal walks); `new` (an `exit-continue` test the empty line still plays: set it until the test has passed in game, and again whenever its steps or assertions change); `opt-in`; `rehud-2.8` (ReHUD 2.8's final build); `seed` (what the seed command does); `recon` (one recon test per character: Isaac, Tainted Isaac, Jacob and Esau, The Forgotten, Tainted Forgotten, Tainted Lazarus, Tainted Jacob; tagged `vanilla` too, as they read no ReHUD); `stored-character` (snapshot tests of a stored Esau Jr. or Flip character through Clicker, ChangePlayerType and losing Esau Jr.); `drop` (asks for a drop press).

What each tags line plays, from the runner's plan (`dry.plan`): the tests, the user's Exit & Continues and pedestal walks, and the worst case: the updates when every test with a limit runs to it (`HARNESS DONE` included; 30 updates a second; menu time for the Continues not counted). A test without a limit has no cap of its own: each of its waits gives up after at most 600 updates, an Exit & Continue after 9000, except `revive > restart from the death certificate`, which waits for its new game (Manual steps).

| Tags line | Tests | Exit & Continues | Walks | Worst case, tests with a limit | Tests without a limit |
|---|---|---|---|---|---|
| (empty) | 76 | 3 | 2 | 17841 updates (9.9 min) | 33 |
| `tags all` | 108 | 35 | 2 | 49841 (27.7 min) | 33 |
| `base_change` | 15 | 7 | 0 | 9531 (5.3 min) | 3 |
| `characters` | 18 | 8 | 0 | 10776 (6.0 min) | 3 |
| `continue` | 13 | 13 | 0 | 10001 (5.6 min) | 3 |
| `drop` | 3 | 0 | 0 | 1336 (0.7 min) | 0 |
| `engine` | 5 | 0 | 0 | - | 5 |
| `esau_jr` | 46 | 7 | 2 | 19041 (10.6 min) | 13 |
| `exit-continue` | 35 | 35 | 0 | 32001 (17.8 min) | 3 |
| `hello` | 3 | 0 | 0 | 446 (0.2 min) | 2 |
| `item_copies` | 4 | 0 | 0 | - | 4 |
| `new` | 3 | 3 | 0 | - | 3 |
| `recon` | 31 | 28 | 0 | 29336 (16.3 min) | 0 |
| `regressions` | 6 | 0 | 0 | 1251 (0.7 min) | 0 |
| `rehud` | 76 | 7 | 2 | 21261 (11.8 min) | 31 |
| `rehud-2.8` | 19 | 1 | 2 | 8026 (4.5 min) | 0 |
| `revive` | 6 | 0 | 0 | 3911 (2.2 min) | 1 |
| `seed` | 1 | 0 | 0 | 446 (0.2 min) | 0 |
| `stored-character` | 12 | 0 | 0 | 5341 (3.0 min) | 0 |
| `vanilla` | 34 | 28 | 0 | 29781 (16.5 min) | 2 |
| `walk` | 1 | 0 | 2 | 1101 (0.6 min) | 0 |

`revive` (five tests, one per source on Lazarus, then one restart from the death certificate) is opt-in and plays with `tags revive`; each source test ends at its source's revive. The last test, `restart from the death certificate`, kills Isaac on the fixed seed, sends `restart` once he has been dead 120 updates or 240 render frames (whether either runs on the certificate is unobserved; session 3a suggests updates stop) and logs whether a new game came; 600 updates or 600 render frames later without one it draws `HARNESS: press Space`, if renders run there.

## Manual steps

- Exit & Continue: the screen shows `exit to the menu and Continue now` on its own line; exit to the menu and pick Continue. A snapshot test gives up after 600 updates of play, a test with assertions after 9000. A new run instead fails a test with assertions (`a new run started, not a Continue`) and ends a snapshot test. A Continue after its step gave up lands in the next test: logged `late Continue, ignored` and noted `; late Continue mid-test` on that test's `RESULT`.
- Automatic Exit & Continue (opt-in; watch its first run, as its key path is unconfirmed): `pwsh -File isaac-test-harness\tools\auto-continue.ps1`, started before launch, presses the keys into the game on each new `WAIT exit-continue <n>` line the harness writes into the tags file (`-DryRun` prints the plan only). On `waiting for isaac-ng in front`, bring the game to the front and press nothing; it sends as soon as it is in front. Only `not sent: no isaac-ng window` and `PARTIAL` need the Exit & Continue by hand, within the step's wait (600 / 9000 updates).
- Pedestal walks (`walk`): `YOU: walk onto the yum-heart pedestal`, then `YOU: step off, then walk back onto the Esau Jr. pedestal`; 450 updates each.
- Game over under `tags revive`: the certificate test's game over is expected, so wait. Press Space when the screen says `HARNESS: press Space`, or when no new game has come 30 s after the certificate shows (the harness may not run there); the test ends at that new game. A source test reaching game over means its source gave no revive: press Space, and that test FAILs `unexpected game start`.

A manual step never logs `STUCK`. Any other wait still running after 60 updates logs `STUCK` once and writes `STUCK <n> <test> | <step>` as the tags file's last line, the latest only, which `stuck-shots.ps1` reads; `pwsh -File isaac-test-harness\tools\stuck-shots.ps1 -Out <folder>`, started before launch, screenshots the game for each (it reads `save1.dat`).

## Results

Copy `log.txt` right after the session, then from the workspace root:

    .venv\Scripts\python -B -I isaac-test-harness\tools\report.py "<log copy>" [--out DIR] [--specs DIR] [--timeline TEST]

Each test ends with one `RESULT <spec> > <test>`: `PASS <n> assertions`; `FAIL <why>` (each failed assertion also logs `ASSERT FAIL`; `FAIL precondition: <why>` when its fixture never got ready); `RECORDED` (a snapshot test without assertions); or `SKIP`. `; unreached: <notes>` lists what did not run: a step that never happened, a test limit (`test limit <n> updates in <step>`), the steps skipped after either (`steps <step> to <step> skipped`), a step skipped by its guard (`skipped: <why>`) and a spec's own notes; `; late Continue mid-test` a late Continue.

`report.py` prints each test with its `INFO` lines, every failed assertion with the lines before it, snapshot differences, the Continues, errors outside its noise list and log guard hits (a mod update or Lua reset mid-session marks every later test `environment changed`), then one verdict line: `ALL PASS`, or `NEEDS ANALYSIS: <reasons>` (a FAIL, an unreached step that chance does not explain, a late Continue, a failed teardown, other errors, missing results or `HARNESS DONE`, Continues asked and resumed differing). Only `NEEDS ANALYSIS` needs an analysis; the exit code is 0 only on `ALL PASS`. It writes `report.json` and, for each failed, new or changed test, its trace `traces\<spec> - <test>.txt` (its lines, `TEST START` to `RESULT`) into `--out` (default: the log's folder). `--timeline <test>` also prints that test's `TRACE` lines as a timeline, characters labelled A, B, C... by GetPtrHash, with a summary per character.

Other lines worth knowing, all `INFO` unless named: `VERDICT <press> index <i> <before> -> <after> new|returned|moved from <j>|unchanged | <lineup> -> <lineup>` (who holds the pressed index after a press, characters labelled by character record (characters.lua), else GetPtrHash), `TIMING` (the pressed index's occupant each frame after an Esau Jr. press), `IDS` (each GetPlayer entry's seeds, Index, GetPtrHash and twins), `NUMBERS` (each character's ReHUD row per look) and `TRACE` (a snapshot test's engine and ReHUD state on each update it changed).

## Snapshots and recon tests

A snapshot test logs `SNAP <spec> > <test> | <n> <step> / <key> = <value>` after each step: game state only (lineup and twins labelled by character record (characters.lua), else GetPtrHash, types, seed labels, items, charges, trinkets, cards, and Esau Jr. TIMING frames relative to their first), never ReHUD's. A stored character is invisible to Lua, so snapshots show only the characters in play. `report.py` keeps them in `specs\<spec>.snap.txt`, one `## <test>` section each:

- No section yet (a recon test): the first played session in which the test passes writes it.
- A section: compared key by key; a difference FAILs the test (`snapshot differs in <n> keys`) showing both values, and only a session whose tags line had `--update-snapshots` replaces it.
- Never written for a failed test, nor for a test with an unreached step, nor from a log without the engine's version line (a dry log).

Report the vanilla log first: the first log reported writes a missing section; the play-set log then compares, and a difference points at a mod.

Commit the `.snap.txt` files `report.py` writes; never deploy them.

## Vanilla sessions

`pwsh -File isaac-test-harness\tools\vanilla-session.ps1 -Start`, with the game closed, writes `disable.it` into every other mod folder that has none (listed in the gitignored `.vanilla-session.txt`); `-End` after the session deletes just those. Every session runs twice with the same tags line: vanilla (this script) and with the user's play mod set.

## Offline tests

From the workspace root, one suite at a time:

    .venv\Scripts\python -B -I isaac-test-harness\tests\test_harness.py isaac-test-harness\main.lua [test function ...]
    .venv\Scripts\python -B -I isaac-test-harness\tests\test_report.py

The dry run (about 8 minutes; name test functions to run a few) plays `main.lua` under lupa (Lua 5.3) against `tests\stub\`, a fake engine, input and ReHUD whose `shortcut:` comments say what it does not model, with a fake user who continues and walks. It checks every test's verdict under each tags line it plays (`WANT` in `tests\test_<spec>.py`, plus each module's checks of its own lines), the runner (`test_runner.py`: tags, limits and worst cases, a late Continue or a new run instead, STUCK, fixture teardown and preconditions, which steps prompt), the presses' spends (`test_presses.py`), each invariant against its negative stub flag (`test_invariants.py`), `auto-continue.ps1 -DryRun` (`test_auto_continue.py`) and `report.py` on dry logs. `test_report.py` checks `report.py`'s verdicts, snapshots, log guard and JSON.

## Writing tests

- A spec: `specs\<name>.lua` returns `{ name = "<name>", tests = { ... } }`; add the name to `SPECS` in `main.lua` (play order; `exit-continue` tests move to the end).
- A test: `name`, `tags`, `fixture`, `steps`; optional `limit` (updates: a test with assertions FAILs there; a snapshot test at its limit ends RECORDED with a `test limit` note, writes no snapshot, and the report says NEEDS ANALYSIS), `snapshot = true`, `onStepError = "skip"` or `"end"` (a step that errors or passes its own `limit` is logged as never happened, then skipped, or the test ends), `onUpdate`, `onRender` (each render frame while the test plays, which may run where updates stop), `traceUpdates`. Steps may nest lists; a step is `function(ctx)` returning `"again"` to run again next update, or `{ label, run, limit, when, manual }`.
- A fixture: `{ name, setup = { steps }, done = function(ctx) return ok, why end, teardown }`. The setup runs, `done` is polled for up to 120 updates (still false: `FAIL precondition: <why>`), then the steps; `teardown` runs exactly once however the test ends. Shared ones in `scripts\fixtures.lua`: `fixture`, `owns`, `freshRun` (a restart on the fixed seed `9SZM 3P3S`, after one `seed` command when the run is on another; a restart off the fixed seed fails the test; `newGame` logs each restart's start seed, type and frame, and every fixture logs `start seed` when done), `holdingJr`, `jacobAndEsau`, `character` with `RECON_CHARACTERS`, and the `TLAZ_*` setups.
- Shared steps: `scripts\snapshot.lua` `test(name, tags, fixture, steps, opts)` builds a snapshot test from labelled steps (`opts.strict`: 120-update steps, a 445-update test) and `perCharacter` one recon test per recon character; `wait.act` and `wait.condition` wait for an effect; `press.lua` makes real presses (`flip`, `esauJr`, `clicker`, ...): a button press through `MC_INPUT_ACTION` that passes only with a new character and the spent charge or card, a stored presser's spend (Esau Jr., Flip without Birthright) read on its own entity before the engine stores it (`..\lua-api-notes.md`); `manual.lua` holds the manual steps; `settle.look` and `lookC` wait for ReHUD to settle, then assert, each look also the invariants (ReHUD's entries against the engine's counts, no duplicates, no phantom stored forms, no `left` entries, no floor later than the current one; `lookC` one row per character too); `assert.lua` has the assertions (`expect`, `expectCount`, ..., `pre` for a precondition).
- Tag it with its spec, `rehud` or `vanilla`, `exit-continue` if it asks for an Exit & Continue (and `new` until it has passed in game), `walk` if it asks for a walk.
- Add its verdict to `WANT` in `tests\test_<spec>.py` (the dry run fails on a planned test without one) and checks of its own lines to that module's `TESTS`.
- Engine behaviour starts as a recon test, without assertions on it, until a played session has shown it (`..\AGENTS.md`).
