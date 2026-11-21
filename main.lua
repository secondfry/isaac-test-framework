-- ReHUD test harness: on the first new run after launch it plays SCENARIOS by itself and logs PROBE/RESULT lines to log.txt.
-- Needs the `ReHUD.dbg` hook (ReHUD eeae5c0 or later).
local mod = RegisterMod("ReHUD Test Harness", 1)
local game = Game()
local itemConfig = Isaac.GetItemConfig()
local maxId = itemConfig:GetCollectibles().Size - 1

-- shortcut: ceilings count updates only, so a paused game or menu stalls the run with no fail; add a wall-clock ceiling if that bites.
local TIMEOUT, CONTINUE_TIMEOUT = 600, 9000 -- ceilings in updates, not waits: 20 s; 5 min of play for the user's exit and Continue

local function P(...)
	local t = {}
	for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
	local s = table.concat(t, " ")
	print(s)
	Isaac.DebugString("PROBE " .. s)
end

-- Lua state survives `restart` and exit/continue, so the state lives in a global; a reload of this file keeps it.
-- shortcut: one pass per launch, and a native crash restarts the suite from the first scenario; add a rerun trigger, or SaveData resume, when either gets in the way.
HARNESS = HARNESS or { started = false, running = false, gen = 0, si = 1, pi = 1, fired = 0, ctx = { floors = {}, fails = {} }, status = "waiting for a run" }

-- shortcut: copy of tracker.lua currentFloorName (the tracker stores this string as `entry.floor`); expose it on ReHUD.dbg if the copy drifts.
local function floorName()
	if StageAPI and StageAPI.Loaded and StageAPI.InOverriddenStage() then
		local name = StageAPI.GetCurrentStageDisplayName()
		if name then return name end
	end
	return game:GetLevel():GetName()
end

local function seedOf(p) return p:GetCollectibleRNG(1):GetSeed() end

local function dbg()
	local d = ReHUD and ReHUD.dbg
	if not (d and d.tracker and d.roster) then error("ReHUD.dbg missing: install ReHUD eeae5c0 or later") end
	return d
end

local function entries() return dbg().tracker.entries end

local function playerOfType(t)
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if p:GetPlayerType() == t then return p, i end
	end
end

local function playerBySeed(seed)
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if seedOf(p) == seed then return p end
	end
end

local function owned(p, id) return p:GetCollectibleNum(id, true) end

-- Copies of card `id` held; slots 0-3 cover every pocket slot, and GetCard reads 0 for an empty one.
local function cards(p, id)
	local n = 0
	for i = 0, 3 do
		if p:GetCard(i) == id then n = n + 1 end
	end
	return n
end

local function probe(ctx, label)
	P("STEP", ctx.name, label, "floor", floorName(), "stage", game:GetLevel():GetStage())
	local wisps = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP)
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		P("PLAYER", i, "type", p:GetPlayerType(), "ctrl", p.ControllerIndex, "variant", p.Variant, "parent", p.Parent ~= nil,
			"ghost", p:IsCoopGhost(), "seed", seedOf(p), "count", p:GetCollectibleCount())
		local hash, wispOf = GetPtrHash(p), {}
		for _, e in ipairs(wisps) do
			local f = e:ToFamiliar()
			if f and f.Player and GetPtrHash(f.Player) == hash then wispOf[e.SubType] = (wispOf[e.SubType] or 0) + 1 end
		end
		for id = 1, maxId do
			if itemConfig:GetCollectible(id) then
				local all = p:GetCollectibleNum(id, false)
				if all > 0 then
					local own, w = owned(p, id), wispOf[id] or 0
					P("ITEM", i, "c" .. id, "owned", own, "wisp", w, "other", all - own - w)
				end
			end
		end
	end
	for n, e in ipairs(entries()) do
		P("ENTRY", n, "c" .. e.id, "number", e.number, "owner", e.owner, "floor", e.floor, "temporary", e.temporary, "left", e.left, "merged", e.merged)
	end
end

