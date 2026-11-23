# Helpers

Every building block a spec can use, from `scripts\`, most used first. Load a module with `include("scripts.<module>")` and take what you need from the table it returns, as in [specs\hello.lua](../specs/hello.lua). How a test, a step and a fixture fit together: [tests.md](tests.md).

Conventions used below:

- **Step**: a value for a test's `steps` list (see [tests.md](tests.md#steps)). **Reader**: a plain function, called from a step. **Fixture**: a value for a test's `fixture`.
- **Waits for**: a waiting step (built on `wait.act`) acts once, then polls its check every update; once the check holds it runs one more update, so ReHUD's `MC_POST_UPDATE` has seen the effect, and logs `DONE <label> after <n> updates`. At its ceiling it errors `<label>: <why> after <n> updates`, which FAILs the test (or, under `onStepError`, marks the step never happened). The default ceiling is 600 updates (`wait.TIMEOUT`, 20 s); a wait with a ceiling of 600 or less logs `STUCK` once at 60 updates.
- **Engine**: works in a vanilla session. **ReHUD**: reads ReHUD through `ReHUD.dbg` (`scripts\rehud.lua`) and errors `ReHUD.dbg missing` without it; tag such a test `rehud`, and the runner skips it when ReHUD is absent.
- Player 0 is `Isaac.GetPlayer(0)`. `ctx` is the test's context: `ctx.name`, `ctx.floors[n]` (floor names recorded by `fresh` and `stage`), `ctx.assertions`, `ctx.notes`.

## fixtures.lua

Starting setups. Each fixture's `setup` steps run, then the runner polls its `done` up to 120 updates (else `FAIL precondition: <why>`). All engine-only unless noted.

| Name | What it is |
|---|---|
| `fixture(name, setup, t, extra)` | A fixture: steps `setup`, done once player 0 is of type `t` and `extra(p)`, if given, returns true (its second value is the why). |
| `owns(id)` | An `extra` for `fixture`: player 0 owns at least one `c<id>`. |
| `freshRun(t)` | A restart as type `t` on the fixed seed `9SZM 3P3S` (`console.fresh`). |
| `holdingJr(character, t)` | Fresh run as `t`, then c4 and Esau Jr. given; done when player 0 owns Esau Jr. `character` only names it. |
| `jacobAndEsau(setup)` | Steps `setup`, done once player 0 is Jacob and an Esau is in play. |
| `RECON_CHARACTERS` | The seven characters the per-character recon tests start as: `{ type, name, who }` for Isaac, Tainted Isaac, Jacob and Esau, The Forgotten, Tainted Forgotten (`who = { index = 0, any = true }` for its presses), Tainted Lazarus, Tainted Jacob. |
| `character(c, setup, extra)` | `console.restart(c.type)` (any character, no type check in the step), then `setup`; a done check that fails names `c` as maybe locked on this save. |
| `TLAZ_JR` | `holdingJr("Tainted Lazarus", T_LAZ)`. |
| `TLAZ_JR_FLOOR_2` | Tainted Lazarus holding c4 and Esau Jr., on floor 2. |
| `TLAZ_JR_TWINS` | Tainted Lazarus holding c4 and Esau Jr., given Birthright (2 players). |
| `TLAZ_C4` / `TLAZ_C4_FLOOR_2` | Tainted Lazarus holding c4, on floor 1 / floor 2. |
| `FLIPPED` | Tainted Lazarus with c4, floor 2, flipped to Dead Tainted Lazarus, who takes c5; done as type 38. |
| `TLAZ_FLIPS` | Tainted Lazarus L flips to D and back, Esau Jr. makes LJ (asserted on D's item seed), LJ flips to D; names L, D, LJ. **ReHUD** (its `lookC` steps). |

## console.lua

Console commands. A command is queued and runs from `MC_POST_RENDER` (`flush`), never inside other mods' `MC_POST_UPDATE`; each logs `CMD <command>`. All engine-only, ceiling 600 unless noted.

| Name | Kind | Does, and waits for |
|---|---|---|
| `give(id, players)` | step | `giveitem c<id>` (player 0); waits until player 0 owns one more copy and, when `players` is given, the player count is `players` (Birthright on Tainted Lazarus: 2). |
| `remove(id, players)` | step | `remove c<id>`; waits until player 0 owns one copy fewer (and `players` players). |
| `stage(n)` | step | `stage <n>`; waits for that stage with a new floor name (an unchanged name fails: floor checks would be meaningless); records `ctx.floors[n]`, logs `FLOOR`. |
| `fresh(t)` | step | A new game on the fixed seed `9SZM 3P3S`: a `seed` command first when the run is on another seed, then `restart <t>`; waits for the new game with player 0 of type `t` (else `character locked?`). A restart off the fixed seed aborts the test; a Continue instead errors. Logs the start seed, type and frame; records `ctx.floors[1]`. |
| `restart(t)` | step | As `fresh`, but any player 0 type passes: the fixture's done check reports a locked character (`fixtures.character`). |
| `seed()` | step | Recon: `seed` with the run's own start seed, then up to 50 updates for a game start; logs whether one came and after how long. Always passes. |
| `giveAnyone(id)` | step | `giveitem c<id>` to whoever the engine gives it (the Keeper once a Strawman Keeper exists); waits until any player owns one more, logs its index and type. |
| `startNew(command)` | function | Queues `command` and tells the runner a new game is expected; returns the game generation to wait past. For a step of your own that starts a game. |

Internal (the runner's and `main.lua`'s): `flush`, `busy`, `reset`.

## assert.lua

Assertions. Each counts one in `ctx.assertions`; a failed one logs `ASSERT FAIL <test> <why>` and fails the test, which still runs to its end.

| Name | Needs | Passes when |
|---|---|---|
| `expect(ctx, label, got, want)` | engine | `got == want`. Also logs `INFO <test> <label> <got>`. The general one. |
| `pre(ok, why)` | engine | `ok`; else errors `precondition: <why>`: the test FAILs `precondition: <why>`, and a soft step of a recon test never happens. Not an assertion: for what a step needs before it acts. |
| `fail(ctx, why)` | engine | Never: records a failed assertion (without counting one). |
| `fired(ctx, label, id, arg, want)` | engine | Callback `id` fired `want` times with `arg` (the item id for `MC_USE_ITEM`) since the step's press began (`ctx.mark`, set by `press.press`). |
| `holds(ctx, label, what, problems)` | engine | `problems` (a list of strings) is empty; the failure names all of them. |
| `expectN(ctx, label, id, n, floor, owner)` | ReHUD | Exactly `n` ReHUD entries of `c<id>`, each on `floor` and owned by `owner` when given. |
| `expectOne(ctx, label, id, floor, owner)` | ReHUD | `expectN` with `n = 1`. |
| `expectCount(ctx, label, want, id, floor, temporary, owner)` | ReHUD | `want` entries of `c<id>` matching every given field (`nil`: any); `temporary = true` counts copies with a clock. One assertion. |
| `own(ctx, label, want, id, floor, temporary)` | ReHUD | `expectCount` with player 0 as owner. |
| `oneC4(ctx, label)` | ReHUD | One c4 entry, on floor 1. |
| `twoC4(ctx, label)` | ReHUD | Two c4 entries on floor 1, both player 0's. |
| `c4c5(ctx, label)` | ReHUD | One c4 on floor 1 and one c5 on floor 2. |
| `birthrightOwners(ctx, label)` | ReHUD | `c4c5`, c4 owned by Tainted Lazarus and c5 by Dead Tainted Lazarus. |
| `noneLeft(ctx, label)` | ReHUD | No entry marked left, and ReHUD's character count equals the engine's. |

## record.lua

What the logs record. `snap` is the one most tests use; the rest log `INFO` lines for recon. All engine-only unless noted.

| Name | Kind | Does |
|---|---|---|
| `snap(ctx, key, value)` | reader | Logs `SNAP <test> \| <key> = <value>`: a value recorded without judging it, compared across sessions by `report.py` ([results.md](results.md#snapshots)). |
| `verdict(press, step, index, timed)` | step | Wraps a press `step`: after it, logs `VERDICT <press> index <i> <before> -> <after> new\|returned\|moved from <j>\|unchanged \| <lineup> -> <lineup>`, who holds GetPlayer index `index` (default 0). `timed` also logs `TIMING` lines, the pressed index's occupant for 5 frames. |
| `watchLineup(n)` | `onUpdate` | From the trace's start: on each of the `n` updates after a game start or a change of GetPlayer's entities, every player as `SNAP` (label, type, seed label, items) and `INFO WATCH` (raw seed and GetPtrHash). |
| `parentsInfo(what)` | step | `INFO PARENTS`: each player's Parent (as a GetPlayer index), ControllerIndex, ReHUD key and number (`no ReHUD` without it). |
| `idsInfo(label)` | step | `INFO IDS`: each player's seeds (CollectibleRNG, InitSeed, DropSeed, Card/Pill/Trinket RNG), Index, GetPtrHash and twins as GetPlayer indices; every read pcall'd. |
| `playerCount` | step | `INFO players in game <n>`. |
| `typeNow` | step | `INFO player 0 type <t>`. |
| `pocketHeld` | step | `INFO player 0 pocket active <id>` (711 = Flip). |
| `slotsNow` | step | `INFO player 0 slots primary <id> secondary <id>`. |
| `storedSettlingNow` | step | `INFO stored forms still settling <keys>` (empty without ReHUD). |
| `innerOn` | step | Turns on `innerWatch` for the test: on each update it changed, `INFO INNER frame`: every player's Inner Eye (c2) owned/total and item count. |
| `innerInfo(what)` | step | One such `INFO INNER <what>` line now. |
| `innerLine()` | reader | That line's text. |
| `innerWatch(ctx)` | `onUpdate` | The per-update half of `innerOn`. |
| `label(ctx, e)` | reader | An entity's snapshot label: `A`, `B`... by character record (`characters.lua`), else GetPtrHash, in first-seen order within the test; `none` for nil. No method is called on `e`. |
| `logState(ctx, label)` | reader | `STEP`, `PLAYER`, `ITEM` and `ENTRY` lines: the floor, each player and its items, each ReHUD entry. **ReHUD**. |
| `try(f)` | reader | `f()` as text, or `error <message>`. |

Internal (runner and `main.lua`): `update`, `startAsserting`, `onTraceStarts`, `stepBegins`, `stopTiming`, `stop`, `onPlayerUpdate`, `snapStep` (a snapshot test's `SNAP` lines after each step, [results.md](results.md#snapshots)).

## press.lua

Real button presses through `MC_INPUT_ACTION`, as a player would press them. All engine-only.

| Name | Kind | Does, and passes when |
|---|---|---|
| `press(label, id, slot, count, ceiling, who)` | step | Charges item `id` in `slot` full (or counts card `id` when `slot` is `"card"`) and presses it: `ACTION_ITEM` for the primary slot, else `ACTION_PILLCARD`, re-armed until something happens. Passes only once player 0 (or GetPlayer index `who.index`) is a new character (type or item seed changed, or the player count did) and the charge or card was spent; `count`: also wants that many players. A stored presser's spend (Esau Jr., Flip without Birthright) is read on its own entity before the engine stores it. Errors early: charge spent and no new character after 30 updates; a new character but nothing spent 30 updates on. `who` presses ITEM and PILLCARD together; `who.any` takes a press from any entity. Logs `PRESS` and `SWAP`. Ceiling `ceiling` or 600. In a recon test, a spent press that left seed and type but changed the entity or items also passes. |
| `flip(label)` | step | `press` of Flip in the pocket slot. |
| `esauJr(label)` | step | `press` of Esau Jr. in the primary slot. |
| `clicker` | step | `press("Clicker", ...)` in the primary slot. |
| `clickerWithin60` | step | `clicker` with a 60-update ceiling. |
| `birthrightFlip` | step | `flip("put type 29 in player 0")`. |
| `soulJE` | step | Soul of Jacob and Esau used by a card press; wants 2 players after. |
| `cancelledClicker(change)` | step | Clicker charged and pressed, with the use vetoed in `MC_PRE_USE_ITEM`; logs the type and charge around it and the callback counts; `change`: `ChangePlayerType(T_FORGOTTEN)` in the same update. Passes once the press reached `MC_PRE_USE_ITEM`; ceiling 10. |
| `dropPress(label, cond, fallbackName, fallback)` | step | Real drop presses by player 0 (re-armed every 10 updates) until `cond(p)`; after 60 updates calls `fallback(p)` once (pcall'd). Nothing pressed when `cond` already holds. Logs which did it. Ceiling 600. |
| `toSlot(label, slot, id)` | step | `dropPress` until item `id` is in `slot`, `SwapActiveItems` as the fallback. |
| `swapCopies()` | step | Player 0's two Esau Jr. copies (primary and Schoolbag) swapped by a drop press, `SwapActiveItems` as the fallback; marked charges show the swap. Errors unless both slots hold Esau Jr. |
| `dropOnce(label, who)` | step | Recon: one drop press, then up to 30 updates for a type or entity to change; logs what changed. Always passes. |
| `deadFirst()` | reader | Player 0 is Dead Tainted Lazarus. |

Internal (`main.lua`'s callbacks): `onUse`, `onPlayerUpdate`, `onInput`, `onVetoPre`, `onClickerUse`, `onVetoUpdate`, `teardown`.

## manual.lua

Steps the player does by hand; the screen prompts each once it starts ([sessions.md](sessions.md#manual-steps)), and none logs `STUCK`. All engine-only.

| Name | Waits for | Ceiling |
|---|---|---|
| `exitAndContinue(soft)` | Exit to the menu and Continue. Passes on a Continue with the same players (item seeds) as before; `soft`: any players, logged. A new run instead errors `a new run started, not a Continue`. Writes a `WAIT exit-continue <n>` line for `auto-continue.ps1`; logs the `ACTION` line again every 300 updates. Tag the test `exit-continue`. | 9000 (`wait.CONTINUE_TIMEOUT`) |
| `dropByHand` | Spawns a Yum Heart pedestal beside player 0 (who must hold Esau Jr. in the primary slot); the player walks onto it, dropping Esau Jr.: passes when player 0 owns no Esau Jr. and one lies on a pedestal. Tag `walk`. | 450 |
| `pickByHand` | The player steps off and walks back onto the Esau Jr. pedestal: passes when player 0 owns Esau Jr. Tag `walk`. | 450 |

In a snapshot test use `snapshot.continued` instead of `exitAndContinue()`.

## snapshot.lua

Snapshot tests: steps that record the game state after each one instead of asserting ([tests.md](tests.md#recon-and-snapshot-tests)). Engine-only (the settle waits skip ReHUD when it is absent).

| Name | Does |
|---|---|
| `test(name, tags, fixture, steps, opts)` | Builds a snapshot test: `fixture`'s setup, a settle wait, then `steps`, each `{ label, step, when, limit }` (or a list of such), numbered `1 <label>`, `2 <label>`..., then a final settle. The runner logs the state after each step as `SNAP`. A step that errors or passes its limit is logged `never happened` and skipped; with `opts.strict`, every step (setup included) gets a 120-update limit (or its own `limit`), the test a limit of `opts.limit` or 445 updates, and a missed step ends the test. Sets `snapshot`, `traceUpdates` and `onStepError`. |
| `perCharacter(tests, spec, name, characters, fixture, steps, continues)` | Appends one strict recon test per character to `tests`: `"<character>: <name>"`, tagged `recon`, `vanilla`, `spec` (and `exit-continue` with `continues`, which gives each a 1000-update limit), fixture `fixture(c)`, steps `steps(c)`. |
| `continued` | A ready `{ label, step, when, limit }` pair: `exitAndContinue(true)` with a 600-update limit. |

## steps.lua

Steps that change the run by script, and guards. All engine-only, ceiling 600 unless noted.

| Name | Kind | Does, and waits for |
|---|---|---|
| `changeType(t)` | step | `ChangePlayerType(t)` on player 0; waits until player 0 is type `t`. |
| `addCard(card)` | step | `AddCard` on player 0; waits until it holds one more (`locked card?` otherwise). |
| `addTrinket(id)` | step | `AddTrinket` on player 0; waits until it holds it. |
| `useCard(card)` | step | `UseCard` on player 0 without holding it; then up to 30 updates for the player count to change; logs the count either way. Always passes. |
| `giveEsau(id, index)` | step | `AddCollectible c<id>` on Esau, or on GetPlayer(`index`) when given; waits for one more owned copy. |
| `giveType(id, t)` | step | `AddCollectible c<id>` on the first player of type `t`; waits for one more owned copy. |
| `keeperJoins` | step | Waits up to 60 updates for Strawman's Keeper (a Keeper with a Parent) to join. |
| `stepOff` | step | Moves player 0 80 px down, off a pedestal. |
| `info(what, f)` | step | Logs `INFO <test> <what> <f(player 0)>`. |
| `onlyIf(what, cond, step)` | step | Runs `step` only if `cond()` holds when it starts; else notes `skipped: <what>` on the RESULT line. |
| `holdsJr()` | reader | Player 0 holds Esau Jr. in the primary slot. |

## settle.lua

Waits for ReHUD to settle (no merge pending, no new character still settling).

| Name | Needs | Does |
|---|---|---|
| `look(label, verify)` | ReHUD | Waits up to 600 updates for ReHUD to settle (still settling then: an assertion fails), logs `SETTLED` and the state (`record.logState`), runs `verify(ctx, label)`, then asserts the invariants (`invariants.check`). |
| `lookC(label, verify)` | ReHUD | `look` that also asserts one row per character (`invariants.characterNumbers`). |
| `settled` | engine | The settle wait alone, capped at 120 updates, no assertions; logs how it ended. Passes at once without ReHUD. A step, not a function returning one. |

## esau_jr_steps.lua

Ready step lists around Esau Jr. Lists of `{ label, step }` pairs are for `snapshot.test`. All engine-only.

| Name | Kind | Does |
|---|---|---|
| `jrPair(label, who)` | pair | `{ label, step }`: an Esau Jr. `press` wrapped in `record.verdict` with `TIMING`; `who` as in `press.press`. |
| `flipV(label)` | step | `flip(label)` wrapped in `record.verdict`. |
| `regiveEsauJr()` | step | `give(ESAU_JR)`, unless player 0 still holds Esau Jr. in the primary slot (then logged and skipped). |
| `jrFirst()` | pairs | Esau Jr., then give c5. |
| `jrAgain()` | pairs | Re-give Esau Jr., press it again. |
| `jrTwice()` | pairs | `jrAgain()` plus a second re-give and press. |
| `giveClicker()` | pairs | Give Clicker, give c1. |
| `loseEsauJr()` | pairs | Checks Esau Jr. in primary (`pre`), gives D6, checks D6 replaced it and no Esau Jr. is owned. |
| `replaceEsauJr()` | pairs | `loseEsauJr()`, then re-give Esau Jr. |
| `esauLoses` | pairs | The same for GetPlayer index 1 (Esau): checks Esau Jr. there, `giveEsau(D6, 1)`, checks, gives Esau Jr. back. |
| `charPresses(who, first, lose)` | pairs | `first`, presses #1-#3, `lose` (default `replaceEsauJr()`), presses #4-#5. |
| `controlPresses()` | pairs | Two presses, each followed by an `INFO` of whether the remembered seeds are present. |
| `rememberOriginal` / `rememberForm` | step | Stores player 0's item seed as `ctx.originalSeed` / `ctx.formSeed`, for `controlPresses`. |
| `useClickerEffect` | step | `UseActiveItem(CLICKER)` on player 0 holding Esau Jr.; passes when the presser's type changed and Esau Jr. stayed in primary. |

## copies.lua

Copies with a clock: item wisps, the Zodiac copy, 3 Dollar Bill grants.

| Name | Needs | Does |
|---|---|---|
| `wisp(id)` | engine | `AddItemWisp(id)` on player 0; waits until its wisp count and `GetCollectibleNum(id, false)` both rose by 1. Ceiling 600. |
| `killWisp(id)` | engine | Kills one `c<id>` wisp of player 0; waits until both counts fell by 1. Ceiling 600. |
| `engineWisps(label, id, want)` | engine | Step asserting player 0 has `want` `c<id>` wisps; the label says the engine failed, not ReHUD. |
| `zodiacOn(label, ceiling)` | engine | Waits for player 0's Zodiac item (`GetZodiacEffect`), sets `ctx.zodiac`, `ctx.zodiacFloor`, `ctx.zodiacOld`. Without `ceiling`: none in 600 updates errors; with one: none by then is logged, not a fail. |
| `grant3DB` | engine | Waits up to 600 updates for a new 3 Dollar Bill grant on player 0 (held, not owned, not a wisp or the Zodiac item, not the last grant); sets `ctx.grant`. |
| `listed` | ReHUD | Waits up to 60 updates for one clocked ReHUD entry of `ctx.grant`. |

## characters.lua

Characters told apart by entity (GetPtrHash), each remembered with its items when last live, so a stored one can still be checked. All engine-only.

| Name | Kind | Does |
|---|---|---|
| `named(n, t)` | step | Names the character at index 0 (or the first of type `t`) `n`; errors if none. |
| `who(n)` | step | Asserts player 0 is the character named `n`; the label blames the engine. |
| `whoInfo(what)` | step | Logs who player 0 is, for an unobserved case. |
| `byName(n)` | reader | The record named `n`: `{ id, name, state, key, type, seed, hash, index, items }`. |
| `charOf(p)` | reader | The record of player `p`, or nil. |
| `track()` | reader | Refreshes the records now (new, live, stored, gone); the runner and the helpers call it. |
| `merged(c)` | reader | Marks record `c` gone. |

Internal: `onGameStart`.

## game.lua

Engine reads. No entity is kept: each lookup finds one now. All engine-only, no logging.

| Name | Returns |
|---|---|
| `seedOf(p)` | `p`'s item seed (`GetCollectibleRNG(1):GetSeed()`). |
| `seeds()` | Every player's item seed, comma-joined. |
| `owned(p, id)` | Owned copies of `c<id>` (`GetCollectibleNum(id, true)`). |
| `itemCounts(p)` | `{ [id] = copies }` with wisps and the Zodiac copy (`GetCollectibleNum(id, false)`). |
| `heldItems(p)` | `id:owned/total` for every item held, space-joined. |
| `countsText(t)` | An `itemCounts` table as `<id>x<n> ...`, or `-`. |
| `cards(p, id)` | Copies of card `id` held. |
| `chargeOf(p, id, slot)` | Active charge in `slot` if it holds `id`, else false/nil. |
| `slots(p)` | `primary <id> secondary <id>`. |
| `wispsOf(p)` | Item wisps of `p`: counts by item id, and the first wisp entity of each. |
| `pedestals(id)` | Pedestals of `c<id>` in the room. |
| `findPlayer(pred)` | The first player, and its index, for which `pred(p)` holds. |
| `ofType(t)` / `bySeed(seed)` / `byHash(h)` | The first player of that type / item seed / GetPtrHash. |
| `withParent(t)` | The first player of type `t` with a Parent (Strawman's Keeper, the temporary Esau). |
| `isCharacter(p)` / `characterCount()` | Whether `p` gets a ReHUD row (copy of ReHUD 2.8's rule) / how many players do. |
| `floorName()` | The floor's name (StageAPI's when it overrides the stage). |
| `ITEM_IDS`, `itemConfig` | Every collectible id, ascending; the item config. |

## ids.lua

Engine ids by name, from the game's `enums.lua`: items (`FLIP`, `ESAU_JR`, `CLICKER`, `BIRTHRIGHT`, `D6`, `YUM_HEART`, `SCHOOLBAG`, `STRAWMAN`, `ANKH`, `JUDAS_SHADOW`, `LAZARUS_RAGS`), the trinket `MISSING_POSTER`, cards (`SOUL_LAZARUS`, `SOUL_FORGOTTEN`, `SOUL_JACOB`), player types (`ISAAC`, `CAIN`, `LAZARUS`, `LAZARUS_RISEN`, `EDEN`, `KEEPER`, `JACOB`, `ESAU`, `FORGOTTEN`, `SOUL`, `T_ISAAC`, `T_LAZ`, `DEAD_T_LAZ`, `T_FORGOTTEN`, `T_SOUL`, `T_JACOB`), slots (`PRIMARY`, `SECONDARY`, `POCKET`) and `PEDESTAL`.

## rehud.lua

The only module that reads ReHUD (`ReHUD.dbg`). Copy its pattern to test your own mod.

| Name | Needs | Returns |
|---|---|---|
| `present()` | engine | Whether `ReHUD.dbg` is loaded. |
| `keyOf(p)` / `tagText(p)` | engine | ReHUD's key for `p` (its GetData tag, else its item seed) / the tag as text or `none`. |
| `entries()` | ReHUD | The tracker's entries: `{ id, owner, floor, number, temporary, left, merged }`. |
| `countEntries(pred)` / `leftEntries()` | ReHUD | Entries for which `pred(e)` holds / marked left. |
| `ownerOf(id)` | ReHUD | The owner of the last entry of `c<id>`. |
| `characterCount()` | ReHUD | ReHUD's character count. |
| `number(key)`, `isSwapped(key)`, `isSettling(key)`, `group(key)`, `rows()` | ReHUD | The roster by key: number, stored, still settling, group; every row. |
| `settling()` | engine | What ReHUD still settles (`a merge`, `a new character`) or nil; nil without ReHUD. |
| `storedSettling()` | engine | Keys of stored forms still settling, comma-joined; empty without ReHUD. |

## wait.lua

Build your own waiting step.

| Name | Does |
|---|---|
| `act(label, start, done, ceiling)` | A step: logs `ACTION <label>`, runs `start(ctx)` once, keeps its result as `ctx.before`, then polls `done(ctx, ctx.before)` (returning ok, why) every update; once ok, one more update, then `DONE`. At `ceiling` (default 600) errors with the last why. |
| `condition(label, cond)` | `act` that does nothing and waits up to 60 updates for `cond()`. |
| `TIMEOUT`, `CONTINUE_TIMEOUT` | 600 and 9000 updates. |

Internal: `resetStep`.

## log.lua

`P(...)`: one line, its arguments joined by spaces, to the console and to `log.txt` as `Lua Debug: PROBE ...`. Log `P("INFO", ctx.name, ...)` so `report.py` shows the line under its test.

## callbacks.lua

Callback counts, for `assert.fired`. `mark()`: the counts now; `since(m, id, arg)`: how often callback `id` fired with `arg` after `m`. `main.lua` registers the counters (`count`); the runner clears them (`reset`).

## invariants.lua

What every `look` asserts, ReHUD only: `check(ctx, label)` (ReHUD's entries match the engine's counts, copies with a clock clocked, no duplicates, no phantom stored forms, no `left` entries unless the test sets `leftOk`, no floor later than the current one) and `characterNumbers(ctx, label)` (every remembered character has its own row, a stored one listed with the copies it held; logs `NUMBERS`). Called by `settle.look` and `lookC`.

## runner.lua

For specs only `expectStart(kind)`: tells the runner the next game start is expected, `"new"` or `"continue"`, so it does not fail the test as unexpected (the `revive` spec's restarts). `abort(why)` FAILs the test past any `onStepError` policy. The rest (`add`, `on`, `tick`, `guard`, `render`, `onGameStart`, `stuck`, `setMod`, `markWait`, `tests`) wires `main.lua` and the other modules.
