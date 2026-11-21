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
HARNESS = HARNESS or { started = false, running = false, gen = 0, si = 1, pi = 1, fired = 0, pressed = 0, ctx = { floors = {}, fails = {}, notes = {} }, status = "waiting for a run" }

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

-- Item wisps of `p`: counts by item id, and the first wisp entity of each. Owners match by GetPtrHash only: a wisp's Player may be a
-- removed entity, and methods on one crash natively (lua-api-notes.md).
local function wispsOf(p)
	local hash, n, first = GetPtrHash(p), {}, {}
	for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP)) do
		local f = e:ToFamiliar()
		if f and f.Player and GetPtrHash(f.Player) == hash then
			n[e.SubType], first[e.SubType] = (n[e.SubType] or 0) + 1, first[e.SubType] or e
		end
	end
	return n, first
end

-- shortcut: copy of ReHUD main.lua isCharacter; expose it on ReHUD.dbg if the copy drifts.
local function isCharacter(p) return p.Variant == 0 and not p.Parent and p:GetPlayerType() ~= PlayerType.PLAYER_THESOUL_B end

local function playable()
	local n = 0
	for i = 0, game:GetNumPlayers() - 1 do
		if isCharacter(Isaac.GetPlayer(i)) then n = n + 1 end
	end
	return n
end

local function probe(ctx, label)
	P("STEP", ctx.name, label, "floor", floorName(), "stage", game:GetLevel():GetStage())
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		P("PLAYER", i, "type", p:GetPlayerType(), "ctrl", p.ControllerIndex, "variant", p.Variant, "parent", p.Parent ~= nil,
			"ghost", p:IsCoopGhost(), "seed", seedOf(p), "count", p:GetCollectibleCount())
		local wispOf = wispsOf(p)
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

-- ReHUD entries of item `id` matching every given field (nil: any); `temporary` true is a copy with a clock.
local function countOf(id, floor, temporary, owner)
	local n = 0
	for _, e in ipairs(entries()) do
		if e.id == id and (floor == nil or e.floor == floor) and (temporary == nil or e.temporary == temporary) and (owner == nil or e.owner == owner) then n = n + 1 end
	end
	return n
end

local function expectCount(ctx, label, want, id, floor, temporary, owner)
	local kind = temporary == nil and "" or (temporary and " clocked" or " unclocked")
	expect(ctx, label .. ": c" .. id .. kind .. (floor and (" on " .. floor) or "") .. (owner and (" of " .. owner) or ""), countOf(id, floor, temporary, owner), want)
end

-- expectCount with player 0 as the owner.
local function own(ctx, label, want, id, floor, temporary) expectCount(ctx, label, want, id, floor, temporary, seedOf(Isaac.GetPlayer(0))) end

local function leftEntries()
	local n = 0
	for _, e in ipairs(entries()) do
		if e.left then n = n + 1 end
	end
	return n
end

-- A step is function(ctx) returning "again" to run itself next update, anything else to move on.

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
			ctx.t, ctx.held, ctx.before, ctx.label = nil, nil, nil, nil
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

-- One item wisp more or fewer on player 0 (`act` adds or kills one), seen in its wisp count and in GetCollectibleNum(id, false) both.
-- The DONE line's update count answers how soon a killed wisp leaves the engine count (Q4).
local function changeWisps(label, id, delta, act)
	local function counts()
		local p = Isaac.GetPlayer(0)
		return wispsOf(p)[id] or 0, p:GetCollectibleNum(id, false)
	end
	return action(label .. " c" .. id, function()
		local w, n = counts()
		act(Isaac.GetPlayer(0))
		return { w = w, n = n }
	end, function(_, b)
		local w, n = counts()
		return w == b.w + delta and n == b.n + delta, "wisps " .. b.w .. " -> " .. w .. ", GetCollectibleNum(false) " .. b.n .. " -> " .. n
	end)
end
local function wisp(id) return changeWisps("AddItemWisp", id, 1, function(p) p:AddItemWisp(id, p.Position) end) end
local function killWisp(id)
	return changeWisps("Kill wisp", id, -1, function(p)
		local e = select(2, wispsOf(p))[id]
		if not e then error("no c" .. id .. " wisp of player 0 to kill") end
		e:Kill()
	end)
end

-- An engine fact the next checks rest on: its FAIL names the engine, not ReHUD.
local function engineWisps(label, id, want)
	return function(ctx) expect(ctx, "engine, not ReHUD: c" .. id .. " wisps of player 0 " .. label, wispsOf(Isaac.GetPlayer(0))[id] or 0, want) end
end

-- Polls player 0's Zodiac item; a new id sets ctx.zodiac and the floor it appeared on, the last one stays as ctx.zodiacOld.
-- With `ceiling`, nothing by then is the answer, logged (Q1: does giveitem c392 grant on its own floor), not a fail.
-- shortcut: takes the first nonzero read after `stage`, so a re-roll landing later is read as "rolled the same item"; poll longer if Q1/Q2 answers look odd.
local function zodiacOn(label, ceiling)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local z = Isaac.GetPlayer(0):GetZodiacEffect()
		if z == 0 and ctx.t < (ceiling or TIMEOUT) then return "again" end
		P("INFO", ctx.name, "Zodiac item " .. label, z, "after", ctx.t, "updates")
		ctx.t = nil
		if z == 0 then
			if ceiling then return end
			error("Zodiac granted nothing " .. label .. " (engine, not ReHUD)")
		end
		ctx.zodiacOld = ctx.zodiac
		if z ~= ctx.zodiac then ctx.zodiac, ctx.zodiacFloor = z, floorName() end
	end
end