local function fail(ctx, why)
	table.insert(ctx.fails, why)
	P("CHECK FAIL", ctx.name, why)
end

-- Exactly `n` ReHUD entries of item `id`, each on `floor` and owned by `owner` when given.
local function expectN(ctx, label, id, n, floor, owner)
	ctx.checks = (ctx.checks or 0) + 1
	local found = {}
	for _, e in ipairs(entries()) do
		if e.id == id then table.insert(found, e) end
	end
	if #found ~= n then return fail(ctx, label .. ": c" .. id .. " has " .. #found .. " entries, want " .. n) end
	for _, e in ipairs(found) do
		if floor and e.floor ~= floor then fail(ctx, label .. ": c" .. id .. " on '" .. tostring(e.floor) .. "', want '" .. floor .. "'") end
		if owner and e.owner ~= owner then fail(ctx, label .. ": c" .. id .. " owner " .. tostring(e.owner) .. ", want " .. owner) end
	end
end
local function expectOne(ctx, label, id, floor, owner) expectN(ctx, label, id, 1, floor, owner) end

-- A probe with an expected answer: logged as INFO, and a check.
local function expect(ctx, label, got, want)
	ctx.checks = (ctx.checks or 0) + 1
	P("INFO", ctx.name, label, got)
	if got ~= want then fail(ctx, label .. ": " .. tostring(got) .. ", want " .. tostring(want)) end
end

-- A step is function(ctx) returning "again" to run itself next update, anything else to move on.
-- Console commands are queued for MC_POST_RENDER, not run in the middle of other mods' MC_POST_UPDATE.

-- An action: `act(ctx)` runs once and its result is kept as `ctx.before`; then `done(ctx, ctx.before)` is polled every update until it
-- returns true, or the step errors naming `label` at the ceiling. One more update follows, so ReHUD's MC_POST_UPDATE has seen the
-- effect whatever the mod load order (not guaranteed, AGENTS.md).
local function action(label, act, done, ceiling)
	return function(ctx)
		if not ctx.t then
			ctx.t, ctx.label = 0, label
			P("ACTION", label, "by type", Isaac.GetPlayer(0):GetPlayerType())
			ctx.before = act(ctx)
			return "again"
		end
		ctx.t = ctx.t + 1
		if ctx.held then
			P("DONE", label, "after", ctx.t - 1, "updates")
			ctx.t, ctx.held, ctx.before = nil, nil, nil
			return
		end
		local ok, why = done(ctx, ctx.before)
		if ok then ctx.held = true return "again" end
		if ctx.t >= (ceiling or TIMEOUT) then error(label .. ": " .. (why or "no effect") .. " after " .. ctx.t .. " updates") end
		return "again"
	end
end

-- giveitem/remove by console on player 0: one copy more or less, and `players` players when given (Birthright on Tainted Lazarus: 2, removed: 1).
local function changeOwned(verb, id, delta, players)
	return action(verb .. " c" .. id, function()
		HARNESS.pending = verb .. " c" .. id
		return owned(Isaac.GetPlayer(0), id)
	end, function(_, n)
		if owned(Isaac.GetPlayer(0), id) ~= n + delta then return false, "owned copies did not change by " .. delta end
		if players and game:GetNumPlayers() ~= players then return false, game:GetNumPlayers() .. " players, want " .. players end
		return true
	end)
end
local function give(id, players) return changeOwned("giveitem", id, 1, players) end
local function remove(id, players) return changeOwned("remove", id, -1, players) end

local function giveEsau(id)
	return action("Esau AddCollectible c" .. id, function()
		local esau = playerOfType(PlayerType.PLAYER_ESAU)
		if not esau then error("no Esau (type 20) to give c" .. id) end
		local n = owned(esau, id)
		esau:AddCollectible(id)
		return n
	end, function(_, n)
		local esau = playerOfType(PlayerType.PLAYER_ESAU)
		return esau and owned(esau, id) == n + 1, "Esau's owned copies did not rise by 1"
	end)
end

