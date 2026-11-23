# Isaac Test Framework

End-to-end tests for Binding of Isaac: Repentance+ mods that run inside the real game (vanilla Lua, no REPENTOGON). Each test starts from its own fresh run on a fixed seed, drives the game with console commands and real button presses, and checks the result with assertions; snapshots record game behaviour once and flag any later difference, so a game or mod update that changes behaviour shows up as a failed test.

## Why

- Mods break silently when the game updates. Repentance+ v1.9.7.19.J510 moved the keyboard to a new controller index and turned mod shaders black; nothing in a mod's own code changed.
- Checking by hand in the debug console is slow and hard to repeat: every check starts from whatever run you happen to be in.
- Some engine behaviour is documented nowhere and only shows up when observed: who holds which items after Esau Jr., Tainted Lazarus's Flip, or an Exit & Continue. A recon test records it; once a session has shown it, a snapshot keeps it under watch. What has been observed so far is in [docs/engine-facts.md](docs/engine-facts.md).

The bundled specs test the engine itself and the ReHUD fork ([secondfry/ReHUD](https://github.com/secondfry/ReHUD)); add a spec for your own mod next to them.

## Quick start

Requirements: Windows, the game on Steam, PowerShell 7 (`pwsh`) for the helper scripts and Python 3 for the report. Back up your save or use a spare save slot: the tests give items, send console commands and kill characters.

1. Clone the repo and copy the mod into the game's mods folder, with the game closed (`<game>` is `C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth` on the default Steam path):

       git clone https://github.com/secondfry/isaac-test-framework
       cd isaac-test-framework
       robocopy . "<game>\mods\isaac_test_framework" main.lua metadata.xml
       robocopy scripts "<game>\mods\isaac_test_framework\scripts" *.lua
       robocopy specs "<game>\mods\isaac_test_framework\specs" *.lua

   robocopy exit codes below 8 mean success. Copy only these files: never `tests\`, `tools\`, `docs\` or `*.snap.txt`.

2. Pick the tests: write `tags hello` as line 1 of `<game>\data\isaac_test_framework\save1.dat` (create the folder if it is missing; `save1.dat` is for save slot 1). `hello` is three short vanilla tests with no manual steps.

3. Launch the game, load save slot 1 and start a new run. The tests play by themselves; the bottom-left of the screen shows `Isaac Test Framework:` with the current test and step.

4. When the screen says `Done: exit to the menu`, exit to the menu (that flushes `log.txt`) and copy `Documents\My Games\Binding of Isaac Repentance+\log.txt` somewhere: the game overwrites it on every launch.

5. Read the copy:

       python -B -I tools\report.py "<log copy>"

   It prints every test's result and ends with `ALL PASS` (exit code 0) or `NEEDS ANALYSIS: <reasons>`.

When you are not testing, put an empty `disable.it` file into `<game>\mods\isaac_test_framework`: the harness starts on the first new run after every launch.

## Writing a test

A **spec** is one file, `specs\<name>.lua`, returning `{ name = "<name>", tests = { ... } }`; add its name to `SPECS` in `main.lua`. A **test** has a `name`, its `tags`, a `fixture` and its `steps`. This one is from `specs\hello.lua`:

```lua
{ name = "Clicker on Isaac", tags = { "hello", "vanilla" }, fixture = freshRun(ISAAC), steps = {
	function(ctx) expect(ctx, "player 0 type", Isaac.GetPlayer(0):GetPlayerType(), ISAAC) end,
	give(CLICKER),
	function(ctx) expect(ctx, "player 0 primary active", Isaac.GetPlayer(0):GetActiveItem(PRIMARY), CLICKER) end,
	clicker,
	function(ctx)
		local p = Isaac.GetPlayer(0)
		snap(ctx, "Clicker roll / type", p:GetPlayerType())
		expect(ctx, "Clicker charge after the use", chargeOf(p, CLICKER, PRIMARY), 0)
	end,
} },
```

- **Fixture**: the starting setup. `freshRun(ISAAC)` restarts as Isaac on the fixed seed `9SZM 3P3S`; the test starts once the fixture's `done` check holds (within 120 updates, else `FAIL precondition`). Shared fixtures are in `scripts\fixtures.lua`.
- **Step**: one action, one per game update. A step is `function(ctx)`, returning `"again"` to run again next update, or a table `{ label, run, limit, when, manual }`. `give(CLICKER)` (`scripts\console.lua`) sends `giveitem` and waits until the item is owned; `clicker` (`scripts\press.lua`) presses the item button for real and passes only when the character changed and the charge was spent.
- **Assertion**: one expected result, such as `expect(ctx, label, got, want)` from `scripts\assert.lua`. A failed one logs `ASSERT FAIL` and fails the test; the test goes on to its end.
- **Snapshot**: `snap(ctx, key, value)` records a value without judging it, here which character Clicker rolled. `report.py` stores the first passing session's values in `specs\<spec>.snap.txt` and compares every later session against them. `snapshot.test(...)` in `scripts\snapshot.lua` builds a whole snapshot test from labelled steps and records the game state after each step. A snapshot test whose values are not stored yet is a **recon test**: it only records.
- **Manual step**: a step the player does by hand, prompted on screen, from `scripts\manual.lua`: `exitAndContinue()` (Exit & Continue) and the pedestal walks.
- **Tags**: tag a test with its spec's name, `vanilla` if it needs no other mod, and `exit-continue` or `walk` if it has those manual steps. The tags line picks the tests a session plays.

To test your own mod, read its state from the test. The `rehud` tests read ReHUD through a read-only `ReHUD.dbg` hook the mod exposes (`scripts\rehud.lua`); without the hook the runner skips the `rehud` tests with assertions (`SKIP ReHUD.dbg not loaded`). Do the same for your mod: expose its state in a global table and read it from the steps.

Engine behaviour starts as a recon test, with no assertions on it, until a played session has shown it; then record it in `docs\engine-facts.md` with that session.

More on test options, the shared steps and fixtures: [docs/reference.md](docs/reference.md).

## Running sessions

**Tags line.** Line 1 of `data\isaac_test_framework\save<slot>.dat` in the game folder, written with the game closed: `tags a,b` plays every test with one of those tags, `tags all` every test but the opt-in ones, an empty line the default set. Add `--update-snapshots` to the line to let `report.py` replace snapshots that differ. The harness writes its own lines below line 1; leave them. Every tag and what each line costs in time: [docs/reference.md](docs/reference.md#tags).

**Two runs per session.** Play each tags line twice: once vanilla, once with the mods you normally play. Report the vanilla log first: it writes any missing snapshot, and the second log is compared against it, so a difference there points at a mod rather than the engine.

    pwsh -File tools\vanilla-session.ps1 -Start
    (launch, play the session, exit to the menu, copy log.txt, close the game)
    pwsh -File tools\vanilla-session.ps1 -End

`-Start` puts `disable.it` into every other mod folder that has none and lists them in `.vanilla-session.txt`; `-End` removes just those. Both refuse to run while the game is open. Pass `-Mods <folder>` if the game is not on the default Steam path.

**During a session.** Hands off, except the manual steps the screen asks for, such as `exit to the menu and Continue now`. Any game start the harness did not ask for (hold-R, a new run) fails the current test. Tests with an Exit & Continue play last, back to back.

**Automatic Exit & Continue** (opt-in; watch its first run). Started before launch, `tools\auto-continue.ps1` presses the keys for you:

    pwsh -File tools\auto-continue.ps1

Each time the harness asks for an Exit & Continue it writes a `WAIT exit-continue <n>` line into the tags file, and the script sends Escape, Up, Return, a 1.5 s wait for the main menu, then Return (Continue) to the game window. At `Done` the harness writes `WAIT exit-menu <n>`; the script sends only Escape, Up, Return, the exit to the menu that flushes `log.txt`, and then stops. It also stops after `-Minutes` (default 60). If it prints `waiting for isaac-ng in front`, bring the game to the front and press nothing. On `not sent` or `PARTIAL`, do that Exit & Continue by hand. `-DryRun` prints the plan and sends nothing; `-File <save1.dat>` points it at another tags file.

**Reading results.**

    python -B -I tools\report.py "<log copy>" [--out DIR] [--timeline TEST]

Each test ends with one `RESULT` line: `PASS <n> assertions`, `FAIL <why>`, `RECORDED` (a snapshot test without assertions) or `SKIP <why>`. The report shows each test's results, failed assertions with the lines before them, and snapshot differences, then `ALL PASS` or `NEEDS ANALYSIS: <reasons>`. It writes `report.json` and a trace of each failed, new or changed test into `--out` (default: the log's folder). Commit the `.snap.txt` files it writes. Details: [docs/reference.md](docs/reference.md#reading-results).

## Limits and requirements

- Windows only: the helper scripts use PowerShell 7 and Windows input calls, and default to the Steam install path.
- Vanilla Repentance+ only; not built for REPENTOGON.
- The save slot you play needs these characters unlocked: Cain, Eve, Samson, Lazarus, Lilith, Eden, Tainted Isaac, Jacob and Esau, The Forgotten, Tainted Forgotten, Tainted Lazarus and Tainted Jacob. A test of a locked character fails as a precondition or, for a snapshot test, ends at its restart.
- The tests send console commands (`restart`, `seed`, `giveitem`), give items and kill characters on that slot: back it up.
- One pass per launch: the harness starts on the first new run after the game launches; a Continue first only logs `HARNESS idle`. A native crash means relaunching and starting the session over.
- `tools\stuck-shots.ps1 -Out <folder>` screenshots the game whenever a wait runs long (`STUCK`); see the reference.

## Dry tests (contributors)

The dry tests play `main.lua` under Lua 5.3 (Python `lupa`) against a fake engine in `tests\stub\`, with a fake player who continues and walks. They need Python 3 with lupa in a virtual environment and, for the tool tests, `pwsh`:

    python -m venv .venv
    .venv\Scripts\pip install lupa
    .venv\Scripts\python -B -I tests\test_harness.py main.lua [test function ...]
    .venv\Scripts\python -B -I tests\test_report.py

The full dry run takes about 8 minutes; name test functions to run a few. A new test needs its expected verdict in `WANT` in `tests\test_<spec>.py`, or the dry run fails. What each suite checks: [docs/reference.md](docs/reference.md#dry-tests).

## Licence

MIT, see [LICENSE](LICENSE).