-- 3 Dollar Bill's grant on player 0: an id held but not owned, not a wisp and not the Zodiac item, other than the last grant
-- (kept as ctx.grantOld). Logs every such id, so one-at-a-time shows, and the DONE line the interval (Q6).
-- shortcut: an owned id cannot be told from the owned copy, so a grant of one is missed (part of Q6 unanswered); compare counts with a pre-grant snapshot if that matters.
local grant3DB = action("3 Dollar Bill grant", function(ctx) ctx.grantOld = ctx.grant end, function(ctx)
	local p = Isaac.GetPlayer(0)
	local w, z, found = wispsOf(p), p:GetZodiacEffect(), {}
	for id = 1, maxId do
		if itemConfig:GetCollectible(id) and id ~= z and id ~= ctx.grantOld and not w[id] and owned(p, id) == 0 and p:GetCollectibleNum(id, false) > 0 then found[#found + 1] = id end
	end
	if not found[1] then return false, "no new grant" end
	ctx.grant = found[1]
	P("INFO", ctx.name, "3 Dollar Bill grants c" .. table.concat(found, " c"))
	return true
end, 600)
-- ReHUD finds a 3 Dollar Bill grant only on its periodic scan (tracker.lua SCAN_INTERVAL 30).
local listed = action("3 Dollar Bill grant listed", function() end, function(ctx)
	local n = countOf(ctx.grant, nil, true)
	return n == 1, "c" .. ctx.grant .. " has " .. n .. " clocked entries, want 1"
end, 60)

local function snapshot()
	local p = Isaac.GetPlayer(0)
	return { count = game:GetNumPlayers(), who = p:GetPlayerType() .. "/" .. seedOf(p) }
end

-- A stored presser (Esau Jr., Flip without Birthright) has no vanilla accessor, but its charge + battery drop shows on its own seed
-- after its MC_USE_ITEM and before the engine stores it (runs 6-7), so HARNESS.watch (set by swap) keeps the first such reading as `seen`.
-- shortcut: rests on J510's order; if a swap FAILs "seen with no drop", log every channel around the press again to find where the drop moved.
local function watchSee(channel, e)
	local w = HARNESS.watch
	if not (w and w.used and not w.seen and e) then return end -- MC_INPUT_ACTION is polled ~1470/s: cheap exit first
	local p = e:ToPlayer()
	if not (p and seedOf(p) == w.seed and p:GetActiveItem(w.slot) == w.id) then return end
	local c = p:GetActiveCharge(w.slot) + p:GetBatteryCharge(w.slot)
	if c < w.total then w.seen = channel .. " charge+battery " .. w.total .. " -> " .. c end
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, item, _, p)
	local w = HARNESS.watch
	if w and item == w.id and p and seedOf(p) == w.seed then w.used = true end
end)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, p) watchSee("POST_PLAYER_UPDATE", p) end)

-- A real press, by player 0, of two kinds. HARNESS.press: true once, on the first triggered poll of that button (cards and ACTION_ITEM;
-- one-shot, so a card press cannot also use the next pocket item). HARNESS.full: true to every triggered and pressed poll of that button
-- from its first poll (HARNESS.fullPolled) to the next MC_POST_UPDATE after it. With Flip in the pocket an update polls PILLCARD
-- triggered, pressed, triggered, and Flip reads the second triggered (the user's console probe), which the one-shot never answers; with
-- only cards held it polls triggered twice and never pressed (runs 4-5).
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, e, hook, button)
	local H = HARNESS
	watchSee("INPUT_ACTION", e)
	if not (H.press or H.full) or hook == InputHook.GET_ACTION_VALUE or not e or GetPtrHash(e) ~= GetPtrHash(Isaac.GetPlayer(0)) then return end -- polled ~1470/s: cheap exit first
	if button == H.full then
		H.fullPolled = true
		if hook == InputHook.IS_ACTION_TRIGGERED then H.fired = H.fired + 1 else H.pressed = H.pressed + 1 end
		return true
	end
	if hook ~= InputHook.IS_ACTION_TRIGGERED or button ~= H.press then return end
	H.press, H.fired = nil, H.fired + 1
	return true
end)

-- Called from MC_POST_UPDATE: true once the full press is over. It ends at the first update after its first poll, so it spans one
-- update's input whether that poll came from a render frame or the update; a press never polled stays down, and shows as fired 0.
local function fullOver(H)
	if H.fullPolled then H.full, H.fullPolled = nil, nil end
	return not H.full
end

local function chargeOf(p, id, slot) return p and p:GetActiveItem(slot) == id and p:GetActiveCharge(slot) end

-- How the use spent `id`, or nil and what was read. `b` is the presser before the press: its seed and full charge or card count.
-- A stored presser passes only on the drop HARNESS.watch saw before the engine stored it.
local function spentHow(b, id, slot)
	local presser = playerBySeed(b.seed) -- a seed lookup, not a kept entity: the presser may be gone (AGENTS.md)
	if slot == "card" then
		local n = presser and cards(presser, id)
		if n == b.cards - 1 then return "spent card " .. b.cards .. "->" .. n end
		return nil, "card count " .. tostring(n) .. ", was " .. b.cards
	end
	local c1 = chargeOf(presser, id, slot)
	local read = "charge " .. b.charge .. " -> presser " .. tostring(c1) .. ", player 0 " .. tostring(chargeOf(Isaac.GetPlayer(0), id, slot))
	if presser then
		if c1 and c1 < b.charge then return "spent presser charge, " .. read end
		return nil, read
	end
	local w = HARNESS.watch
	if w and w.seen then return "spent stored presser charge, " .. w.seen end
	return nil, "stored presser seen with no drop after its use, " .. read
end

local function arm(H, b)
	if b.full then H.full = b.button else H.press = b.button end
	b.arms = b.arms + 1
end