-- Records the new floor as ctx.floors[n]; an unchanged name would make every floor check meaningless.
local function stage(n)
	return action("stage " .. n, function()
		HARNESS.pending = "stage " .. n
		return floorName()
	end, function(ctx, old)
		if game:GetLevel():GetStage() ~= n then return false, "stage is " .. game:GetLevel():GetStage() end
		if floorName() == old then return false, "floor name unchanged: floor checks inconclusive" end
		ctx.floors[n] = floorName()
		P("FLOOR", n, ctx.floors[n])
		return true
	end)
end

-- A new (not continued) game with player 0 of type `t`; records floor 1.
local function restart(t)
	return action("restart " .. t, function()
		local H = HARNESS
		H.pending, H.expectStart = "restart " .. t, true
		return H.gen
	end, function(ctx, gen)
		local H = HARNESS
		if H.gen == gen or game:GetNumPlayers() == 0 then return false, "no new game" end
		if H.continued then error("restart " .. t .. " continued a run") end
		local got = Isaac.GetPlayer(0):GetPlayerType()
		if got ~= t then return false, "player 0 is type " .. got .. " (character locked?)" end
		ctx.floors[1] = floorName()
		P("FLOOR", 1, ctx.floors[1])
		return true
	end)
end

local function seeds()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do t[#t + 1] = seedOf(Isaac.GetPlayer(i)) end
	return table.concat(t, ",")
end

-- The user exits to the menu and continues: a continued game with the same players (seeds) as before the exit.
local function exitAndContinue()
	return action("exit to the menu and Continue now", function()
		HARNESS.expectStart = true
		return { gen = HARNESS.gen, seeds = seeds() }
	end, function(ctx, b)
		local H = HARNESS
		if H.gen == b.gen then
			if ctx.t % 300 == 0 then P("ACTION exit to the menu and Continue now") end
			return false, "no Continue"
		end
		if not H.continued then error("a new run started, not a Continue") end
		return seeds() == b.seeds, "players " .. seeds() .. ", want " .. b.seeds
	end, CONTINUE_TIMEOUT)
end

-- Not a press, so only the new-character half of the swap rule applies: there is no item to spend.
local function changeType(t)
	return action("ChangePlayerType " .. t, function() Isaac.GetPlayer(0):ChangePlayerType(t) end,
		function() return Isaac.GetPlayer(0):GetPlayerType() == t, "player 0 is type " .. Isaac.GetPlayer(0):GetPlayerType() end)
end

local function snapshot()
	local p = Isaac.GetPlayer(0)
	return { count = game:GetNumPlayers(), who = p:GetPlayerType() .. "/" .. seedOf(p) }
end

-- A real press: HARNESS.press is answered true once, on the first triggered poll of that button by player 0 (one-shot, so a card
-- press cannot also use the next pocket item); HARNESS.flood keeps answering until cleared (the probes' double-fire test).
-- HARNESS.hold, while set, also holds the button: IS_ACTION_PRESSED true, and with `value` GET_ACTION_VALUE 1 (pocket press modes b, c).
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, e, hook, button)
	local H = HARNESS
	if not (H.press or H.hold) or not e or GetPtrHash(e) ~= GetPtrHash(Isaac.GetPlayer(0)) then return end -- polled ~1470/s: cheap exit first
	if hook == InputHook.IS_ACTION_TRIGGERED then
		if button ~= H.press then return end
		if not H.flood then H.press = nil end
		H.fired = H.fired + 1
		return true
	end
	local hold = H.hold
	if not hold or button ~= hold.button or (hook == InputHook.GET_ACTION_VALUE and not hold.value) then return end
	H.polls[hook] = (H.polls[hook] or 0) + 1
	if hook == InputHook.GET_ACTION_VALUE then return 1.0 end
	return true
end)

local function chargeOf(p, id, slot) return p and p:GetActiveItem(slot) == id and p:GetActiveCharge(slot) end

