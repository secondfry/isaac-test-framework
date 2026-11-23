# Isaac Test Framework reference

Details most readers of the [README](../README.md) do not need. Commands run from the repo root.

## Repository layout

- `main.lua`: only wires the specs to the runner and the runner to the game's callbacks. `SPECS` sets the play order (`exit-continue` tests move to the end).
- `scripts\`: the runner and the shared steps, fixtures and assertions.
- `specs\<spec>.lua`: one spec's tests; `specs\<spec>.snap.txt`: its snapshots, written by `report.py`.
- `tests\`: the dry tests; `tests\stub\` the fake engine.
- `tools\`: `report.py`, `vanilla-session.ps1`, `auto-continue.ps1`, `stuck-shots.ps1`.
- `docs\engine-facts.md`: the engine behaviour the code relies on, each fact with the session that showed it.

Labels in comments ("session 3c", "run 8", "obsyb1") name in-game sessions; `docs\engine-facts.md` lists them.

The `rehud` tests read ReHUD through its `ReHUD.dbg` debug hook (ReHUD cf965b0 or later, on the ReHUD fork's branch `feat/multiple-copies`, https://github.com/secondfry/ReHUD PR #4). Without the hook each `rehud` test with assertions ends `SKIP ReHUD.dbg not loaded`; the `rehud` snapshot tests, which record game state only, still play.

## Tags

Line 1 of `data\isaac_test_framework\save<slot>.dat` in the game folder (the vanilla `SaveData` file of the save slot played), written before launch:

- `tags a,b` (commas or spaces): every test that has one of the tags; `tags all`: every test but the `opt-in` ones.
- Empty line, or no file: every test but the `opt-in` ones and the `exit-continue` ones not tagged `new`.
- An `opt-in` test plays only when one of its other tags is named.
- `--update-snapshots` anywhere on the line lets `report.py` replace the snapshots that differ.

`HARNESS START` logs the line; a skipped test logs `RESULT <spec> > <test> SKIP <why> (tags '<line>')` and takes no update. The lines below line 1 are the harness's own (`WAIT`, `STUCK`) and never change the tags; `HARNESS START` drops the last session's.

The tags:

- One per spec: `hello`, `engine`, `continue`, `characters`, `esau_jr`, `base_change`, `item_copies`, `regressions`, `revive`.
- `vanilla` (no ReHUD needed) or `rehud` (reads ReHUD).
- `exit-continue`: asks for an Exit & Continue; these tests play last, back to back.
- `walk`: asks for pedestal walks. `drop`: asks for a drop press.
- `new`: an `exit-continue` test the empty line still plays. Set it until the test has passed in game, and again whenever its steps or assertions change.
- `opt-in`.
- `rehud-2.8`: ReHUD 2.8's final build.
- `seed`: what the `seed` command does.
- `recon`: one recon test per character (Isaac, Tainted Isaac, Jacob and Esau, The Forgotten, Tainted Forgotten, Tainted Lazarus, Tainted Jacob); tagged `vanilla` too, as they read no ReHUD.
- `stored-character`: snapshot tests of a stored Esau Jr. or Flip character through Clicker, ChangePlayerType and losing Esau Jr.

### What each line plays

From the runner's plan (`dry.plan`): the tests, the Exit & Continues and pedestal walks asked of the player, and the worst case: the updates when every test with a limit runs to it (`HARNESS DONE` included; 30 updates a second; menu time for the Continues not counted). A test without a limit has no cap of its own: each of its waits gives up after at most 600 updates, an Exit & Continue after 9000, except a `revive` test on the death certificate, which waits for its new game (updates stop there, session 3c), so no limit counts.

| Tags line | Tests | Exit & Continues | Walks | Worst case, tests with a limit | Tests without a limit |
|---|---|---|---|---|---|
| (empty) | 73 | 0 | 2 | 17841 updates (9.9 min) | 30 |
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
| `recon` | 31 | 28 | 0 | 29336 (16.3 min) | 0 |
| `regressions` | 6 | 0 | 0 | 1251 (0.7 min) | 0 |
| `rehud` | 71 | 7 | 2 | 21261 (11.8 min) | 26 |
| `rehud-2.8` | 19 | 1 | 2 | 8026 (4.5 min) | 0 |
| `revive` | 7 | 0 | 0 | 4693 (2.6 min) | 1 |
| `seed` | 1 | 0 | 0 | 446 (0.2 min) | 0 |
| `stored-character` | 12 | 0 | 0 | 5341 (3.0 min) | 0 |
| `vanilla` | 39 | 28 | 0 | 29781 (16.5 min) | 7 |
| `walk` | 1 | 0 | 2 | 1101 (0.6 min) | 0 |

## Writing tests

- A test: `name`, `tags`, `fixture`, `steps`; optional:
  - `limit` (updates): a test with assertions FAILs there; a snapshot test at its limit ends RECORDED with a `test limit` note, writes no snapshot, and the report says NEEDS ANALYSIS.
  - `snapshot = true`.
  - `onStepError = "skip"` or `"end"`: a table step that errors or passes its own `limit` is logged as never happened, then skipped, or the test ends.
  - `onUpdate(ctx)`; `onRender(ctx)`, each render frame while the test plays, also where updates stop (session 3c); it may return one line, drawn last.
  - `traceUpdates`: log a `TRACE` line on each update the state changed.
- Steps may nest lists. A step is `function(ctx)` returning `"again"` to run again next update, or `{ label, run, limit, when, manual }`.
- A fixture: `{ name, setup = { steps }, done = function(ctx) return ok, why end, teardown }`. The setup runs, `done` is polled for up to 120 updates (still false: `FAIL precondition: <why>`), then the steps; `teardown` runs exactly once however the test ends. Shared ones in `scripts\fixtures.lua`: `fixture`, `owns`, `freshRun` (a restart on the fixed seed `9SZM 3P3S`, after one `seed` command when the run is on another; a restart off the fixed seed fails the test), `holdingJr`, `jacobAndEsau`, `character` with `RECON_CHARACTERS`, and the `TLAZ_*` setups. Each restart logs its start seed, type and frame, and every fixture logs `start seed` when done.
- Shared steps:
  - `scripts\snapshot.lua`: `test(name, tags, fixture, steps, opts)` builds a snapshot test from labelled steps (`opts.strict`: 120-update steps, a 445-update test); `perCharacter` one recon test per recon character.
  - `scripts\wait.lua`: `act` and `condition` wait for an effect.
  - `scripts\press.lua`: real presses (`flip`, `esauJr`, `clicker`, ...): a button press through `MC_INPUT_ACTION` that passes only with a new character and the spent charge or card; a stored presser's spend (Esau Jr., Flip without Birthright) is read on its own entity before the engine stores it.
  - `scripts\manual.lua`: the manual steps.
  - `scripts\settle.lua`: `look` and `lookC` wait for ReHUD to settle, then assert; each look also checks the invariants (ReHUD's entries against the engine's counts, no duplicates, no phantom stored forms, no `left` entries, no floor later than the current one; `lookC` one row per character too).
  - `scripts\assert.lua`: `expect`, `expectCount`, ..., and `pre` for a precondition.
- Add the test's verdict to `WANT` in `tests\test_<spec>.py` (the dry run fails on a planned test without one) and checks of its own lines to that module's `TESTS`.

## Manual steps

- Exit & Continue: the screen shows `exit to the menu and Continue now` on its own line; exit to the menu and pick Continue. A snapshot test gives up after 600 updates of play, a test with assertions after 9000. A new run instead fails a test with assertions (`a new run started, not a Continue`) and ends a snapshot test. A Continue after its step gave up lands in the next test: logged `late Continue, ignored` and noted `; late Continue mid-test` on that test's `RESULT`.
- Pedestal walks (`walk`): `YOU: walk onto the yum-heart pedestal`, then `YOU: step off, then walk back onto the Esau Jr. pedestal`; 450 updates each.
- Game over under `tags revive`: the certificate test's and the Missing Poster test's game overs are expected, so wait. Press Space when the screen shows `press Space` as the last line of the `Isaac Test Framework:` block, or when no new game has come 30 s after the certificate shows; the test ends at that new game. A source test reaching game over means its source gave no revive: press Space, and that test FAILs `unexpected game start`.
- At `Done: exit to the menu`, or at a game over outside `tags revive`, exit to the menu: that flushes `log.txt`.

### The revive spec

`revive` (opt-in, `tags revive`): five tests, one per revive source on Lazarus, each ending at its source's revive; then `restart from the death certificate`, which kills Isaac on the fixed seed, sends `restart` once he has been dead 120 updates or 240 render frames (updates stop there at 57 dead, renders run on: session 3c) and logs whether a new game came; 600 updates or 600 render frames later without one it shows `press Space`. The last test, `Lazarus with Missing Poster dies until it revives him`, plays after it so the restart has worked in the session first: Lazarus holding only Missing Poster dies through his own revive, then again; a Poster revive ends it RECORDED; a death still dead 120 updates or 240 render frames on is taken for a game over, restarted from the certificate the same way, and the test ends at that new game: `SKIP Missing Poster gave no revive, Poster kept: The Lost likely locked` when he still held the Poster, else RECORDED.

## Helper scripts

All take `-File <save1.dat>` (or `-Mods <folder>`) when the game is not on the default Steam path.

### auto-continue.ps1

    pwsh -File tools\auto-continue.ps1 [-File <save1.dat>] [-Keys <list>] [-ExitKeys <list>] [-Minutes 60] [-DryRun]

Opt-in; watch its first run. Start it before launch. On each new `WAIT exit-continue <n>` line in the tags file it brings the game window to the front and sends `-Keys` (default Escape, Up, Return, `wait:1500`, Return: these keys performed every Exit & Continue of session 4b; the 1.5 s wait for the main menu is unconfirmed). At `HARNESS DONE` the harness writes `WAIT exit-menu <n>`, and the script sends only `-ExitKeys` (default Escape, Up, Return), the exit to the menu, then stops; a Continue after Done keeps that marker. It also stops after `-Minutes` from its own start. Keys are Escape, Return, Up, Down or `wait:<ms>`, sent as scan codes, each only while the game is in front.

- `waiting for isaac-ng in front`: bring the game to the front and press nothing; it sends as soon as the game is in front.
- `not sent: no isaac-ng window` or `PARTIAL`: do the Exit & Continue by hand, within the step's wait (600 / 9000 updates).
- A marker already in the file when it starts is the last session's and is ignored.
- `-DryRun` prints the target window and the plan for each marker and sends nothing.

### vanilla-session.ps1

`-Start`, with the game closed, writes `disable.it` into every other mod folder that has none, recording each path in the gitignored `.vanilla-session.txt` before writing it; `-End` deletes only those, then the state file. Both are safe to run twice, and `-End` also cleans up after an interrupted `-Start`. It warns when the harness itself is disabled.

### stuck-shots.ps1

A manual step never logs `STUCK`. Any other wait still running after 60 updates logs `STUCK` once and writes `STUCK <n> <test> | <step>` as the tags file's last line (the latest only). `pwsh -File tools\stuck-shots.ps1 -Out <folder>`, started before launch, screenshots the game for each new one, and stops when the game exits or after `-Minutes` (default 30).

## Reading results

    python -B -I tools\report.py "<log copy>" [--out DIR] [--specs DIR] [--timeline TEST]

Each test ends with one `RESULT <spec> > <test>`:

- `PASS <n> assertions`.
- `FAIL <why>`: each failed assertion also logs `ASSERT FAIL`; `FAIL precondition: <why>` when its fixture never got ready.
- `RECORDED`: a snapshot test without assertions.
- `SKIP <why>`.
- `; unreached: <notes>` lists what did not run: a step that never happened, a test limit (`test limit <n> updates in <step>`), the steps skipped after either (`steps <step> to <step> skipped`), a step skipped by its guard (`skipped: <why>`) and a spec's own notes; `; late Continue mid-test` a late Continue.

`report.py` prints each test with its `INFO` lines, every failed assertion with the lines before it, snapshot differences, the Continues, errors outside its noise list and log guard hits (a mod update or Lua reset mid-session marks every later test `environment changed`), then one verdict line: `ALL PASS`, or `NEEDS ANALYSIS: <reasons>` (a FAIL, an unreached step that chance does not explain, a late Continue, a failed teardown, other errors, missing results or `HARNESS DONE`, Continues asked and resumed differing). The exit code is 0 only on `ALL PASS`. It writes `report.json` and, for each failed, new or changed test, its trace `traces\<spec> - <test>.txt` (its lines, `TEST START` to `RESULT`) into `--out` (default: the log's folder). `--specs` points at another folder of `.snap.txt` files. `--timeline <test>` prints that test's `TRACE` lines as a timeline, characters labelled A, B, C... by GetPtrHash, with a summary per character.

Other log lines, all `INFO` unless named:

- `VERDICT <press> index <i> <before> -> <after> new|returned|moved from <j>|unchanged | <lineup> -> <lineup>`: who holds the pressed index after a press, characters labelled by character record (`scripts\characters.lua`), else GetPtrHash.
- `TIMING`: the pressed index's occupant each frame after an Esau Jr. press.
- `IDS`: each GetPlayer entry's seeds, Index, GetPtrHash and twins.
- `NUMBERS`: each character's ReHUD row per look.
- `TRACE`: a snapshot test's engine and ReHUD state on each update it changed.

## Snapshots

A snapshot test logs `SNAP <spec> > <test> | <n> <step> / <key> = <value>` after each step: game state only (lineup and twins labelled by character record, else GetPtrHash, types, seed labels, items, charges, trinkets, cards, and Esau Jr. TIMING frames relative to their first), never ReHUD's. A stored character is invisible to Lua, so snapshots show only the characters in play. `report.py` keeps them in `specs\<spec>.snap.txt`, one `## <test>` section each:

- No section yet (a recon test): the first played session in which the test passes writes it.
- A section: compared key by key; a difference FAILs the test (`snapshot differs in <n> keys`) showing both values, and only a session whose tags line had `--update-snapshots` replaces it.
- Never written for a failed test, nor for a test with an unreached step, nor from a log without the engine's version line (a dry log). A played test that ended SKIP is neither compared nor written, and FAILs when its section exists.

Report the vanilla log first, so a difference in the play-set log points at a mod. Commit the `.snap.txt` files; never deploy them.

## Dry tests

The dry run plays `main.lua` under lupa (Lua 5.3) against `tests\stub\`, a fake engine, input and ReHUD whose `shortcut:` comments say what it does not model, with a fake player who continues and walks. `-I` ignores user site-packages, so install lupa into the virtual environment, not with `pip install --user`. Run one suite at a time. It checks:

- every test's verdict under each tags line it plays (`WANT` in `tests\test_<spec>.py`, plus each module's checks of its own lines);
- the runner (`test_runner.py`): tags, limits and worst cases, a late Continue or a new run instead, STUCK, fixture teardown and preconditions, which steps prompt;
- the presses' spends (`test_presses.py`);
- each invariant against its negative stub flag (`test_invariants.py`);
- `auto-continue.ps1 -DryRun` (`test_auto_continue.py`) and `vanilla-session.ps1` (`test_vanilla_session.py`), both needing `pwsh`;
- `report.py` on dry logs; `test_report.py` checks its verdicts, snapshots, log guard and JSON.

Engine behaviour enters the stub, like the code, only once a played session has shown it.
