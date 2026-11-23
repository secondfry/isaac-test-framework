# Sessions

Playing a session in game: what the player does and the helper scripts around it. The README's [Running sessions](../README.md#running-sessions) covers the routine; this is the detail. Commands run from the repo root.

## Tags line and the two runs

Write the tags line (line 1 of `data\isaac_test_framework\save<slot>.dat`, [tags.md](tags.md)) with the game closed. Play each tags line twice: once vanilla (`tools\vanilla-session.ps1`), once with the mods you normally play. Report the vanilla log first: it writes any missing snapshot, and the second log is compared against it, so a difference there points at a mod rather than the engine.

## Manual steps

- Exit & Continue: the screen shows `exit to the menu and Continue now` on its own line; exit to the menu and pick Continue. A snapshot test gives up after 600 updates of play, a test with assertions after 9000. A new run instead fails a test with assertions (`a new run started, not a Continue`) and ends a snapshot test. A Continue after its step gave up lands in the next test: logged `late Continue, ignored` and noted `; late Continue mid-test` on that test's `RESULT`.
- Pedestal walks (`walk`): `YOU: walk onto the yum-heart pedestal`, then `YOU: step off, then walk back onto the Esau Jr. pedestal`; 450 updates each.
- Game over under `tags revive`: the certificate test's and the Missing Poster test's game overs are expected, so wait. Press Space when the screen shows `press Space` as the last line of the `Isaac Test Framework:` block, or when no new game has come 30 s after the certificate shows; the test ends at that new game. A source test reaching game over means its source gave no revive: press Space, and that test FAILs `unexpected game start`.
- At `Done: exit to the menu`, or at a game over outside `tags revive`, exit to the menu: that flushes `log.txt`.

## The revive spec

`revive` (opt-in, `tags revive`): five tests, one per revive source on Lazarus, each ending at its source's revive; then `restart from the death certificate`, which kills Isaac on the fixed seed, sends `restart` once he has been dead 120 updates or 240 render frames (updates stop there at 57 dead, renders run on: session 3c) and logs whether a new game came; 600 updates or 600 render frames later without one it shows `press Space`. The last test, `Lazarus with Missing Poster dies until it revives him`, plays after it so the restart has worked in the session first: Lazarus holding only Missing Poster dies through his own revive, then again; a Poster revive ends it RECORDED; a death still dead 120 updates or 240 render frames on is taken for a game over, restarted from the certificate the same way, and the test ends at that new game: `SKIP Missing Poster gave no revive, Poster kept: The Lost likely locked` when he still held the Poster, else RECORDED.

## Helper scripts

All take `-File <save1.dat>` (or `-Mods <folder>`) when the game is not on the default Steam path.

### auto-continue.ps1

    pwsh -File tools\auto-continue.ps1 [-File <save1.dat>] [-Keys <list>] [-ExitKeys <list>] [-Minutes 60] [-DryRun]

Opt-in; watch its first run. Start it before launch. On each new `WAIT exit-continue <n>` line in the tags file it brings the game window to the front and sends `-Keys` (default Escape, Up, Return, `wait:1500`, Return: these keys and the 1.5 s wait for the main menu performed every Exit & Continue in play). At `HARNESS DONE` the harness writes `WAIT exit-menu <n>`, and the script sends only `-ExitKeys` (default Escape, Up, Return), the exit to the menu, then stops; a Continue after Done keeps that marker. It also stops after `-Minutes` from its own start. Keys are Escape, Return, Up, Down or `wait:<ms>`, sent as scan codes, each only while the game is in front.

- `waiting for isaac-ng in front`: bring the game to the front and press nothing; it sends as soon as the game is in front.
- `not sent: no isaac-ng window` or `PARTIAL`: do the Exit & Continue by hand, within the step's wait (600 / 9000 updates).
- A marker already in the file when it starts is the last session's and is ignored.
- `-DryRun` prints the target window and the plan for each marker and sends nothing.

### vanilla-session.ps1

`-Start`, with the game closed, writes `disable.it` into every other mod folder that has none, recording each path in the gitignored `.vanilla-session.txt` before writing it; `-End` deletes only those, then the state file. Both are safe to run twice, and `-End` also cleans up after an interrupted `-Start`. It warns when the harness itself is disabled.

### stuck-shots.ps1

A manual step never logs `STUCK`. Any other wait still running after 60 updates logs `STUCK` once and writes `STUCK <n> <test> | <step>` as the tags file's last line (the latest only). `pwsh -File tools\stuck-shots.ps1 -Out <folder>`, started before launch, screenshots the game for each new one, and stops when the game exits or after `-Minutes` (default 30).