-- How the use spent `id`, or nil and what was read. `b` is the presser before the press: its seed and full charge or card count.
-- shortcut: a new player 0 is compared with the presser's full charge, so a form that comes back already drained passes; drop that side
-- once the probes show which entity holds the spent charge.
local function spentHow(b, id, slot, gone)
	local presser = playerBySeed(b.seed) -- a seed lookup, not a kept entity: the presser may be gone (AGENTS.md)
	if slot == "card" then
		local n = presser and cards(presser, id)
		if n == b.cards - 1 then return "card " .. b.cards .. "->" .. n end
		return nil, "card count " .. tostring(n) .. ", was " .. b.cards
	end
	local c1, c0 = chargeOf(presser, id, slot), chargeOf(Isaac.GetPlayer(0), id, slot)
	local read = "charge " .. b.charge .. " -> presser " .. tostring(c1) .. ", player 0 " .. tostring(c0)
	if c1 and c1 < b.charge then return "presser charge, " .. read end
	if c0 and c0 < b.charge then return "player 0 charge, " .. read end
	if gone and presser and presser:GetActiveItem(slot) ~= id then return "item gone, " .. read end
	return nil, read
end

local HOLD = 5 -- updates a held press (modes b, c) stays down, then as many up before the next arm, so each arm is a fresh press

local function arm(H, b) H.press, H.hold, b.arms = b.button, b.hold, b.arms + 1 end

-- Every character swap: player 0 presses `id` (active in `slot`, or a held card with slot "card"), and it is done only when a new
-- character appears (`count` players after, when given) and the use spent the charge, the card, or with `gone` the item.
-- `mode` is the pocket press: "a" triggered only (cards and ACTION_ITEM, verified in run 2), "b" also held, "c" also an action value.
-- Run 2: a triggered PILLCARD never used Flip, so a pocket press takes the mode the probes found, or b.
local function swap(label, id, slot, count, gone, mode, ceiling)
	local button = slot == ActiveSlot.SLOT_PRIMARY and ButtonAction.ACTION_ITEM or ButtonAction.ACTION_PILLCARD
	return action(label, function()
		local p, H = Isaac.GetPlayer(0), HARNESS
		local b = snapshot()
		b.seed, b.button, b.mode = seedOf(p), button, slot == ActiveSlot.SLOT_POCKET and (mode or H.pocketMode or "b") or "a"
		if b.mode ~= "a" then b.hold = { button = button, value = b.mode == "c" } end
		local read = ""
		if slot == "card" then
			b.cards = cards(p, id)
			if b.cards == 0 then error(label .. ": card " .. id .. " not held") end
		else
			if p:GetActiveItem(slot) ~= id then error(label .. ": c" .. id .. " not in slot " .. slot) end
			-- Full, so a drop is visible. ItemConfig MaxCharges reads 6 for Flip, but REP+ Flip takes 4, and SetActiveCharge(6, 2) gave
			-- 4 + 2 battery (user, in game); FullCharge without force fills the first bar only when no Battery is held (IsaacDocs).
			if slot == ActiveSlot.SLOT_POCKET then p:FullCharge(slot) else p:SetActiveCharge(itemConfig:GetCollectible(id).MaxCharges, slot) end
			b.charge = p:GetActiveCharge(slot)
			read = " charge " .. b.charge .. " battery " .. p:GetBatteryCharge(slot)
		end
		H.polls, b.arms, b.n, b.fired = {}, 0, 0, H.fired
		arm(H, b)
		P("PRESS", label, "button", button, "mode", b.mode .. read)
		return b
	end, function(ctx, b)
		local H, a = HARNESS, snapshot()
		if a.who == b.who and a.count == b.count then
			b.n = b.n + 1
			-- shortcut: mode a re-arms each update until a new character shows, in case the first poll was not the use logic; a press taken
			-- but shown late could fire twice, harmless while the charge is spent; wait a frame before re-arming if probes show that.
			if not b.hold then
				if not H.press then arm(H, b) end
			elseif b.n % (2 * HOLD) == HOLD then H.hold = nil
			elseif b.n % (2 * HOLD) == 0 then arm(H, b) end
			-- fired 0: the use logic never polled the triggered press; pressed/value: held polls answered
			return false, "no new character, mode " .. b.mode .. ", arms " .. b.arms .. ", fired " .. (H.fired - b.fired)
				.. ", pressed " .. (H.polls[InputHook.IS_ACTION_PRESSED] or 0) .. ", value " .. (H.polls[InputHook.GET_ACTION_VALUE] or 0)
		end
		H.press, H.hold = nil, nil
		if count and a.count ~= count then return false, a.count .. " players, want " .. count end
		local how, read = spentHow(b, id, slot, gone)
		if not how then return false, "spent nothing: " .. read end
		ctx.arms = b.arms
		P("SWAP", label, b.who, "->", a.who, "players", b.count, "->", a.count, "spent", how, "mode", b.mode, "arms", b.arms, "fired", H.fired - b.fired,
			"pressed", H.polls[InputHook.IS_ACTION_PRESSED] or 0, "value", H.polls[InputHook.GET_ACTION_VALUE] or 0)
		return true
	end, ceiling)
