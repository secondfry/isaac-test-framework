# Results

Reading a session's log. Commands run from the repo root.

## report.py

    python -B -I tools\report.py "<log copy>" [--out DIR] [--specs DIR] [--timeline TEST]

`report.py` prints each test with its `INFO` lines, every failed assertion with the lines before it, snapshot differences, the Continues, errors outside its noise list and log guard hits (a mod update or Lua reset mid-session marks every later test `environment changed`), then one verdict line: `ALL PASS`, or `NEEDS ANALYSIS: <reasons>` (a FAIL, an unreached step that chance does not explain, a late Continue, a failed teardown, other errors, missing results or `HARNESS DONE`, Continues asked and resumed differing). The exit code is 0 only on `ALL PASS`.

It writes `report.json` and, for each failed, new or changed test, its trace `traces\<spec> - <test>.txt` (its lines, `TEST START` to `RESULT`) into `--out` (default: the log's folder). `--specs` points at another folder of `.snap.txt` files. `--timeline <test>` prints that test's `TRACE` lines as a timeline, characters labelled A, B, C... by GetPtrHash, with a summary per character.

## RESULT lines

Each test ends with one `RESULT <spec> > <test>`:

- `PASS <n> assertions`.
- `FAIL <why>`: each failed assertion also logs `ASSERT FAIL`; `FAIL precondition: <why>` when its fixture never got ready.
- `RECORDED`: a snapshot test without assertions.
- `SKIP <why>`.
- `; unreached: <notes>` lists what did not run: a step that never happened, a test limit (`test limit <n> updates in <step>`), the steps skipped after either (`steps <step> to <step> skipped`), a step skipped by its guard (`skipped: <why>`) and a spec's own notes; `; late Continue mid-test` a late Continue.

## Other log lines

All `INFO` unless named:

- `VERDICT <press> index <i> <before> -> <after> new|returned|moved from <j>|unchanged | <lineup> -> <lineup>`: who holds the pressed index after a press, characters labelled by character record (`scripts\characters.lua`), else GetPtrHash.
- `TIMING`: the pressed index's occupant each frame after an Esau Jr. press.
- `IDS`: each GetPlayer entry's seeds, Index, GetPtrHash and twins.
- `NUMBERS`: each character's ReHUD row per look.
- `TRACE`: a snapshot test's engine and ReHUD state on each update it changed.

Which helper writes each: [helpers.md](helpers.md#recordlua).

## Snapshots

A snapshot test logs `SNAP <spec> > <test> | <n> <step> / <key> = <value>` after each step: game state only (lineup and twins labelled by character record, else GetPtrHash, types, seed labels, items, charges, trinkets, cards, and Esau Jr. TIMING frames relative to their first), never ReHUD's. A stored character is invisible to Lua, so snapshots show only the characters in play. `report.py` keeps them in `specs\<spec>.snap.txt`, one `## <test>` section each:

- No section yet (a recon test): the first played session in which the test passes writes it.
- A section: compared key by key; a difference FAILs the test (`snapshot differs in <n> keys`) showing both values, and only a session whose tags line had `--update-snapshots` replaces it.
- Never written for a failed test, nor for a test with an unreached step, nor from a log without the engine's version line (a dry log). A played test that ended SKIP is neither compared nor written, and FAILs when its section exists.

Report the vanilla log first, so a difference in the play-set log points at a mod. Commit the `.snap.txt` files; never deploy them.