-- Every character swap: player 0 presses `id` (active in `slot`, or a held card with slot "card"), and it is done only when a new
-- character appears (`count` players after, when given) and the use spent the charge or the card.
-- A pocket active takes the full press; cards and ACTION_ITEM the one-shot (one-shot: run 2; full press: runs 4-5).
local function swap(label, id, slot, count)
	local button = slot == ActiveSlot.SLOT_PRIMARY and ButtonAction.ACTION_ITEM or ButtonAction.ACTION_PILLCARD
	return action(label, function()
		local p, H = Isaac.GetPlayer(0), HARNESS
		local b = snapshot()
		-- shortcut: the full press answers both triggered polls of its update, safe only while the pocket holds no card (a card reads
		-- the first, Flip the second); Flip's charge of 4 is spent by one use, so it cannot flip twice. Revisit for a card beside Flip.
		b.seed, b.button, b.full = seedOf(p), button, slot == ActiveSlot.SLOT_POCKET
		local read = ""
		if slot == "card" then
			b.cards = cards(p, id)
			if b.cards == 0 then error(label .. ": card " .. id .. " not held") end
		else
			if p:GetActiveItem(slot) ~= id then error(label .. ": c" .. id .. " not in slot " .. slot) end
			-- Full, so a drop is visible. ItemConfig MaxCharges reads 6 for Flip, but REP+ Flip takes 4, and SetActiveCharge(6, 2) gave
			-- 4 + 2 battery (user, in game); FullCharge without force fills the first bar only (run 3: charge 4, battery 0).
			if slot == ActiveSlot.SLOT_POCKET then p:FullCharge(slot)
			else p:SetActiveCharge(itemConfig:GetCollectible(id).MaxCharges, slot) end
			b.charge = p:GetActiveCharge(slot)
			read = " charge " .. b.charge .. " battery " .. p:GetBatteryCharge(slot)
			-- Only active slots: watchSee reads GetActiveItem(slot), which a "card" slot would make throw in MC_INPUT_ACTION.
			H.watch = { seed = b.seed, id = id, slot = slot, total = b.charge + p:GetBatteryCharge(slot) }
		end
		b.arms, b.fired, b.pressed = 0, H.fired, H.pressed
		arm(H, b)
		P("PRESS", label, "button", button, (b.full and "full" or "one-shot") .. read)
		return b
	end, function(ctx, b)
		local H, a = HARNESS, snapshot()
		local polls = "arms " .. b.arms .. ", fired " .. (H.fired - b.fired) .. ", pressed " .. (H.pressed - b.pressed)
		if a.who == b.who and a.count == b.count then
			-- shortcut: re-arms until a new character shows (the one-shot each update, the full press one update after its release, so
			-- each is a fresh press), in case the first poll was not the use logic; a press shown late could fire twice, harmless while the
			-- presser holds no battery or second card; count uses per swap before a scenario gives either.
			if b.full then
				if b.released then arm(H, b); b.released = nil elseif fullOver(H) then b.released = true end
			elseif not H.press then arm(H, b) end
			return false, "no new character, " .. polls -- fired 0: the use logic never polled the press
		end
		H.press, H.full, H.fullPolled = nil, nil, nil
		if count and a.count ~= count then return false, a.count .. " players, want " .. count end
		local how, read = spentHow(b, id, slot)
		if not how then return false, "spent nothing: " .. read end
		H.watch, ctx.arms = nil, b.arms
		P("SWAP", label, b.who, "->", a.who, "players", b.count, "->", a.count, how, polls)
		return true
	end)
end

local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT = CollectibleType.COLLECTIBLE_FLIP, CollectibleType.COLLECTIBLE_ESAU_JR, CollectibleType.COLLECTIBLE_CLICKER, CollectibleType.COLLECTIBLE_BIRTHRIGHT
local T_LAZ, DEAD_LAZ, JE, ISAAC, CAIN = PlayerType.PLAYER_LAZARUS_B, PlayerType.PLAYER_LAZARUS2_B, PlayerType.PLAYER_JACOB, PlayerType.PLAYER_ISAAC, PlayerType.PLAYER_CAIN

local function flip(label) return swap(label, FLIP, ActiveSlot.SLOT_POCKET) end
local function esauJr(label) return swap(label, ESAU_JR, ActiveSlot.SLOT_PRIMARY) end
-- On Isaac, not beside Flip: a card beside a pocket active sits in slot 1 (run 5) and is untested with either press.
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

-- Stored forms still settling: the wait skips them, as ReHUD freezes their settle until they return (roster.lua), so this says whether
-- a step tested ReHUD's stored-mid-settle path or its settled one.
local function storedSettling()
	local r, seen, t = dbg().roster, {}, {}
	for _, e in ipairs(entries()) do
		if not seen[e.owner] and r.isSwapped(e.owner) and r.isSettling(e.owner) then seen[e.owner] = true; t[#t + 1] = e.owner end
	end
	return table.concat(t, ",")
end

-- One check per invariant: it fails naming every problem found.
local function holds(ctx, label, what, problems)
	ctx.checks = (ctx.checks or 0) + 1
	if problems[1] then fail(ctx, label .. ": invariant " .. what .. ": " .. table.concat(problems, "; ")) end
end

-- A stored form can come back only through the engine's two swap items (lua-api-notes.md): Flip, by a present Tainted Lazarus of its
-- group without Birthright (with it both forms play), or Esau Jr., held by a present member. Stricter than ReHUD's own rule (roster.lua
-- keeps a form swapped while any member of its group plays, merging it only into a former Tainted Lazarus form), so a form ReHUD forgot to
-- merge or drop shows here.
local function revivable(r, key, present)
	for k, p in pairs(present) do
		if p and r.group(k) == r.group(key) then
			local t = p:GetPlayerType()
			if (t == T_LAZ or t == DEAD_LAZ) and owned(p, BIRTHRIGHT) == 0 then return true end
			for slot = 0, 2 do -- primary, secondary, pocket
				if p:GetActiveItem(slot) == ESAU_JR then return true end
			end
		end
	end