end

local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT = CollectibleType.COLLECTIBLE_FLIP, CollectibleType.COLLECTIBLE_ESAU_JR, CollectibleType.COLLECTIBLE_CLICKER, CollectibleType.COLLECTIBLE_BIRTHRIGHT
local T_LAZ, JE, ISAAC = PlayerType.PLAYER_LAZARUS_B, PlayerType.PLAYER_JACOB, PlayerType.PLAYER_ISAAC

local function flip(label) return swap(label, FLIP, ActiveSlot.SLOT_POCKET) end
local function esauJr(label) return swap(label, ESAU_JR, ActiveSlot.SLOT_PRIMARY) end
-- Run Soul of J&E on a character with no pocket active (Isaac): beside Flip, PILLCARD may use Flip instead (research-review R4).
local soulJE = swap("Soul of Jacob and Esau", Card.CARD_SOUL_JACOB, "card", 2)

local function addCard(card)
	return action("AddCard " .. card, function()
		local p = Isaac.GetPlayer(0)
		local n = cards(p, card)
		p:AddCard(card)
		return n
	end, function(_, n) return cards(Isaac.GetPlayer(0), card) == n + 1, "card count did not rise by 1 (locked card?)" end)
end

-- What ReHUD is still settling, or nil. The roster key is the Sad Onion RNG seed (roster.lua playerKey), which is seedOf.
local function settling()
	for _, e in ipairs(entries()) do
		if e.merged then return "a merge" end
	end
	local roster = dbg().roster
	for i = 0, game:GetNumPlayers() - 1 do
		if roster.isSettling(seedOf(Isaac.GetPlayer(i))) then return "a new character" end
	end
end

-- Once ReHUD has settled: probe, then run `check(ctx, label)` if given.
local function look(label, check)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local busy = settling()
		if busy and ctx.t < TIMEOUT then return "again" end
		if busy then fail(ctx, label .. ": ReHUD still settling " .. busy .. " after " .. ctx.t .. " updates") end
		P("SETTLED", label, "after", ctx.t, "updates")
		ctx.t = nil
		probe(ctx, label)
		if check then check(ctx, label) end
	end
end

local function c4c5(ctx, label)
	expectOne(ctx, label, 4, ctx.floors[1])
	expectOne(ctx, label, 5, ctx.floors[2])
end
local function oneC4(ctx, label) expectOne(ctx, label, 4, ctx.floors[1]) end
local function twoC4(ctx, label) expectN(ctx, label, 4, 2, ctx.floors[1], seedOf(Isaac.GetPlayer(0))) end

local clicker = swap("Clicker", CLICKER, ActiveSlot.SLOT_PRIMARY, nil, true) -- charged or consumed: unverified, so either counts
local clickerLook = look("after Clicker", function(ctx, label)
	local n = 0
	for i = 0, game:GetNumPlayers() - 1 do n = n + owned(Isaac.GetPlayer(i), 4) end
	expectN(ctx, label .. " " .. ctx.uses, 4, n, ctx.floors[1])
end)

