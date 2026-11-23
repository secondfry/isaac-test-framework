# Engine facts

The Repentance+ engine behaviour (vanilla, v1.9.7.19.J510, no REPENTOGON) that the harness code and its stub rely on. Each fact was observed in game; the label names where:

- `session <n>`, `run <n>`, `obsx<n>`, `obsya<n>`, `obsyb<n>`: an in-game harness session (the labels the code's comments cite).
- `console probe`: a manual probe from the debug console, outside the harness.

What no session has shown is marked unobserved, and stays a recon test (no assertions) until a session shows it.

## Player entities

- A removed player (Esau after Clicker, an old Esau after `restart 19` twice) still answers `GetPlayerType`, `.Index` and `.Damage`, but `HasCollectible` on it crashes the game natively, past any `pcall`. Observed in game (console probe, 3 of 3). So the harness keeps no entity: it looks players up by `GetPtrHash`, and calls no method on a wisp's `Player`, a returned twin or a `Parent`, which may be removed.
- `GetPtrHash` is the entity's address: each character and each form has its own, kept through Flip; an Esau Jr. swap back restores the exact hashes from before the swap. A Continue gives every player a new one, and a hash is later reused by another character. Observed in game (obsyb1, obsyb2).
- No stable per-character key exists: item seeds are shared in the cases under Seeds, `GetPtrHash` renews on Continue, `Index` changes (Esau Jr. swap back, Continue). Observed in game (obsyb2).

## Stored characters

- A stored character (Tainted Lazarus's other form without Birthright, an Esau Jr. original) is invisible to Lua: `Isaac.FindByType(1)` and `GetNumPlayers` return only the one playing. Its items are known only from when it last played. Observed in game (console probe, Tainted Lazarus with three stored characters).
- A stored form comes back only by Flip (Tainted Lazarus without Birthright) or by pressing the Esau Jr. copy that holds it. Observed in game (obsx1-3, obsya1, obsyb1-2).
- Each Esau Jr. copy holds the character it last swapped out, wherever the copy lies (pedestal, Schoolbag, through a Continue). A copy's first press makes a new character; a later press brings back the one it holds. A destroyed copy (displaced by `giveitem`, rerolled by D6) leaves its character unreachable, and a fresh copy makes a new one. Observed in game (obsx1-3, obsya1, obsyb1-2).
- After the returned original loses Esau Jr. and gets it back, the next press brings a form with the stored form's seed and type but other items. Observed in game (obsx2, obsx3).
- Clicker with Esau Jr. kept: the next press brings the original back, typed as the presser's new type. Observed in game (obsx1, obsx2, obsya1).
- A stored original survives save and Continue and returns on the next press. Observed in game (obsyb1-2).
- Every new Esau Jr. form holds Esau Jr. on its first update. Observed in game (obsya1).

## Seeds

- `GetCollectibleRNG(1):GetSeed()` (the item seed) is stable per form across Flip, Esau Jr. and Exit & Continue. Observed in game (obsya1, obsyb1, obsyb2).
- An Esau Jr. form usually gets a new seed. On Tainted Lazarus (type 29) with another form, the Esau Jr. form takes that other form's (the Dead form's) item seed and InitSeed. Observed in game (obsyb1-2, console probe).
- After a Continue, a press after the original lost Esau Jr. makes a form with the old form's seed and type, and later presses swap the two same-seed forms. Observed in game (obsyb1-2).
- Clicker changes the type and keeps the seed; Lazarus's revive (8 -> 11) and The Forgotten's switch to The Soul (16 <-> 17) change the type in place, same seed and `GetPtrHash`. Observed in game (run 1, console probe).
- The `seed <start seed>` console command restarts on that seed; later `restart <type>` commands keep it, and so do Exit & Continues. Observed in game (session 1, session 2).

## Driving the game from Lua

- `Isaac.ExecuteCommand("restart <type>")` from `MC_POST_RENDER`, `player:ChangePlayerType(t)`, `player:UseCard(Card.CARD_SOUL_JACOB, 0)` with the card not held, and `UseActiveItem` for Flip (711) and Clicker (482) all work from a mod callback. Soul of Jacob and Esau's Esau is type 20 with a `Parent`. Observed in game (run 1, run 2).
- `UseActiveItem(703, 0)` (Esau Jr.) does nothing, held or not. Observed in game (runs 1 and 2).
- Teleporting a player onto a pedestal, or moving it there every update, never counts as touching it, so the walk steps ask the player to walk. Observed in game (obsya1, obsya2).
- A press: returning `true` from `MC_INPUT_ACTION` on `IS_ACTION_TRIGGERED` once works for `ACTION_ITEM` and for a card on `ACTION_PILLCARD`; a pocket active (Flip) needs every poll of that update answered. Observed in game (runs 2-5).
- `FullCharge` without force fills the first bar only (Flip: charge 4, battery 0); REP+ Flip takes 4 charges though `MaxCharges` reads 6. Observed in game (run 3).
- Beside a pocket active a new card lands in slot 1. Observed in game (run 5).
- A stored presser's spend (Esau Jr., Flip without Birthright) can be read on its own entity on `MC_INPUT_ACTION` and `MC_POST_PLAYER_UPDATE`, after its `MC_USE_ITEM` and before the engine stores it. Observed in game (runs 6 and 7).
- Clicker changes the type before `MC_USE_ITEM`; a Clicker vetoed in `MC_PRE_USE_ITEM` spends its charge, keeps the type and fires no `MC_USE_ITEM`. Observed in game (obsx1).
- `MC_POST_PLAYER_UPDATE` runs twice per game frame. Observed in game (obsya1).

## Revives

- Lazarus holding Soul of Lazarus, Lazarus' Rags, Ankh, Judas' Shadow and Missing Poster, dying by `player:Kill()` each time: Soul of Lazarus first (stays type 8), then his innate revive (8 -> 11), Rags (stays 11), Ankh (11 -> 4), Judas' Shadow (4 -> 12); the sixth death gave no revive with Missing Poster held, and the game ended. Observed in game (session 2).
- Each source alone on a fresh Lazarus: Soul of Lazarus and the innate revive revive him on death 1; with Rags, Ankh or Judas' Shadow the innate revive comes first and the item on death 2, the item then gone. Each was alive again 57 updates after its `Kill()`, same `GetPtrHash`. Observed in game (session 3b).
- Missing Poster alone: the innate revive on death 1, Poster kept; death 2 gave no revive and reached game over with the Poster still held. Why (The Lost locked on that save?) is unobserved. Observed in game (session 3d).
- The game over shows the death certificate, which waits for a Space press; the engine does not restart by itself. Observed in game (session 3a).
- On the certificate updates stop (at 57 updates dead) while renders run on; before it, 2 renders per update. A console `restart 0` sent from a render there starts a new game within 1 render, no Space needed. Observed in game (session 3c).
