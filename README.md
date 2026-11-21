# rehud_test_harness

Install: copy `main.lua` and `metadata.xml` over to `mods\rehud_test_harness` in the game folder and delete `disable.it` there; put `disable.it` back after each session.

On the first new run after launch, on save slot 1 (unlocked there: Cain, Eve, Samson, Lazarus, Lilith, The Forgotten, J&E, Tainted Lazarus, Tainted Forgotten), it plays the scenarios in `SCENARIOS` by itself; the user only starts the run, exits and continues when the screen says so, and exits to the menu after DONE (that flushes `log.txt`).

Each scenario is `kind = "small"` (passes on its own) or `"large"` (needs the user's exit and Continue; runs last, back to back, each asking for its own); a large one carries `new = true` until it has passed in game, then clear the flag; set it again whenever its steps or checks change.

Mode: before launch, write the plain text `regression` into `data\rehud_test_harness\save1.dat` in the game folder (vanilla `SaveData` path, `data\<metadata directory>\save<slot>.dat`) to run every scenario before a release; `only <prefix>` runs just the scenarios whose name starts with it (`only obs`: every `obs` scenario); any other content, or no file, runs all small scenarios and only the new large ones.

The `HARNESS START` line logs the mode, the mod name and the raw data read; a skipped one logs `RESULT <name> SKIP`.

A wait (action, look or settle) still unfinished after 60 updates logs `PROBE STUCK` and writes `STUCK <n> <scenario> | <step>` as the second line of that mode file (only its first line sets the mode); `tools\stuck-shots.ps1` screenshots the game window for each new STUCK line, so start it before launching the game: `pwsh -File isaac-test-harness\tools\stuck-shots.ps1 -Out <folder>`.

Each action polls its postcondition and probes wait for ReHUD to settle; a swap (Flip, Esau Jr., Clicker, Soul of J&E) is a real button press through `MC_INPUT_ACTION` and passes only with a new character plus the spent charge or card; a stored presser's spend (Esau Jr., Flip without Birthright) is read on its seed before the engine stores it (`..\lua-api-notes.md`), and a swap with no such reading FAILs. `probes` re-checks engine facts the checks rely on. Probes read ReHUD state through the permanent `ReHUD.dbg` hook (tracker, config, roster).

Results: `PROBE RESULT <scenario> PASS|FAIL|INFO` in `log.txt`, with a `PROBE CHECK FAIL` line per failed check. Every settled look also checks five invariants (engine vs ReHUD counts, duplicates, phantom stored forms, `left` entries, floors not later than the current one).

After a run, copy `log.txt` and run `.venv\Scripts\python -B -I isaac-test-harness\tools\run_report.py "<log path>"`; it ends with `ALL PASS` or `NEEDS ANALYSIS: <reasons>`, and only the latter needs an analysis agent.

The `obs` scenarios have no checks (INFO only, a step that never happens is logged and skipped): they log `PROBE OBS` lines of engine and ReHUD state on every update it changed; `tools\obs_report.py "<log path>"` prints them as one timeline per scenario, seeds as labels A, B, C..., with a per-seed summary. Add new scenarios (ReHUD or other mods) to `SCENARIOS` instead of typing console steps. Dry run: `.venv\Scripts\python -B -I isaac-test-harness\tests\test_harness.py isaac-test-harness\main.lua`.