-- Clicker on Jacob until it is Jacob & Esau again, up to 20 uses (each refilled by the swap); each use is a checked swap followed by
-- a settled probe. A random character may never land on J&E, so a missed split is INFO, and the merge checks still count.
local function clickerLoop(ctx)
	if not ctx.phase then
		if ctx.back then return end
		if (ctx.uses or 0) >= 20 then return P("INFO", ctx.name, "split not reached in 20 Clicker uses") end
		ctx.uses, ctx.phase = (ctx.uses or 0) + 1, "press"
		local p = Isaac.GetPlayer(0)
		if p:GetActiveItem() ~= CLICKER then p:AddCollectible(CLICKER) end -- a consumed Clicker is given again
		if p:GetActiveItem() ~= CLICKER then error("Clicker not in the active slot after AddCollectible") end
	end
	if ctx.phase == "press" then
		if clicker(ctx) == "again" then return "again" end
		ctx.phase = "look"
	end
	if clickerLook(ctx) == "again" then return "again" end
	ctx.phase = nil
	ctx.back = Isaac.GetPlayer(0):GetPlayerType() == JE and playerOfType(PlayerType.PLAYER_ESAU) ~= nil
	return "again"
end

-- Probes for what research-review.md left to an in-game check.

local function maxCharges(ctx)
	for _, c in ipairs({ { CLICKER, 6 }, { ESAU_JR, 1 }, { FLIP, 6 } }) do -- want: pre-REP+ items.xml
		expect(ctx, "MaxCharges c" .. c[1], itemConfig:GetCollectible(c[1]).MaxCharges, c[2])
	end
end

-- Diagnosis only (run 1: UseActiveItem(703, 0) never swapped): does slot 0, with these flags, swap plain Isaac within 30 updates?
local function esauJrDirect(flags)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		if ctx.t == 1 then
			ctx.before = snapshot()
			Isaac.GetPlayer(0):UseActiveItem(ESAU_JR, flags, ActiveSlot.SLOT_PRIMARY)
			return "again"
		end
		local a = snapshot()
		if a.who == ctx.before.who and ctx.t < 30 then return "again" end
		P("INFO", ctx.name, "UseActiveItem(703, flags " .. flags .. ", slot 0):", a.who == ctx.before.who and "no swap" or "swapped", ctx.before.who, "->", a.who)
		ctx.t, ctx.before = nil, nil
	end
end

-- REP+ Flip takes 4 though MaxCharges reads 6 (user, in game): SetActiveCharge(6) should read 4 + 2 battery; the swap uses FullCharge(2).
local function pocketCharge(ctx)
	local p, s = Isaac.GetPlayer(0), ActiveSlot.SLOT_POCKET
	expect(ctx, "pocket item", p:GetActiveItem(s), FLIP)
	P("INFO", ctx.name, "ChargeType c711", itemConfig:GetCollectible(FLIP).ChargeType)
	local function read(how) P("INFO", ctx.name, how, "charge", p:GetActiveCharge(s), "battery", p:GetBatteryCharge(s), "needs charge", p:NeedsCharge(s)) end
	for _, n in ipairs({ 0, itemConfig:GetCollectible(FLIP).MaxCharges }) do
		p:SetActiveCharge(n, s)
		read("after SetActiveCharge " .. n)
	end
	p:SetActiveCharge(0, s)
	read("FullCharge(2) returned " .. tostring(p:FullCharge(s)))
end

local function onePress(label) return function(ctx) expect(ctx, label .. ": arms needed", ctx.arms, 1) end end