end

-- Invariants every settled look checks, whatever the scenario: (1) for each present character and item, ReHUD's entries match the
-- engine's GetCollectibleNum(id, false) (ReHUD lists every copy: owned and innate without a clock, each wisp and the Zodiac copy with
-- one), at least the wisps and Zodiac copy clocked, and no entry of an owner gone without being stored or left; (2) no duplicates past
-- that count; (3) every stored form revivable; (4) no left entries unless the scenario sets `leftOk`; (5) no entry on a floor later
-- than the current one. A ghost's list is frozen, so ghosts are left out of (1) and (2).
-- shortcut: a 3 Dollar Bill grant shows only on ReHUD's 30-update scan, so a look within 30 updates of a re-grant would fail (1); every
-- look after a grant follows `listed`, far inside the ~170-update interval. Wait for that scan in look if a scenario looks later.
local function invariants(ctx, label)
	local r, present, have = dbg().roster, {}, {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if isCharacter(p) then present[seedOf(p)] = not p:IsCoopGhost() and p end
	end
	local rank, stageNow = {}, game:GetLevel():GetStage()
	for k = 1, stageNow do
		if ctx.floors[k] then rank[ctx.floors[k]] = k end
	end
	local counts, dups, phantoms, lefts, floors = {}, {}, {}, {}, {}
	for _, e in ipairs(entries()) do
		local tag = "c" .. e.id .. " of " .. tostring(e.owner)
		have[e.owner] = have[e.owner] or {}
		local h = have[e.owner][e.id] or { all = 0, clocked = 0 }
		have[e.owner][e.id] = h
		h.all, h.clocked = h.all + 1, h.clocked + (e.temporary and 1 or 0)
		if present[e.owner] == nil and not r.isSwapped(e.owner) and not e.left then counts[#counts + 1] = tag .. ": owner gone, neither stored nor left" end
		if e.left then lefts[#lefts + 1] = tag end
		if not rank[e.floor] then floors[#floors + 1] = tag .. " on '" .. tostring(e.floor) .. "', not a floor up to stage " .. stageNow end
	end
	for key, p in pairs(present) do
		if p then
			local w, z = wispsOf(p), p:GetZodiacEffect()
			for id = 1, maxId do
				if itemConfig:GetCollectible(id) then
					local engine = p:GetCollectibleNum(id, false)
					local h = (have[key] or {})[id] or { all = 0, clocked = 0 }
					local tag = "c" .. id .. " of " .. key .. ": " .. h.all .. " entries, engine " .. engine
					if h.all < engine then counts[#counts + 1] = tag .. ", missing"
					elseif h.all > engine and engine == 0 then counts[#counts + 1] = tag .. ", stale"
					elseif h.all > engine then dups[#dups + 1] = tag .. ", duplicate" end
					local clocks = (w[id] or 0) + (z == id and 1 or 0)
					if h.clocked < clocks then counts[#counts + 1] = tag .. ", " .. h.clocked .. " clocked for " .. clocks .. " wisp/Zodiac copies" end
				end
			end
		end
	end
	for _, row in ipairs(r.serialize()) do
		if row.swapped and not revivable(r, row.key, present) then phantoms[#phantoms + 1] = tostring(row.key) .. " stored, nobody can swap it back" end
	end
	holds(ctx, label, "engine counts", counts)
	holds(ctx, label, "duplicates", dups)
	holds(ctx, label, "phantom stored forms", phantoms)
	holds(ctx, label, "left entries", ctx.leftOk and {} or lefts)
	holds(ctx, label, "floors", floors)
end

-- Once ReHUD has settled: probe, run `check(ctx, label)` if given, then the invariants (not while ReHUD still settles at the ceiling).
local function look(label, check)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local busy = settling()
		if busy and ctx.t < TIMEOUT then return "again" end
		if busy then fail(ctx, label .. ": ReHUD still settling " .. busy .. " after " .. ctx.t .. " updates") end
		P("SETTLED", label, "after", ctx.t, "updates", "stored settling", storedSettling())
		ctx.t = nil
		probe(ctx, label)
		if check then check(ctx, label) end
		if not busy then invariants(ctx, label) end
	end
end

local function c4c5(ctx, label)
	expectOne(ctx, label, 4, ctx.floors[1])
	expectOne(ctx, label, 5, ctx.floors[2])
end
local function oneC4(ctx, label) expectOne(ctx, label, 4, ctx.floors[1]) end
local function twoC4(ctx, label) expectN(ctx, label, 4, 2, ctx.floors[1], seedOf(Isaac.GetPlayer(0))) end

local function birthrightOwners(ctx, label)
	c4c5(ctx, label)
	expectOne(ctx, label, 4, nil, seedOf(playerOfType(T_LAZ)))
	expectOne(ctx, label, 5, nil, seedOf(playerOfType(DEAD_LAZ)))
end

-- No list marked left, and ReHUD counts every playable player (no swapped-out form holds a list here).
local function noneLeft(ctx, label)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
	expect(ctx, label .. ": characterCount = playable players", dbg().tracker.characterCount, playable())
end

local clicker = swap("Clicker", CLICKER, ActiveSlot.SLOT_PRIMARY)
local clickerLook = look("after Clicker", function(ctx, label)
	label = label .. " " .. ctx.uses
	local n = 0
	for i = 0, game:GetNumPlayers() - 1 do n = n + owned(Isaac.GetPlayer(i), 4) end
	expectN(ctx, label, 4, n, ctx.floors[1])
	noneLeft(ctx, label)
	if ctx.esau and not playerBySeed(ctx.esau) then expect(ctx, label .. ": merged Esau's number", dbg().roster.number(ctx.esau), nil) end
end)

-- Clicker on Jacob until it is Jacob & Esau again, up to 20 uses (each refilled by the swap); each use is a checked swap followed by
-- a settled probe. A random character may never land on J&E, so a missed split is a note in the RESULT line, not a fail.
local function clickerLoop(ctx)
	if not ctx.phase then
		if ctx.back then return end
		if (ctx.uses or 0) >= 20 then table.insert(ctx.notes, "split (20 Clicker uses)") return end
		ctx.uses, ctx.phase = (ctx.uses or 0) + 1, "press"
		if Isaac.GetPlayer(0):GetActiveItem() ~= CLICKER then error("Clicker left the active slot") end
		local esau = playerOfType(PlayerType.PLAYER_ESAU)
		ctx.esau = esau and seedOf(esau)
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

-- probes: engine facts the swaps rely on, as checks, so a game patch that changes one fails here first.

local function maxCharges(ctx)
	for _, c in ipairs({ { CLICKER, 6 }, { ESAU_JR, 1 }, { FLIP, 6 } }) do -- want: pre-REP+ items.xml
		expect(ctx, "MaxCharges c" .. c[1], itemConfig:GetCollectible(c[1]).MaxCharges, c[2])
	end
end

-- REP+ Flip takes 4 though MaxCharges reads 6 (user, in game; run 3).
local function pocketCharge(ctx)
	local p, s = Isaac.GetPlayer(0), ActiveSlot.SLOT_POCKET
	local function read() return p:GetActiveCharge(s) .. " + " .. p:GetBatteryCharge(s) end
	expect(ctx, "pocket item", p:GetActiveItem(s), FLIP)
	p:SetActiveCharge(6, s)
	expect(ctx, "SetActiveCharge(6, 2): charge + battery", read(), "4 + 2")
	p:SetActiveCharge(0, s)
	p:FullCharge(s)
	expect(ctx, "FullCharge(2) from 0: charge + battery", read(), "4 + 0")
end

local function onePress(label) return function(ctx) expect(ctx, label .. ": arms needed", ctx.arms, 1) end end

local function clickerHeld(ctx)
	local p = Isaac.GetPlayer(0)
	expect(ctx, "Clicker after a real press: active, charge", p:GetActiveItem() .. ", " .. p:GetActiveCharge(), CLICKER .. ", 0")
end

local function cardBesideFlip(ctx)
	local p, slot = Isaac.GetPlayer(0), nil
	for i = 0, 3 do
		if p:GetCard(i) == Card.CARD_SOUL_JACOB then slot = slot or i end
	end
	expect(ctx, "Soul of J&E beside Flip: card slot", slot, 1)
end

-- Tainted Lazarus flips with c4, the user exits and continues, and ChangePlayerType merges the stored form: one c4, no c711.
local function continueSteps(beforeFlip)
	local steps = { restart(T_LAZ), give(4), stage(2), beforeFlip }
	-- Pacing alone decides whether the Flip stores the 29 form mid-settle, so the path each variant tests is checked.
	local function beforeExit(ctx, label)
		oneC4(ctx, label)
		expect(ctx, label .. ": stored form mid-settle", storedSettling() ~= "", beforeFlip == nil)
	end
	for _, s in ipairs({ flip("Flip"), look("before exit", beforeExit), exitAndContinue(), changeType(ISAAC),
		look("after continue and ChangePlayerType", function(ctx, label)
			expectOne(ctx, label, 4, ctx.floors[1], seedOf(Isaac.GetPlayer(0)))
			expectN(ctx, label, FLIP, 0)
		end) }) do
		steps[#steps + 1] = s
	end
	return steps
end

local function jeCopies(ctx, label)
	expectCount(ctx, label, 1, 4, ctx.floors[1], false, ctx.jacob)
	expectCount(ctx, label, 1, 5, ctx.floors[1], false, ctx.esau)
end

-- L1's copies: Cain's owned and innate c46 on floor 1, a c46 wisp from floor 2, an owned c4 and a c4 wisp from floor 1. The totals
-- catch a continue re-listing copies under the current floor.
local function copyKinds(ctx, label)
	own(ctx, label, 2, 46, ctx.floors[1], false)
	own(ctx, label, 1, 46, ctx.floors[2], true)
	own(ctx, label, 1, 4, ctx.floors[1], false)
	own(ctx, label, 1, 4, ctx.floors[1], true)
	expectCount(ctx, label, 3, 46)
	expectCount(ctx, label, 2, 4)
end

-- After Clicker out of Tainted Lazarus (S3): every c4 (floor 1, the stored form's) and c5 (floor 2, the Dead form's) the engine counts,
-- wisps aside, is listed once, floor kept, under the player holding it; the stored form is forgotten. A roll into the other form's type
-- keeps Flip and starts a fresh, unseen form (run 8), so ReHUD's count of characters is not checked then.
local function afterTLazClicker(ctx, label)
	local t = Isaac.GetPlayer(0):GetPlayerType()
	P("INFO", ctx.name, "Clicker rolled type", t) -- Q7
	local lazarus = t == T_LAZ or t == DEAD_LAZ
	for id, floor in pairs({ [4] = ctx.floors[1], [5] = ctx.floors[2] }) do
		local sum = 0
		for i = 0, game:GetNumPlayers() - 1 do
			local q = Isaac.GetPlayer(i)
			local n = q:GetCollectibleNum(id, false) - (wispsOf(q)[id] or 0)
			sum = sum + n
			expectCount(ctx, label .. " (player " .. i .. ")", n, id, nil, nil, seedOf(q))
		end
		expectCount(ctx, label .. " (all)", sum, id)
		expectCount(ctx, label .. " (all)", sum, id, floor)
	end
	expectN(ctx, label, FLIP, lazarus and 1 or 0)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
	if lazarus then return expect(ctx, label .. ": left entries", leftEntries(), 0) end
	noneLeft(ctx, label)
end

-- r1, after ChangePlayerType(29) on the Dead form with the 29 form stored: the stored form's c4 (floor 1) and the Dead form's c5 (floor 2)
-- both on player 0, floors kept, and the stored form forgotten.
local function r1Merged(ctx, label)
	local key = seedOf(Isaac.GetPlayer(0))
	ctx.merged = key
	expectOne(ctx, label, 4, ctx.floors[1], key)
	expectOne(ctx, label, 5, ctx.floors[2], key)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
end

-- r1, after the next Flip: a fresh Dead form whose only entry is its Flip; the stored survivor keeps c4 (floor 1), c5 (floor 2) and one
-- Flip (which floor's Flip survives is not checked: the oldest goes once the survivor settles).
local function r1Fresh(ctx, label)
	local key = seedOf(Isaac.GetPlayer(0))
	expect(ctx, label .. ": a new form", key ~= ctx.merged and key ~= ctx.stored, true)
	expectCount(ctx, label, 1, FLIP, nil, nil, key)
	local n = 0
	for _, e in ipairs(entries()) do
		if e.owner == key then n = n + 1 end
	end
	expect(ctx, label .. ": entries of the new form", n, 1)
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.merged)
	expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.merged)
	expectCount(ctx, label, 1, FLIP, nil, nil, ctx.merged)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
end

-- r1 mirror, after ChangePlayerType(38) on the 29 form with the Dead form stored: unobserved in game, so the merge run 8 showed for r1 is
-- expected, and the engine state is logged; a resumed stored form (its seed back at player 0) fails here.
local function mirrorMerged(ctx, label)
	local p = Isaac.GetPlayer(0)
	local key = seedOf(p)
	P("INFO", ctx.name, "engine after ChangePlayerType(38): type", p:GetPlayerType(), "seed", key, "was", ctx.active, "stored", ctx.stored,
		"pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET), "players", game:GetNumPlayers())
	expect(ctx, label .. ": player 0 keeps its seed", key, ctx.active)
	expectOne(ctx, label, 4, ctx.floors[1], key)
	expectOne(ctx, label, 5, ctx.floors[2], key)
	expectN(ctx, label, FLIP, 1)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
end

-- kind "large": needs the user to exit and Continue; runs last. new = true until it has passed in game (then clear it by hand); set it
-- again whenever its steps or checks change. leftOk = true lets left entries pass the invariant (for a scenario where a player leaves).
local SCENARIOS = {
	{ name = "probes", kind = "small", steps = {
		restart(ISAAC), maxCharges, give(ESAU_JR), esauJr("Esau Jr."), onePress("Esau Jr."),
		give(CLICKER), give(1), clicker, clickerHeld, -- c1 after Clicker, so Clicker's 50% item removal takes c1, not Clicker
		restart(T_LAZ), addCard(Card.CARD_SOUL_JACOB), cardBesideFlip,
		restart(T_LAZ), pocketCharge, flip("Flip"), onePress("Flip"),
	} },
	{ name = "test3", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), look("before ChangePlayerType"), changeType(ISAAC),
		look("after ChangePlayerType", function(ctx, label)
			c4c5(ctx, label)
			local key = seedOf(Isaac.GetPlayer(0))
			expectOne(ctx, label .. " (Isaac owns)", 4, nil, key)
			expectOne(ctx, label .. " (Isaac owns)", 5, nil, key)
			expectN(ctx, label, FLIP, 0)
		end),
	} },
	{ name = "birthright", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), give(BIRTHRIGHT, 2), look("after Birthright", birthrightOwners),
		flip("Flip 1 of 2"), look("after Flip 1", birthrightOwners), flip("Flip 2 of 2"), look("after two Flips", birthrightOwners),
		stage(3), look("on stage 3", birthrightOwners),
	} },
	-- Run 7: the Dead form, number 1, holds c711 from Basement II.
	{ name = "P3", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), look("after c4", oneC4),
		give(BIRTHRIGHT, 2), look("after Birthright", function(ctx, label)
			oneC4(ctx, label)
			ctx.dead = seedOf(playerOfType(DEAD_LAZ))
		end),
		remove(BIRTHRIGHT, 1), look("after remove Birthright", function(ctx, label)
			oneC4(ctx, label)
			expect(ctx, label .. ": Dead form swapped", dbg().roster.isSwapped(ctx.dead), true)
			expect(ctx, label .. ": Dead form number", dbg().roster.number(ctx.dead), 1)
			expectCount(ctx, label, 1, FLIP, ctx.floors[2], nil, ctx.dead)
		end),
		stage(3), flip("Flip"), look("after Flip", function(ctx, label)
			oneC4(ctx, label)
			expect(ctx, label .. ": player 0 is the Dead form", seedOf(Isaac.GetPlayer(0)), ctx.dead)
			expectCount(ctx, label, 1, FLIP, ctx.floors[2], nil, ctx.dead)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
	} },
	{ name = "P4a", kind = "small", steps = {
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("after c4", oneC4),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", oneC4), esauJr("Esau Jr. 2"), look("after Esau Jr. 2", oneC4),
	} },
	-- Numbers are first seen (roster.lua observe), so Jacob 0, Esau 1 and Jacob's Esau Jr. form 2 (run 7's P4b).
	{ name = "S4", kind = "small", steps = {
		restart(JE), give(4), giveEsau(5), give(ESAU_JR), stage(2),
		look("start", function(ctx, label)
			ctx.jacob, ctx.esau = seedOf(Isaac.GetPlayer(0)), seedOf(playerOfType(PlayerType.PLAYER_ESAU))
			jeCopies(ctx, label)
		end),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", function(ctx, label)
			local r, esau = dbg().roster, playerOfType(PlayerType.PLAYER_ESAU)
			ctx.form = seedOf(Isaac.GetPlayer(0))
			expect(ctx, "engine, not ReHUD: Esau's owned c5 after Jacob's Esau Jr. (Q9)", esau and owned(esau, 5), 1)
			jeCopies(ctx, label)
			expect(ctx, label .. ": Jacob swapped", r.isSwapped(ctx.jacob), true)
			expect(ctx, label .. ": numbers Jacob, Esau, form", tostring(r.number(ctx.jacob)) .. "," .. tostring(r.number(ctx.esau)) .. "," .. tostring(r.number(ctx.form)), "0,1,2")
			expect(ctx, label .. ": left entries", leftEntries(), 0)
			expect(ctx, label .. ": characterCount", dbg().tracker.characterCount, 3)
		end),
		esauJr("Esau Jr. 2"), look("after Esau Jr. 2", function(ctx, label)
			jeCopies(ctx, label)
			expect(ctx, label .. ": player 0 is Jacob", seedOf(Isaac.GetPlayer(0)), ctx.jacob)
			expect(ctx, label .. ": form swapped", dbg().roster.isSwapped(ctx.form), true)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
	} },
	{ name = "P1", kind = "small", steps = {
		restart(ISAAC), give(4), give(4), stage(2), look("before Soul of Jacob and Esau", twoC4),
		addCard(Card.CARD_SOUL_JACOB), soulJE, look("after Soul of Jacob and Esau", twoC4),
		giveEsau(1), look("after Esau c1", function(ctx, label) twoC4(ctx, label) expectN(ctx, label, 1, 0) end),
		stage(3), look("on stage 3", twoC4),
	} },
	{ name = "P2", kind = "small", steps = {
		restart(JE), give(4), give(4), give(4), give(4), giveEsau(4), give(CLICKER), stage(2), look("start"), clickerLoop,
	} },
	-- One entry per copy, by kind (clocked: wisps), floors kept; a lost copy takes the oldest entry of its kind.
	{ name = "S1", kind = "small", steps = {
		restart(CAIN), look("start", function(ctx, label)
			own(ctx, label, 2, 46, ctx.floors[1], false) -- owned + innate
			expectCount(ctx, label, 0, 46, nil, true)
		end),
		give(4), stage(2), give(4), look("two c4", function(ctx, label)
			own(ctx, label, 1, 4, ctx.floors[1], false)
			own(ctx, label, 1, 4, ctx.floors[2], false)
		end),
		wisp(4), look("c4 wisp", function(ctx, label)
			own(ctx, label, 2, 4, nil, false)
			own(ctx, label, 1, 4, ctx.floors[2], true)
		end),
		stage(3), engineWisps("after stage (Q3)", 4, 1), wisp(4), look("second c4 wisp", function(ctx, label)
			own(ctx, label, 1, 4, ctx.floors[2], true)
			own(ctx, label, 1, 4, ctx.floors[3], true)
		end),
		killWisp(4), look("one c4 wisp killed", function(ctx, label)
			own(ctx, label, 1, 4, nil, true)
			own(ctx, label, 1, 4, ctx.floors[3], true)
			own(ctx, label, 2, 4, nil, false)
		end),
		remove(4), look("c4 removed", function(ctx, label)
			own(ctx, label, 1, 4, nil, false)
			own(ctx, label, 1, 4, ctx.floors[2], false)
			own(ctx, label, 1, 4, ctx.floors[3], true)
		end),
		killWisp(4), look("last c4 wisp killed", function(ctx, label)
			own(ctx, label, 0, 4, nil, true)
			own(ctx, label, 1, 4, ctx.floors[2], false)
			own(ctx, label, 2, 46, ctx.floors[1], false)
		end),
	} },
	-- Zodiac and 3 Dollar Bill copies are clocked. Settled before each grant, so neither is learned as innate.
	{ name = "S1b", kind = "small", steps = {
		restart(ISAAC), look("start"), give(392), zodiacOn("on the floor given", 30), stage(2), zodiacOn("on stage 2"),
		look("Zodiac", function(ctx, label)
			expectCount(ctx, label, 1, ctx.zodiac, ctx.zodiacFloor, true)
			expectCount(ctx, label, 0, ctx.zodiac, nil, false)
			expectCount(ctx, label, 1, 392, ctx.floors[1], false)
		end),
		stage(3), zodiacOn("on stage 3"), look("Zodiac on stage 3", function(ctx, label) -- Q2
			if ctx.zodiac == ctx.zodiacOld then
				table.insert(ctx.notes, "Zodiac rolled the same item")
				return expectCount(ctx, label, 1, ctx.zodiac, nil, true)
			end
			expectCount(ctx, label, 0, ctx.zodiacOld)
			expectCount(ctx, label, 1, ctx.zodiac, ctx.floors[3], true)
		end),
		restart(ISAAC), look("before 3 Dollar Bill"), give(191), grant3DB, listed,
		look("3 Dollar Bill", function(ctx, label) expectCount(ctx, label, 0, ctx.grant, nil, false) end),
		grant3DB, listed, look("next 3 Dollar Bill grant", function(ctx, label)
			if Isaac.GetPlayer(0):GetCollectibleNum(ctx.grantOld, false) > 0 then return table.insert(ctx.notes, "3 Dollar Bill still grants c" .. ctx.grantOld) end
			expectCount(ctx, label, 0, ctx.grantOld, nil, true)
		end),
	} },
	-- ChangePlayerType re-settles: the new type's innate c46 is learned, the wisp and the Zodiac copy stay clocked.
	{ name = "S2", kind = "small", steps = {
		restart(ISAAC), look("start"), give(392), stage(2), zodiacOn("on stage 2"), wisp(46),
		look("Zodiac and a c46 wisp", function(ctx, label)
			own(ctx, label, 1, 46, nil, true)
			own(ctx, label, 0, 46, nil, false)
			own(ctx, label, 1, ctx.zodiac, nil, true)
		end),
		changeType(CAIN), look("as Cain", function(ctx, label)
			own(ctx, label, 1, 46, nil, false) -- innate
			own(ctx, label, 1, 46, nil, true) -- wisp
			local z = Isaac.GetPlayer(0):GetZodiacEffect()
			P("INFO", ctx.name, "Zodiac item after ChangePlayerType", z, "was", ctx.zodiac) -- Q5
			if z == 0 then return table.insert(ctx.notes, "ChangePlayerType dropped the Zodiac item") end
			own(ctx, label, 1, z, nil, true)
			own(ctx, label, 0, z, nil, false)
		end),
		killWisp(46), look("c46 wisp killed", function(ctx, label)
			own(ctx, label, 1, 46, nil, false)
			own(ctx, label, 0, 46, nil, true)
		end),
	} },
	{ name = "S3", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), give(CLICKER), stage(3),
		look("before Clicker", function(ctx, label)
			for _, e in ipairs(entries()) do
				if e.id == 4 then ctx.stored = e.owner end
			end
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.stored)
			own(ctx, label, 1, 5, ctx.floors[2])
		end),
		clicker, look("after Clicker", afterTLazClicker),
	} },
	-- R1: ChangePlayerType(29) on the Dead form, with the 29 form stored, merges the two and keeps Flip; the next Flip brings a fresh Dead form (run 8).
	{ name = "r1", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5),
		look("before", function(ctx, label)
			for _, e in ipairs(entries()) do
				if e.id == 4 then ctx.stored = e.owner end
			end
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.stored)
		end),
		changeType(T_LAZ), look("after ChangePlayerType", r1Merged), flip("Flip after"), look("after Flip", r1Fresh),
	} },
	-- r1 the other way: the 29 form turned 38 with the Dead form stored (unobserved; expects r1's merge).
	{ name = "r1 mirror", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), flip("Flip back"),
		look("before", function(ctx, label)
			ctx.active = seedOf(Isaac.GetPlayer(0))
			for _, e in ipairs(entries()) do
				if e.id == 5 then ctx.stored = e.owner end
			end
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.active)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.stored)
		end),
		changeType(DEAD_LAZ), look("after ChangePlayerType", mirrorMerged),
	} },
	-- The Flip comes about 5 updates after restart, so the 29 form is stored mid-settle (the 20ca1f1 path).
	{ name = "continue", kind = "large", new = true, steps = continueSteps() },
	-- The settle wait first, so the 29 form is stored settled, as in real play.
	{ name = "continue settled", kind = "large", new = true, steps =continueSteps(look("before Flip", oneC4)) },
	-- Copy kinds survive a continue, and Cain's saved innate row means no second settle.
	{ name = "L1", kind = "large", new = true, steps = {
		restart(CAIN), look("start"), give(4), wisp(4), stage(2), wisp(46), look("before exit", copyKinds), exitAndContinue(),
		function(ctx) expect(ctx, "no re-settle after continue", dbg().roster.isSettling(seedOf(Isaac.GetPlayer(0))), false) end,
		engineWisps("after continue", 4, 1), engineWisps("after continue", 46, 1), look("after continue", copyKinds),
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
		verdict = (ctx.checks and ("PASS " .. ctx.checks .. " checks") or "INFO data only")
			.. (#ctx.notes > 0 and ("; unobserved: " .. table.concat(ctx.notes, ", ")) or "")
	end
	P("RESULT", sc.name, verdict)
	H.si, H.pi, H.expectStart, H.press, H.full, H.fullPolled, H.watch = H.si + 1, 1, nil, nil, nil, nil, nil -- a timed-out press must not reach the next scenario
	H.ctx = { floors = {}, fails = {}, notes = {} }
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
	if H.pi == 1 and sc.kind == "large" and not sc.new and H.mode ~= "regression" then
		P("RESULT", sc.name, "SKIP large and not new (" .. H.mode .. " mode)")
		H.si = H.si + 1
		return
	end
	local step = sc.steps[H.pi]
	if not step then return finish() end
	if not H.ctx.name then P("SCENARIO START", sc.name) end -- tools/run_report.py pairs it with a RESULT
	H.ctx.name, H.ctx.leftOk = sc.name, sc.leftOk
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

-- Console commands are queued for MC_POST_RENDER, not run in the middle of other mods' MC_POST_UPDATE.
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
		-- The mode file is data\rehud_test_harness\save<slot>.dat in the game folder (metadata.xml <directory>), written before launch:
		-- "regression" runs every scenario; anything else, or none, runs the small ones and the new large ones.
		local raw = mod:LoadData()
		H.started, H.running, H.mode = true, true, raw:match("^%s*(.-)%s*$") == "regression" and "regression" or "default"
		P("HARNESS START", #SCENARIOS, "scenarios,", H.mode, "mode, mod data of '" .. mod.Name .. "' read", string.format("%q", raw))
		return
	end
	if H.running and not H.expectStart then finish("unexpected game start (hold-R, new run or continue)") end
	H.expectStart = nil
end)
