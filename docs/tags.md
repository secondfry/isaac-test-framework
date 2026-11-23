# Tags

Which tests a session plays. How to write the tags line and run a session: [sessions.md](sessions.md).

## Rules

Line 1 of `data\isaac_test_framework\save<slot>.dat` in the game folder (the vanilla `SaveData` file of the save slot played), written before launch:

- `tags a,b` (commas or spaces): every test that has one of the tags; `tags all`: every test but the `opt-in` ones.
- Empty line, or no file: every test but the `opt-in` ones and the `exit-continue` ones not tagged `new`.
- An `opt-in` test plays only when one of its other tags is named.
- `--update-snapshots` anywhere on the line lets `report.py` replace the snapshots that differ.

`HARNESS START` logs the line; a skipped test logs `RESULT <spec> > <test> SKIP <why> (tags '<line>')` and takes no update. The lines below line 1 are the harness's own (`WAIT`, `STUCK`) and never change the tags; `HARNESS START` drops the last session's.

## The tags

Tag a test with its spec's name, `vanilla` or `rehud`, and each manual step it asks for.

- One per spec: `hello`, `engine`, `continue`, `characters`, `esau_jr`, `base_change`, `item_copies`, `regressions`, `revive`.
- `vanilla` (no ReHUD needed) or `rehud` (reads ReHUD).
- `exit-continue`: asks for an Exit & Continue; these tests play last, back to back.
- `walk`: asks for pedestal walks. `drop`: asks for a drop press.
- `new`: an `exit-continue` test the empty line still plays. Set it until the test has passed in game, and again whenever its steps or assertions change.
- `opt-in`.
- `rehud-2.8`: ReHUD 2.8's final build.
- `rehud-rework`: recon for ReHUD matching a character back from Exit & Continue by its owned items.
- `seed`: what the `seed` command does.
- `recon`: one recon test per character (Isaac, Tainted Isaac, Jacob and Esau, The Forgotten, Tainted Forgotten, Tainted Lazarus, Tainted Jacob); tagged `vanilla` too, as they read no ReHUD.
- `stored-character`: snapshot tests of a stored Esau Jr. or Flip character through Clicker, ChangePlayerType and losing Esau Jr.

## What each line plays

From the runner's plan (`dry.plan`): the tests, the Exit & Continues and pedestal walks asked of the player, and the worst case: the updates when every test with a limit runs to it (`HARNESS DONE` included; 30 updates a second; menu time for the Continues not counted). A test without a limit has no cap of its own: each of its waits gives up after at most 600 updates, an Exit & Continue after 9000, except a `revive` test on the death certificate, which waits for its new game (updates stop there, session 3c), so no limit counts.

| Tags line | Tests | Exit & Continues | Walks | Worst case, tests with a limit | Tests without a limit |
|---|---|---|---|---|---|
| (empty) | 73 | 0 | 2 | 17841 updates (9.9 min) | 30 |
| `tags all` | 111 | 38 | 4 | 54241 (30.1 min) | 33 |
| `base_change` | 15 | 7 | 0 | 9531 (5.3 min) | 3 |
| `characters` | 18 | 8 | 0 | 10776 (6.0 min) | 3 |
| `continue` | 16 | 16 | 2 | 14401 (8.0 min) | 3 |
| `drop` | 3 | 0 | 0 | 1336 (0.7 min) | 0 |
| `engine` | 5 | 0 | 0 | - | 5 |
| `esau_jr` | 46 | 7 | 2 | 19041 (10.6 min) | 13 |
| `exit-continue` | 38 | 38 | 2 | 36401 (20.2 min) | 3 |
| `hello` | 3 | 0 | 0 | 446 (0.2 min) | 2 |
| `item_copies` | 4 | 0 | 0 | - | 4 |
| `recon` | 34 | 31 | 2 | 33736 (18.7 min) | 0 |
| `regressions` | 6 | 0 | 0 | 1251 (0.7 min) | 0 |
| `rehud` | 71 | 7 | 2 | 21261 (11.8 min) | 26 |
| `rehud-2.8` | 19 | 1 | 2 | 8026 (4.5 min) | 0 |
| `rehud-rework` | 3 | 3 | 2 | 4401 (2.4 min) | 0 |
| `revive` | 7 | 0 | 0 | 4693 (2.6 min) | 1 |
| `seed` | 1 | 0 | 0 | 446 (0.2 min) | 0 |
| `stored-character` | 12 | 0 | 0 | 5341 (3.0 min) | 0 |
| `vanilla` | 42 | 31 | 2 | 34181 (19.0 min) | 7 |
| `walk` | 2 | 1 | 4 | 3501 (1.9 min) | 0 |