-- Which pocket press mode uses Flip: a, b, c in turn, 150 updates each (30 arms in a, 15 in b and c), up to the first that swaps. The
-- answer becomes HARNESS.pocketMode for every later Flip; a mode that fails is INFO here, and the later Flips fail on their own.
local POCKET_MODES = { "a", "b", "c" }
local flipTries = {}
for i, m in ipairs(POCKET_MODES) do flipTries[i] = swap("Flip mode " .. m, FLIP, ActiveSlot.SLOT_POCKET, nil, nil, m, 150) end
local function findPocketMode(ctx)
	local i = ctx.try or 1
	local ok, res = pcall(flipTries[i], ctx)
	if ok and res == "again" then return "again" end
	ctx.t, ctx.held, ctx.before, HARNESS.press, HARNESS.hold = nil, nil, nil, nil, nil
	if ok then
		ctx.try, HARNESS.pocketMode = nil, POCKET_MODES[i]
		return P("INFO", ctx.name, "pocket press mode that swaps", POCKET_MODES[i])
	end
	P("INFO", ctx.name, "pocket press mode", POCKET_MODES[i], "failed:", res)
	if i == #POCKET_MODES then
		ctx.try = nil
		return P("INFO", ctx.name, "no pocket press mode swaps; later Flips use b")
	end
	ctx.try = i + 1
	return "again"
end

-- One press fires at most once: with two Fools held, PILLCARD is answered true on every poll for one update; one card may go.
local floodCards = action("PILLCARD forced for one update, two cards held", function()
	local H, n = HARNESS, cards(Isaac.GetPlayer(0), Card.CARD_FOOL)
	if n ~= 2 then error("want 2 Fools held, have " .. n) end
	H.press, H.flood = ButtonAction.ACTION_PILLCARD, true
	return { n = n, fired = H.fired }
end, function(ctx, b)
	local H = HARNESS
	H.press, H.flood = nil, nil -- the window closes at the first poll of `done`: one update
	local n = cards(Isaac.GetPlayer(0), Card.CARD_FOOL)
	if n == b.n then return false, "no card used" end
	P("INFO", ctx.name, "polls answered in one update", H.fired - b.fired)
	expect(ctx, "cards used by one forced update", b.n - n, 1)
	return true
end)

local function clickerHeld(ctx)
	local p = Isaac.GetPlayer(0)
	expect(ctx, "active after a real Clicker press", p:GetActiveItem(), CLICKER)
	P("INFO", ctx.name, "Clicker charge after the press", p:GetActiveCharge())
end

local function cardBesideFlip(ctx)
	local p = Isaac.GetPlayer(0)
	P("INFO", ctx.name, "Soul of J&E beside Flip: cards", p:GetCard(0), p:GetCard(1), p:GetCard(2), p:GetCard(3), "pocket active", p:GetActiveItem(ActiveSlot.SLOT_POCKET))
end

local SCENARIOS = {
	-- Steps that never error come first: an action that times out ends the scenario.
	{ name = "probes", steps = {
		restart(ISAAC), maxCharges, give(ESAU_JR), esauJrDirect(0), esauJrDirect(UseFlag.USE_OWNED),
		restart(ISAAC), give(ESAU_JR), esauJr("Esau Jr."), onePress("Esau Jr."),
		give(CollectibleType.COLLECTIBLE_POLYDACTYLY), addCard(Card.CARD_FOOL), addCard(Card.CARD_FOOL), floodCards,
		give(CLICKER), give(1), clicker, clickerHeld, -- c1 after Clicker, so Clicker's 50% item removal takes c1, not Clicker
		restart(T_LAZ), addCard(Card.CARD_SOUL_JACOB), cardBesideFlip,
		restart(T_LAZ), pocketCharge, findPocketMode, -- last: in run 2 the Flip press timed out and skipped every probe after it
	} },
	{ name = "test3", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), look("before ChangePlayerType"), changeType(ISAAC),
		look("after ChangePlayerType", function(ctx, label)
			c4c5(ctx, label)
			local key = seedOf(Isaac.GetPlayer(0))
			expectOne(ctx, label .. " (Isaac owns)", 4, nil, key)
			expectOne(ctx, label .. " (Isaac owns)", 5, nil, key)
		end),
	} },
	{ name = "birthright", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), give(BIRTHRIGHT, 2), look("after Birthright", c4c5),
		flip("Flip 1 of 2"), look("after Flip 1", c4c5), flip("Flip 2 of 2"), look("after two Flips", c4c5),
		stage(3), look("on stage 3", c4c5),
	} },
	{ name = "P3", steps = {
		restart(T_LAZ), give(4), stage(2), look("after c4", oneC4),
		give(BIRTHRIGHT, 2), look("after Birthright", oneC4),
		remove(BIRTHRIGHT, 1), look("after remove Birthright", oneC4),
		flip("Flip"), look("after Flip", oneC4),
	} },
	{ name = "P4a", steps = {
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("after c4", oneC4),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", oneC4), esauJr("Esau Jr. 2"), look("after Esau Jr. 2", oneC4),
	} },
	{ name = "P4b", steps = {
		restart(JE), give(ESAU_JR), look("start"),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1"), esauJr("Esau Jr. 2"), look("after Esau Jr. 2"),
	} },
	{ name = "P1", steps = {
		restart(ISAAC), give(4), give(4), stage(2), look("before Soul of Jacob and Esau", twoC4),
		addCard(Card.CARD_SOUL_JACOB), soulJE, look("after Soul of Jacob and Esau", twoC4),
		giveEsau(1), look("after Esau c1", twoC4), stage(3), look("on stage 3", twoC4),
	} },
	{ name = "P2", steps = {
		restart(JE), give(4), give(4), give(4), give(4), giveEsau(4), give(CLICKER), stage(2), look("start"), clickerLoop,
	} },
	{ name = "continue", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), look("before exit"), exitAndContinue(), changeType(ISAAC),
		look("after continue and ChangePlayerType", function(ctx, label) expectOne(ctx, label, 4, ctx.floors[1], seedOf(Isaac.GetPlayer(0))) end),
	} },
}

local function finish(err)
	local H = HARNESS
	local sc, ctx = SCENARIOS[H.si], H.ctx
	local verdict
	if err then
		verdict = "FAIL " .. err
	elseif #ctx.fails > 0 then
		verdict = "FAIL " .. table.concat(ctx.fails, "; ")
	else
		verdict = ctx.checks and ("PASS " .. ctx.checks .. " checks") or "INFO data only"
	end
	P("RESULT", sc.name, verdict)
	H.si, H.pi, H.expectStart, H.press, H.flood, H.hold = H.si + 1, 1, nil, nil, nil, nil -- a timed-out press must not reach the next scenario
	H.ctx = { floors = {}, fails = {} }
end

local function tick()
	local H = HARNESS
	if not H.running or H.pending then return end
	local sc = SCENARIOS[H.si]
	if not sc then
		H.running, H.status = false, "DONE: exit to the menu, then tell Claude" -- exiting flushes log.txt (run 1)
		P("HARNESS DONE")
		return
	end
	local step = sc.steps[H.pi]
	if not step then return finish() end
	H.ctx.name = sc.name
	H.status = sc.name .. " step " .. H.pi .. "/" .. #sc.steps .. (H.ctx.label and (": " .. H.ctx.label) or "")
	local ok, res = pcall(step, H.ctx)
	if not ok then return finish("error in step " .. H.pi .. ": " .. tostring(res)) end
	if res ~= "again" then H.pi = H.pi + 1 end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
	local ok, err = pcall(tick)
	if not ok then
		P("HARNESS ERROR", err)
		if HARNESS.si <= #SCENARIOS then pcall(finish, "harness error: " .. tostring(err)) end
	end
end)

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
	local H = HARNESS
	if H.pending then
		local c = H.pending
		H.pending = nil
		P("CMD", c)
		Isaac.ExecuteCommand(c)
	end
	Isaac.RenderText("HARNESS: " .. H.status, 60, 30, 1, 1, 0, 1)
end)

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	local H = HARNESS
	H.gen, H.continued = H.gen + 1, isContinued
	P("GAME START", H.gen, "continued", isContinued)
	if not H.started then
		if isContinued then P("HARNESS idle: start a new run to test") return end
		H.started, H.running = true, true
		P("HARNESS START", #SCENARIOS, "scenarios")
		return
	end
	if H.running and not H.expectStart then finish("unexpected game start (hold-R, new run or continue)") end
	H.expectStart = nil
end)
