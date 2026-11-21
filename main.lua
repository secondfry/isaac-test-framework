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
-- At 60 updates a wait is stuck: log it once and append a STUCK line under the mode line for tools\stuck-shots.ps1 to screenshot.
local function stuckAt(ctx, t, label)
	if t ~= 60 then return end
	local H = HARNESS
	H.stuck = (H.stuck or 0) + 1
	P("STUCK", ctx.name, label, t)
	Isaac.SaveModData(mod, (H.modLine or "") .. "\nSTUCK " .. H.stuck .. " " .. tostring(ctx.name) .. " | " .. tostring(label))
end

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
			ctx.t, ctx.held, ctx.before, ctx.label, ctx.why = nil, nil, nil, nil, nil
			return
		end
		local ok, why = done(ctx, ctx.before)
		if ok then ctx.held = true return "again" end
		ctx.why = why -- an obs step ceiling names it
		if (ceiling or TIMEOUT) <= TIMEOUT then stuckAt(ctx, ctx.t, label) end -- a longer ceiling waits for the user's Continue
		if ctx.t >=(ceiling or TIMEOUT) then error(label .. ": " .. (why or "no effect") .. " after " .. ctx.t .. " updates") end
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

-- AddCollectible on Esau, or on GetPlayer(`index`) when given (a pressed index may hold an Esau Jr. form, not Esau).
local function giveEsau(id, index)
	local function esauNow() return index and Isaac.GetPlayer(index) or playerOfType(PlayerType.PLAYER_ESAU) end
	return action("Esau AddCollectible c" .. id, function()
		local esau = esauNow()
		if not esau then error("no " .. (index and ("player at index " .. index) or "Esau (type 20)") .. " to give c" .. id) end
		local n = owned(esau, id)
		esau:AddCollectible(id)
		return n
	end, function(_, n)
		local esau = esauNow()
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

-- The user exits to the menu and continues: a continued game with the same players (seeds) as before the exit; `soft` takes any
-- players and logs them (obsy: what a continue does to a stored form is the question).
local function exitAndContinue(soft)
	return action("exit to the menu and Continue now", function()
		HARNESS.expectStart = "continue"
		return { gen = HARNESS.gen, seeds = seeds() }
	end, function(ctx, b)
		local H = HARNESS
		if H.gen == b.gen then
			if ctx.t % 300 == 0 then P("ACTION exit to the menu and Continue now") end
			return false, "no Continue"
		end
		if not H.continued then error("a new run started, not a Continue") end
		if soft then P("INFO", ctx.name, "after Continue: player seeds", seeds(), "before the exit", b.seeds) return true end
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

local function snapshot(index)
	local p = Isaac.GetPlayer(index or 0)
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
	if not (H.press or H.full) or hook == InputHook.GET_ACTION_VALUE or not e then return end -- polled ~1470/s: cheap exit first
	-- H.pressHash: the pressing entity's hash (swap's `who`), false for any entity, nil for player 0.
	if H.pressHash ~= false and GetPtrHash(e) ~= (H.pressHash or GetPtrHash(Isaac.GetPlayer(0))) then return end
	if button == H.full or (type(H.full) == "table" and H.full[button]) then
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

-- id:owned/total for every item p holds; total is GetCollectibleNum(id, false), so wisps and the Zodiac copy count too.
local function heldItems(p)
	local t = {}
	for id = 1, maxId do
		local total = itemConfig:GetCollectible(id) and p:GetCollectibleNum(id, false) or 0
		if total > 0 then t[#t + 1] = id .. ":" .. owned(p, id) .. "/" .. total end
	end
	return table.concat(t, " ")
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
	local c1, moved = chargeOf(presser, id, slot), ""
	-- A Birthright swap can move the presser's seed to a twin without the item (obsy b identity press #2): read the pressed index.
	if presser and not c1 then c1, moved = chargeOf(Isaac.GetPlayer(b.index), id, slot), " (seed holds no c" .. id .. ", read index " .. b.index .. ")" end
	local read = "charge " .. b.charge .. " -> presser " .. tostring(c1) .. moved .. ", player 0 " .. tostring(chargeOf(Isaac.GetPlayer(0), id, slot))
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
-- `who` (obsy): { index = GetPlayer index of the presser, any = answer every entity's polls }; its press is a full one of ACTION_ITEM
-- and ACTION_PILLCARD both, as which button and entity use a second player's or Tainted Forgotten's active is unknown.
local function swap(label, id, slot, count, ceiling, who)
	local index = who and who.index or 0
	local button = slot == ActiveSlot.SLOT_PRIMARY and ButtonAction.ACTION_ITEM or ButtonAction.ACTION_PILLCARD
	if who then button = { [ButtonAction.ACTION_ITEM] = true, [ButtonAction.ACTION_PILLCARD] = true } end
	return action(label, function()
		local p, H = Isaac.GetPlayer(index), HARNESS
		local b = snapshot(index)
		H.pressHash = nil
		if who and who.any then H.pressHash = false elseif who then H.pressHash = GetPtrHash(p) end
		-- shortcut: the full press answers both triggered polls of its update, safe only while the pocket holds no card (a card reads
		-- the first, Flip the second); Flip's charge of 4 is spent by one use, so it cannot flip twice. Revisit for a card beside Flip.
		b.seed, b.button, b.full, b.index, b.hash = seedOf(p), button, slot == ActiveSlot.SLOT_POCKET or who ~= nil, index, GetPtrHash(p)
		if H.obs then b.items = heldItems(p) end
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
		P("PRESS", label, "button", who and "ITEM+PILLCARD" or button, (b.full and "full" or "one-shot") .. read, who and ("player " .. index .. (who.any and ", any entity" or "")) or "")
		return b
	end, function(ctx, b)
		local H, a = HARNESS, snapshot(index)
		local polls = "arms " .. b.arms .. ", fired " .. (H.fired - b.fired) .. ", pressed " .. (H.pressed - b.pressed)
		if a.who == b.who and a.count == b.count then
			-- A use that spends the charge and swaps nothing (obs2: Flip on a 38 whose other form is gone) never swaps later: stop early.
			local c = slot ~= "card" and chargeOf(playerBySeed(b.seed), id, slot)
			-- obs data: after a Continue a press made a new entity with the old seed and type, its items re-rolled (obsy b run 1).
			local p = Isaac.GetPlayer(index)
			if c and c < b.charge and b.items and (GetPtrHash(p) ~= b.hash or heldItems(p) ~= b.items) then
				local how = GetPtrHash(p) ~= b.hash and ("new form, same seed " .. b.seed .. ", hash " .. b.hash .. " -> " .. GetPtrHash(p)) or ("acted in place: same seed " .. b.seed)
				P("INFO", ctx.name, label, how .. ", items " .. b.items .. " -> " .. heldItems(p) .. ", charge " .. b.charge .. " -> " .. c)
				H.press, H.full, H.fullPolled, H.pressHash, H.watch, ctx.arms = nil, nil, nil, nil, nil, b.arms
				return true
			end
			if c and c < b.charge and ctx.t >= 30 then error(label .. ": charge spent " .. b.charge .. " -> " .. c .. ", no new character after " .. ctx.t .. " updates") end
			-- shortcut: re-arms until a new character shows (the one-shot each update, the full press one update after its release, so
			-- each is a fresh press), in case the first poll was not the use logic; a press shown late could fire twice, harmless while the
			-- presser holds no battery or second card; count uses per swap before a scenario gives either.
			if b.full then
				if b.released then arm(H, b); b.released = nil elseif fullOver(H) then b.released = true end
			elseif not H.press then arm(H, b) end
			return false, "no new character, " .. polls -- fired 0: the use logic never polled the press
		end
		H.press, H.full, H.fullPolled, H.pressHash = nil, nil, nil, nil
		if count and a.count ~= count then return false, a.count .. " players, want " .. count end
		local how, read = spentHow(b, id, slot)
		if not how then
			-- A spend not found 30 updates after the new character never shows (obs3 birthright "Esau Jr. again"): stop early.
			b.newAt = b.newAt or ctx.t
			if ctx.t - b.newAt >= 30 then error(label .. ": new character but spent nothing: " .. read .. " after " .. ctx.t .. " updates") end
			return false, "spent nothing: " .. read
		end
		H.watch, ctx.arms = nil, b.arms
		P("SWAP", label, b.who, "->", a.who, "players", b.count, "->", a.count, how, polls)
		return true
	end, ceiling)
end

local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT = CollectibleType.COLLECTIBLE_FLIP, CollectibleType.COLLECTIBLE_ESAU_JR, CollectibleType.COLLECTIBLE_CLICKER, CollectibleType.COLLECTIBLE_BIRTHRIGHT
local T_LAZ, DEAD_LAZ, JE, ISAAC, CAIN = PlayerType.PLAYER_LAZARUS_B, PlayerType.PLAYER_LAZARUS2_B, PlayerType.PLAYER_JACOB, PlayerType.PLAYER_ISAAC, PlayerType.PLAYER_CAIN
local T_FORGOTTEN = PlayerType.PLAYER_THEFORGOTTEN_B

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
-- keeps a form swapped while any member of its group plays, merging it only into its Flip partner turned another type), so a form ReHUD forgot to
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
		if busy and ctx.t < TIMEOUT then stuckAt(ctx, ctx.t, label) return "again" end
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

-- P4c: an Esau Jr. form of Tainted Lazarus taken out of Tainted Lazarus. ReHUD merges a stored form only into its recorded Flip partner,
-- so it assumes the engine leaves the Esau Jr. original stored (lupa X2, X3, Y1); unobserved, so each engine state is logged as INFO
-- and a different outcome fails the checks. ctx.orig: the Esau Jr. presser; ctx.form: the Esau Jr. form; ctx.dead: a Flip partner.
local function engineInfo(ctx, what)
	local p = Isaac.GetPlayer(0)
	P("INFO", ctx.name, "engine " .. what .. ": type", p:GetPlayerType(), "seed", seedOf(p), "original", ctx.orig, "form", ctx.form, "dead", ctx.dead,
		"primary", p:GetActiveItem(ActiveSlot.SLOT_PRIMARY), "pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET), "players", game:GetNumPlayers())
end
local function origStored(ctx, label)
	expect(ctx, label .. ": Esau Jr. original stored", dbg().roster.isSwapped(ctx.orig), true)
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.orig)
end
local function esauJrForm(ctx, label)
	ctx.form = seedOf(Isaac.GetPlayer(0))
	expect(ctx, label .. ": a new form", ctx.form ~= ctx.orig and ctx.form ~= ctx.dead, true)
	origStored(ctx, label)
end
local function origBeforeEsauJr(ctx, label)
	ctx.orig, ctx.form, ctx.dead = seedOf(Isaac.GetPlayer(0)), nil, nil
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.orig)
end

-- obs esaujr: no checks, only what the engine and ReHUD do and in what order. While HARNESS.obs is set, tick logs the whole state on
-- every update where it changed: one OBS line per player, roster row and tracker entry.
local OBS_IDS = { 4, 5, ESAU_JR, FLIP, CLICKER, BIRTHRIGHT }
local function pedestals(id) return #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id) end
local function obsLines()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p, n = Isaac.GetPlayer(i), {}
		for _, id in ipairs(OBS_IDS) do n[#n + 1] = "c" .. id .. " " .. p:GetCollectibleNum(id, false) end
		t[#t + 1] = "PLAYER " .. i .. " type " .. p:GetPlayerType() .. " seed " .. seedOf(p) .. " hash " .. GetPtrHash(p) .. " ctrl " .. p.ControllerIndex
			.. " parent " .. tostring(p.Parent ~= nil) .. " " .. table.concat(n, " ") .. " primary " .. p:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
			.. " secondary " .. p:GetActiveItem(ActiveSlot.SLOT_SECONDARY) .. " pocket " .. p:GetActiveItem(ActiveSlot.SLOT_POCKET)
		t[#t + 1] = "PLAYERX " .. i .. " variant " .. p.Variant .. " ghost " .. tostring(p:IsCoopGhost())
			.. " charge primary " .. p:GetActiveCharge(ActiveSlot.SLOT_PRIMARY) .. "+" .. p:GetBatteryCharge(ActiveSlot.SLOT_PRIMARY)
			.. " pocket " .. p:GetActiveCharge(ActiveSlot.SLOT_POCKET) .. "+" .. p:GetBatteryCharge(ActiveSlot.SLOT_POCKET) .. " items " .. heldItems(p)
	end
	t[#t + 1] = "COUNT players " .. game:GetNumPlayers() .. " c703 pedestals " .. pedestals(ESAU_JR)
	local rows = dbg().roster.serialize()
	table.sort(rows, function(a, b) return (a.number or -1) < (b.number or -1) end)
	for _, r in ipairs(rows) do
		t[#t + 1] = "ROSTER key " .. tostring(r.key) .. " number " .. tostring(r.number) .. " swapped " .. tostring(r.swapped) .. " partner " .. tostring(r.partner) .. " left " .. tostring(r.left) .. " type " .. tostring(r.type) .. " group " .. tostring(r.group)
	end
	for n, e in ipairs(entries()) do t[#t + 1] = "ENTRY " .. n .. " c" .. e.id .. " owner " .. tostring(e.owner) .. " floor " .. tostring(e.floor) .. " merged " .. tostring(e.merged) .. " temporary " .. tostring(e.temporary) end
	return t
end

local function observe()
	local o = HARNESS.obs
	if not o then return end
	o.u = o.u + 1
	local lines = obsLines()
	local s = table.concat(lines, "\n")
	if s == o.last then return end
	o.last = s
	for _, l in ipairs(lines) do P("OBS u" .. o.u, "after " .. o.step .. ":", l) end
end

local function startObs() HARNESS.obs = { u = 0, step = "start" } end

-- Twelve obsx scenarios at 445 updates each, plus a 1-update SKIP per other scenario and HARNESS DONE, fit three minutes (5385 of 5400
-- with 56 scenarios: one more obsx scenario, or 15 more others, breaks it; the test asserts it); in runs 2-3 none came near.
local OBSX_STEP_LIMIT, OBSX_SCENARIO_LIMIT = 120, 445

-- An obs step: tags later OBS lines with `tag` (unique within its scenario); a step that errors (its postcondition never came) is
-- logged as INFO and skipped, not failed; in an obsx or obsy scenario it also ends the scenario, so later presses cannot run on the
-- wrong setup. `limit` overrides the step ceiling (a Continue waits for the user).
local function obs(tag, step, when, stopOnError, limit)
	limit = limit or OBSX_STEP_LIMIT
	return function(ctx)
		if ctx.obsInterrupted or (not ctx.t and when and not when(ctx)) then return end
		local H = HARNESS
		if H.obs and H.obs.step ~= tag then H.obs.step = tag; P("OBS u" .. H.obs.u, "step " .. tag .. " begins") end
		local ok, res = pcall(step, ctx)
		if ok and stopOnError and res == "again" and not ctx.held and ctx.t >= limit then
			ok, res = false, "obsx ceiling " .. limit .. " updates" .. (ctx.why and (": " .. ctx.why) or "")
		end
		if ok then return res end
		P("INFO", ctx.name, tag, "never happened:", res)
		ctx.obsInterrupted = stopOnError
		ctx.t, ctx.held, ctx.before, ctx.label, ctx.why = nil, nil, nil, nil, nil
		H.press, H.full, H.fullPolled, H.watch, H.cancelClicker, H.pressHash, H.timing = nil, nil, nil, nil, nil, nil, nil
	end
end

-- The settle wait of look, without its checks, capped at 120 updates: a merged flag left on a stored survivor (a known ReHUD bug,
-- obs3 cross and flip) never clears, and obs only notes it.
local function settled(ctx)
	ctx.t = (ctx.t or 0) + 1
	local busy = settling()
	if busy and ctx.t < 120 then stuckAt(ctx, ctx.t, HARNESS.obs and HARNESS.obs.step or "settle") return "again" end
	P("INFO", ctx.name, "settle wait ended after", ctx.t, "updates", busy and ("still settling " .. busy) or "settled")
	ctx.t = nil
end

local function regiveEsauJr()
	local g = give(ESAU_JR)
	return function(ctx)
		if not ctx.t and Isaac.GetPlayer(0):GetActiveItem(ActiveSlot.SLOT_PRIMARY) == ESAU_JR then return P("INFO", ctx.name, "Esau Jr. still in the active slot, no re-give") end
		return g(ctx)
	end
end

local function obsInfo(what, f) return function(ctx) P("INFO", ctx.name, what, f(Isaac.GetPlayer(0))) end end
local pocketHeld = obsInfo("player 0 pocket active (711 = Flip)", function(p) return p:GetActiveItem(ActiveSlot.SLOT_POCKET) end)
local typeNow = obsInfo("player 0 type", function(p) return p:GetPlayerType() end)
local playerCount = obsInfo("players in game", function() return game:GetNumPlayers() end)
local storedSettlingNow = obsInfo("stored forms still settling", storedSettling)
-- Watches `n` updates without acting and logs each change of what ReHUD still settles, so the log shows how long a returned survivor settles.
local function idle(n)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local busy = settling() or "nothing"
		if busy ~= ctx.busy then ctx.busy = busy; P("INFO", ctx.name, "idle update", ctx.t, "settling", busy) end
		if ctx.t < n then return "again" end
		ctx.t, ctx.busy = nil, nil
	end
end

-- An obs scenario: `pre` unlogged (ending in a settle wait), then the logger, then `steps` as { tag, step } pairs, each soft and
-- numbered, then a last settle wait; a step may be a list of pairs, a pair may carry its step ceiling 4th. Markers: c4 before the
-- first swap, c5 right after it. `opts`: kind (default "small") and budget (the scenario ceiling, default OBSX_SCENARIO_LIMIT).
local function strictObs(name) return name:sub(1, 5) == "obsx " or name:sub(1, 5) == "obsy " end
local function obsScenario(name, pre, steps, opts)
	opts = opts or {}
	local all, n = {}, 0
	local stopOnError = strictObs(name)
	for _, s in ipairs(pre) do
		all[#all + 1] = stopOnError and obs("setup " .. (#all + 1), s, nil, true) or s
	end
	all[#all + 1] = stopOnError and obs("setup settle", settled, nil, true) or settled
	all[#all + 1] = startObs
	steps[#steps + 1] = { "settle", settled }
	for _, s in ipairs(steps) do
		for _, pair in ipairs(type(s[1]) == "string" and { s } or s) do
			n = n + 1
			all[#all + 1] = obs(n .. " " .. pair[1], pair[2], pair[3], stopOnError, pair[4])
		end
	end
	return { name = name, kind = opts.kind or "small", steps = all, obsBudget = stopOnError and (opts.budget or OBSX_SCENARIO_LIMIT) }
end
local function jrSetup(playerType) return { restart(playerType), give(4), give(ESAU_JR) } end
local function tlazJr() return jrSetup(T_LAZ) end
local function jrFirst() return { { "Esau Jr.", esauJr("Esau Jr.") }, { "give c5", give(5) } } end
local function jrAgain() return { { "re-give c703", regiveEsauJr() }, { "Esau Jr. again", esauJr("Esau Jr. again") } } end
local PRIMARY = ActiveSlot.SLOT_PRIMARY

local function clickerCallback(name, p, slot)
	local H = HARNESS
	if not H.obs or not strictObs(H.ctx.name) then return end
	P("INFO", H.ctx.name, name, "update", H.obs.u + 1, "type", p:GetPlayerType(),
		"seed", seedOf(p), "slot", slot, "charge", slot >= 0 and p:GetActiveCharge(slot) or "n/a")
end

-- Let ReHUD's default-priority PRE callback see the attempt before returning the veto.
mod:AddPriorityCallback(ModCallbacks.MC_PRE_USE_ITEM, CallbackPriority.LATE, function(_, _, _, p, _, slot)
	clickerCallback("MC_PRE_USE_ITEM", p, slot)
	local cancelled = HARNESS.cancelClicker
	if not cancelled or GetPtrHash(p) ~= cancelled.hash then return end
	cancelled.pre = (cancelled.pre or 0) + 1
	return true
end, CLICKER)

mod:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, _, _, p, _, slot)
	clickerCallback("MC_USE_ITEM", p, slot)
	local cancelled = HARNESS.cancelClicker
	if cancelled and GetPtrHash(p) == cancelled.hash then cancelled.used = (cancelled.used or 0) + 1 end
end, CLICKER)

-- Read the completed input and apply the optional type change before ReHUD observes this update.
mod:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.EARLY, function()
	local H = HARNESS
	local b = H.cancelClicker
	if not b or not b.pre then return end
	H.cancelClicker, H.press = nil, nil
	b.observed = true
	local p = Isaac.GetPlayer(0)
	P("INFO", H.ctx.name, "cancelled Clicker", "update", H.obs.u + 1,
		"type", b.who, "->", snapshot().who, "charge", b.charge, "->", chargeOf(p, CLICKER, PRIMARY),
		"MC_PRE_USE_ITEM calls", b.pre, "MC_USE_ITEM calls", b.used or 0)
	if not b.change then return end
	if seedOf(p) ~= b.seed then
		P("INFO", H.ctx.name, "same-update ChangePlayerType skipped: presser seed disappeared")
		return
	end
	p:ChangePlayerType(T_FORGOTTEN)
	P("INFO", H.ctx.name, "same-update ChangePlayerType", "update", H.obs.u + 1, "type", Isaac.GetPlayer(0):GetPlayerType())
end)

-- shortcut: one veto per press, matched by GetPtrHash of player 0; extend it if a second player must press.
local function cancelledClicker(change)
	return action("cancelled Clicker", function()
		local H, p = HARNESS, Isaac.GetPlayer(0)
		if p:GetActiveItem(PRIMARY) ~= CLICKER then error("Clicker not held in the primary slot") end
		p:SetActiveCharge(itemConfig:GetCollectible(CLICKER).MaxCharges, PRIMARY)
		local b = snapshot()
		b.seed, b.hash, b.change = seedOf(p), GetPtrHash(p), change
		b.charge, b.button, b.arms = p:GetActiveCharge(PRIMARY), ButtonAction.ACTION_ITEM, 0
		H.cancelClicker = b
		arm(H, b)
		return b
	end, function(ctx, b)
		if b.observed then return true end
		if not HARNESS.press and ctx.t < 10 then arm(HARNESS, b) end
		return false, "press did not reach MC_PRE_USE_ITEM"
	end, 10)
end

local obsClicker = swap("Clicker", CLICKER, PRIMARY, nil, 60)
local function jrTwice()
	return jrAgain(), { "re-give c703 #2", regiveEsauJr() }, { "Esau Jr. #2", esauJr("Esau Jr. #2") }
end

local function giveClicker()
	return { { "give Clicker", give(CLICKER) }, { "give c1", give(1) } }
end

local function rememberOriginal(ctx)
	ctx.originalSeed = seedOf(Isaac.GetPlayer(0))
end

local function rememberForm(ctx)
	ctx.formSeed = seedOf(Isaac.GetPlayer(0))
end

local function recordReturn(label)
	return function(ctx)
		P("INFO", ctx.name, label, "A seed", ctx.originalSeed, "present", playerBySeed(ctx.originalSeed) ~= nil)
		if ctx.formSeed then
			P("INFO", ctx.name, label, "B seed", ctx.formSeed, "present", playerBySeed(ctx.formSeed) ~= nil)
		end
	end
end

local function controlPresses()
	return {
		{ "Esau Jr. after intervention", esauJr("Esau Jr. after intervention") },
		{ "record return #1", recordReturn("press #1") },
		{ "Esau Jr. after intervention #2", esauJr("Esau Jr. after intervention #2") },
		{ "record return #2", recordReturn("press #2") },
	}
end

local function loseEsauJr()
	return {
		{ "check Esau Jr. in primary", function()
			if Isaac.GetPlayer(0):GetActiveItem(PRIMARY) ~= ESAU_JR then error("expected Esau Jr. before giving D6") end
		end },
		{ "give D6", give(CollectibleType.COLLECTIBLE_D6) },
		{ "check D6 in primary", function(ctx)
			local p = Isaac.GetPlayer(0)
			if p:GetActiveItem(PRIMARY) ~= CollectibleType.COLLECTIBLE_D6 then error("D6 did not replace Esau Jr.") end
			local n = owned(p, ESAU_JR)
			P("INFO", ctx.name, "c703 owned", n, "pedestals", pedestals(ESAU_JR))
			if n ~= 0 then error("c703 still owned after D6") end
		end },
	}
end

local function replaceEsauJr()
	local t = loseEsauJr()
	t[#t + 1] = { "re-give c703", give(ESAU_JR) }
	return t
end

local useClickerEffect = action("UseActiveItem Clicker", function()
	local p = Isaac.GetPlayer(0)
	if p:GetActiveItem(PRIMARY) ~= ESAU_JR then error("expected Esau Jr. in primary before UseActiveItem") end
	local before = { seed = seedOf(p), who = p:GetPlayerType() }
	p:UseActiveItem(CLICKER, 0)
	return before
end, function(ctx, before)
	local p = playerBySeed(before.seed)
	local who = p and p:GetPlayerType()
	local primary = p and p:GetActiveItem(PRIMARY)
	P("INFO", ctx.name, "UseActiveItem Clicker type", before.who, "->", who, "changed", who ~= nil and who ~= before.who,
		"primary", ESAU_JR, "->", primary)
	if not who or who == before.who then error("UseActiveItem did not verify a type change on the presser") end
	if primary ~= ESAU_JR then error("Esau Jr. did not stay in primary after UseActiveItem") end
	return true
end)

local birthrightFlip = flip("put type 29 in player 0")

-- obsy: INFO-only follow-ups to obsx runs 1-4, run as two modes ("only obsy a", "only obsy b"), each worst case under 5400 updates
-- (3 minutes) counting the 1-update SKIPs of every other scenario (tests/test_harness.py asserts both). Each stops at
-- OBSX_SCENARIO_LIMIT updates, a Continue one at 1000 with 600 for the user's exit and Continue.
local OBSY_CONTINUE_LIMIT, CONTINUE_STEP_LIMIT = 1000, 600
local PEDESTAL, SECONDARY = PickupVariant.PICKUP_COLLECTIBLE, ActiveSlot.SLOT_SECONDARY
local YUM_HEART, SCHOOLBAG = CollectibleType.COLLECTIBLE_YUM_HEART, CollectibleType.COLLECTIBLE_SCHOOLBAG

-- Seeds as labels A, B, C... in first-seen order within the scenario.
local function tagOf(ctx, seed)
	local t = ctx.tags or { n = 0 }
	ctx.tags = t
	if not t[seed] then t.n = t.n + 1; t[seed] = string.char(64 + t.n) end
	return t[seed]
end

-- Every GetPlayer index as index:label(type); a seed first seen here also shows its value.
local function lineup(ctx)
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		local s = seedOf(p)
		local new = not (ctx.tags and ctx.tags[s])
		t[#t + 1] = i .. ":" .. tagOf(ctx, s) .. "(t" .. p:GetPlayerType() .. ")" .. (new and ("=" .. s) or "")
	end
	return table.concat(t, " ")
end

-- The occupant of the pressed index once per game frame for 5 frames from its first sight with a seed other than the
-- presser's: does a new Esau Jr. form hold c703 on its very first update? HARNESS.timing lists one watch per press, as the next
-- press may come within those 5 frames; each watch ends early once its index holds a seed other than that first new one.
local function timingSee(p)
	local list = HARNESS.timing
	if not list then return end
	for i = #list, 1, -1 do
		local t = list[i]
		local occupant = Isaac.GetPlayer(t.index)
		local seed, frame = seedOf(p), game:GetFrameCount()
		if occupant and GetPtrHash(occupant) == GetPtrHash(p) and (seed ~= t.seed or t.first) then
			t.first, t.firstSeed = t.first or frame, t.firstSeed or seed
			if frame - t.first >= 5 or seed ~= t.firstSeed then table.remove(list, i)
			elseif frame ~= t.logged then -- MC_POST_PLAYER_UPDATE runs twice per game frame
				t.logged = frame
				P("INFO", HARNESS.ctx.name, "TIMING", t.label, "frame", frame, "+" .. (frame - t.first), "index", t.index, "seed", seed, "type", p:GetPlayerType(),
					"c703 owned", owned(p, ESAU_JR), "primary", p:GetActiveItem(PRIMARY), "secondary", p:GetActiveItem(SECONDARY), "pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET))
			end
		end
	end
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, p) timingSee(p) end)

-- A swap step plus its verdict line: who holds `index` after it (by label, new or returned) and the whole lineup before and after.
-- `timed` also starts timingSee.
local function verdict(label, step, index, timed)
	index = index or 0
	return function(ctx)
		if not ctx.t then
			ctx.vBefore, ctx.vSeed, ctx.vType, ctx.vSeeds = lineup(ctx), seedOf(Isaac.GetPlayer(index)), Isaac.GetPlayer(index):GetPlayerType(), {}
			for i = 0, game:GetNumPlayers() - 1 do ctx.vSeeds[seedOf(Isaac.GetPlayer(i))] = i end
			if timed then
				HARNESS.timing = HARNESS.timing or {}
				table.insert(HARNESS.timing, { index = index, seed = ctx.vSeed, label = label })
				P("INFO", ctx.name, "TIMING", label, "pressed at frame", game:GetFrameCount())
			end
		end
		local r = step(ctx)
		if r == "again" then return r end
		local p = Isaac.GetPlayer(index)
		local s = p and seedOf(p)
		local known = s and ctx.tags[s]
		local after = lineup(ctx)
		local what
		if not p then what = "nobody"
		elseif s == ctx.vSeed then
			local t = p:GetPlayerType()
			what = "unchanged" .. (t ~= ctx.vType and (" (t" .. ctx.vType .. "->" .. t .. ")") or "")
		elseif ctx.vSeeds[s] then what = tagOf(ctx, s) .. " moved from " .. ctx.vSeeds[s] -- a Birthright Flip swaps the twins' indices
		else what = tagOf(ctx, s) .. (known and " returned" or " new") end
		P("INFO", ctx.name, "VERDICT", label, "index", index, tagOf(ctx, ctx.vSeed), "->", what, "|", ctx.vBefore, "->", after)
	end
end
local function jr(label, who) return verdict(label, swap(label, ESAU_JR, PRIMARY, nil, nil, who), who and who.index, true) end
local function flipV(label) return verdict(label, flip(label)) end

local function slots(p) return "primary " .. p:GetActiveItem(PRIMARY) .. " secondary " .. p:GetActiveItem(SECONDARY) end
-- A real drop press by player 0 (one-shot, re-armed every 10 updates) until `cond(p)`; after 60 updates `fallback(p)` once, pcall'd.
-- Nothing is pressed when `cond` already holds.
local function dropPress(label, cond, fallbackName, fallback)
	return action(label, function(ctx)
		ctx.fell, ctx.already = nil, cond(Isaac.GetPlayer(0))
		if not ctx.already then HARNESS.press = ButtonAction.ACTION_DROP end
	end, function(ctx)
		local H, p = HARNESS, Isaac.GetPlayer(0)
		if cond(p) then
			H.press = nil
			P("INFO", ctx.name, label, "after", ctx.t, "updates by", ctx.already and "nothing (already so)" or ctx.fell and fallbackName or "drop press",
				"|", slots(p), "type", p:GetPlayerType())
			return true
		end
		if ctx.t == 60 then
			H.press, ctx.fell = nil, true
			local ok, err = pcall(fallback, p)
			P("INFO", ctx.name, label, "drop press changed nothing in 60 updates,", fallbackName, ok and "called" or ("failed: " .. tostring(err)))
		elseif not ctx.fell and not H.press and ctx.t % 10 == 0 then H.press = ButtonAction.ACTION_DROP end
		return false, slots(p) .. " type " .. p:GetPlayerType()
	end)
end
local function primaryIs(id) return function(p) return p:GetActiveItem(PRIMARY) == id end end
local function jrToPrimary() return dropPress("Esau Jr. to primary", primaryIs(ESAU_JR), "SwapActiveItems", function(p) p:SwapActiveItems() end) end
local slotsNow = obsInfo("player 0 slots", slots)

-- DropCollectible is REPENTOGON-only in IsaacDocs; logged, not used.
local function dropCollectibleInfo(ctx)
	local p = Isaac.GetPlayer(0)
	local ok, v = pcall(function() return p.DropCollectible end)
	P("INFO", ctx.name, "EntityPlayer.DropCollectible:", ok and type(v) or ("error " .. tostring(v)), "(not used: a pedestal swap instead)")
end

-- A c45 pedestal swaps with the held Esau Jr. on touch, leaving c703 on it. Player 0 goes 80 px off the press spot first, in case a
-- form comes back where it was stored; the pedestal spawns 40 px beside it (one spawned under a player that never moves onto it was
-- never touched in game), its Wait zeroed (pcall'd), and player 0 is put onto it every update.
local dropOnPedestal = action("touch a c45 pedestal", function(ctx)
	local p = Isaac.GetPlayer(0)
	if p:GetActiveItem(PRIMARY) ~= ESAU_JR then error("Esau Jr. not in the primary slot") end
	p.Position = p.Position + Vector(0, 80)
	local pos = p.Position + Vector(40, 0)
	local e = Isaac.Spawn(EntityType.ENTITY_PICKUP, PEDESTAL, YUM_HEART, pos, Vector(0, 0), nil)
	P("INFO", ctx.name, "c45 pedestal Wait = 0:", tostring(pcall(function() e:ToPickup().Wait = 0 end)))
	return pos
end, function(ctx, pos)
	local p = Isaac.GetPlayer(0)
	local n, ped = owned(p, ESAU_JR), pedestals(ESAU_JR)
	if n == 0 and ped > 0 then
		P("INFO", ctx.name, "c703 dropped after", ctx.t, "updates: owned", n, "c703 pedestals", ped, "c45 pedestals", pedestals(YUM_HEART), slots(p))
		return true
	end
	P("INFO", ctx.name, "touch try", ctx.t, "c45 pedestals", pedestals(YUM_HEART), "c703 pedestals", ped, "c703 owned", n)
	p.Velocity, p.Position = Vector(0, 0), pos
	return false, "c703 owned " .. n .. ", c703 pedestals " .. ped
end)

-- Then 10 updates away from it (a swapped pedestal is not re-taken while touched), its Wait zeroed (pcall'd), and onto it every update.
local pickBack = action("walk back onto the c703 pedestal", function()
	local e = Isaac.FindByType(EntityType.ENTITY_PICKUP, PEDESTAL, ESAU_JR)[1]
	if not e then error("no c703 pedestal") end
	return Vector(e.Position.X, e.Position.Y)
end, function(ctx, pos)
	local p = Isaac.GetPlayer(0)
	local n = owned(p, ESAU_JR)
	if n > 0 then
		P("INFO", ctx.name, "c703 picked back after", ctx.t, "updates: owned", n, "c703 pedestals", pedestals(ESAU_JR), "c45 pedestals", pedestals(YUM_HEART), slots(p))
		p.Position = pos + Vector(80, 0) -- off the c45 pedestal, so the form a press brings here cannot swap with it
		return true
	end
	p.Velocity = Vector(0, 0)
	if ctx.t <= 10 then p.Position = pos + Vector(80, 0) return false, "stepping away" end
	if ctx.t == 11 then
		local e = Isaac.FindByType(EntityType.ENTITY_PICKUP, PEDESTAL, ESAU_JR)[1]
		P("INFO", ctx.name, "c703 pedestal Wait = 0:", e and tostring(pcall(function() e:ToPickup().Wait = 0 end)) or "no pedestal")
	end
	p.Position = pos
	return false, "c703 owned 0, c703 pedestals " .. pedestals(ESAU_JR)
end)

-- Every vanilla per-entity id of each player, each read pcall'd; twins as the GetPlayer index whose GetPtrHash matches
-- (no method is called on a returned twin but GetPtrHash).
local function ids(label)
	return function(ctx)
		local index = {}
		for i = 0, game:GetNumPlayers() - 1 do index[GetPtrHash(Isaac.GetPlayer(i))] = i end
		local function try(f)
			local ok, v = pcall(f)
			return ok and tostring(v) or ("error " .. tostring(v))
		end
		for i = 0, game:GetNumPlayers() - 1 do
			local p = Isaac.GetPlayer(i)
			local function twin(m)
				return try(function()
					local t = p[m](p)
					if t == nil then return "nil" end
					local k = index[GetPtrHash(t)]
					return k and ("index " .. k) or "not a player"
				end)
			end
			P("INFO", ctx.name, "IDS", label, "index", i, "type", p:GetPlayerType(), "CollectibleRNG(1)", seedOf(p), "hash", GetPtrHash(p),
				"InitSeed", try(function() return p.InitSeed end), "DropSeed", try(function() return p.DropSeed end), "Index", try(function() return p.Index end),
				"CardRNG(1)", try(function() return p:GetCardRNG(1):GetSeed() end), "PillRNG(1)", try(function() return p:GetPillRNG(1):GetSeed() end),
				"TrinketRNG(1)", try(function() return p:GetTrinketRNG(1):GetSeed() end), "OtherTwin", twin("GetOtherTwin"), "MainTwin", twin("GetMainTwin"))
		end
	end
end

-- Press, press back, press to the form again, the form loses Esau Jr. (D6) and gets it back, two presses. `first`: pairs
-- before the presses; `lose`: pairs for the loss (default: player 0's D6 and re-give).
local function charPresses(who, first, lose)
	return { first or {}, { "Esau Jr. #1", jr("Esau Jr. #1", who) }, { "Esau Jr. #2", jr("Esau Jr. #2", who) }, { "Esau Jr. #3", jr("Esau Jr. #3", who) },
		lose or replaceEsauJr(), { "Esau Jr. #4", jr("Esau Jr. #4", who) }, { "Esau Jr. #5", jr("Esau Jr. #5", who) } }
end
local D6 = CollectibleType.COLLECTIBLE_D6
local esauLoses = { { "check c703 on index 1", function()
		local p = Isaac.GetPlayer(1)
		if not p or p:GetActiveItem(PRIMARY) ~= ESAU_JR then
			error("index 1 does not hold c703 before the D6: " .. (p and ("type " .. p:GetPlayerType() .. " primary " .. p:GetActiveItem(PRIMARY) .. " c703 owned " .. owned(p, ESAU_JR)) or "no player"))
		end
	end },
	{ "Esau gets D6", giveEsau(D6, 1) },
	{ "check D6 on index 1", function(ctx)
		local p = Isaac.GetPlayer(1)
		local n = owned(p, ESAU_JR)
		P("INFO", ctx.name, "index 1 type", p:GetPlayerType(), "primary", p:GetActiveItem(PRIMARY), "c703 owned", n)
		if n ~= 0 then error("c703 still owned by index 1 after D6") end
	end },
	{ "Esau gets c703 back", giveEsau(ESAU_JR, 1) } }
local continued = { "exit and Continue", exitAndContinue(true), nil, CONTINUE_STEP_LIMIT }
local deadFirst = function() return Isaac.GetPlayer(0):GetPlayerType() == DEAD_LAZ end
local LARGE_OBSY = { kind = "large", budget = OBSY_CONTINUE_LIMIT }

local OBSY = {
	-- Does A return after its form drops Esau Jr. as a pedestal and picks it up again?
	obsScenario("obsy a pedestal pick-back", jrSetup(ISAAC), { { "DropCollectible?", dropCollectibleInfo }, { "Esau Jr. #1", jr("Esau Jr. #1") },
		{ "drop c703 on a pedestal", dropOnPedestal }, { "pick c703 back", pickBack }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Does A return after its form held Esau Jr. in the Schoolbag's second slot? Variant: a real Clicker press meanwhile.
	obsScenario("obsy a schoolbag", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, { "give Schoolbag", give(SCHOOLBAG) }, { "give c45", give(YUM_HEART) },
		{ "slots after c45", slotsNow },
		{ "Esau Jr. to secondary", dropPress("Esau Jr. to secondary", function(p) return p:GetActiveItem(SECONDARY) == ESAU_JR end, "SwapActiveItems", function(p) p:SwapActiveItems() end) },
		{ "Esau Jr. to primary", jrToPrimary() }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	obsScenario("obsy a schoolbag Clicker", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, { "give Schoolbag", give(SCHOOLBAG) }, giveClicker(),
		{ "slots after Clicker", slotsNow }, { "Clicker to primary", dropPress("Clicker to primary", primaryIs(CLICKER), "SwapActiveItems", function(p) p:SwapActiveItems() end) },
		{ "Clicker", verdict("Clicker", obsClicker) }, { "slots after the Clicker press", slotsNow }, { "Esau Jr. to primary", jrToPrimary() },
		{ "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Once A is lost, does A's Dead form X (or A) ever come back through B's Flips or presses?
	obsScenario("obsy a Dead form after A lost", tlazJr(), { { "Flip", flipV("Flip") }, { "Flip back", flipV("Flip back") }, { "Esau Jr. #1", jr("Esau Jr. #1") },
		replaceEsauJr(), { "Flip of B", flipV("Flip of B") }, { "Flip back to B", flipV("Flip back to B") }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Clicker's effect with Esau Jr. kept, on a non-Lazarus character.
	obsScenario("obsy a Isaac Clicker effect", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, { "give c1", give(1) },
		{ "use Clicker effect", useClickerEffect }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Other characters.
	obsScenario("obsy a J&E by Jacob", jrSetup(JE), charPresses()),
	obsScenario("obsy a J&E by Esau", { restart(JE), give(4), giveEsau(ESAU_JR) }, charPresses({ index = 1 }, nil, esauLoses)),
	obsScenario("obsy a Forgotten and Soul", jrSetup(PlayerType.PLAYER_THEFORGOTTEN), charPresses(nil, {
		{ "Esau Jr. as Forgotten #1", jr("Esau Jr. as Forgotten #1") }, { "Esau Jr. as Forgotten #2", jr("Esau Jr. as Forgotten #2") },
		{ "switch to the Soul", dropPress("switch to the Soul", function(p) return p:GetPlayerType() == PlayerType.PLAYER_THESOUL end,
			"ChangePlayerType 17", function(p) p:ChangePlayerType(PlayerType.PLAYER_THESOUL) end) } })),
	obsScenario("obsy a Tainted Forgotten", jrSetup(T_FORGOTTEN), charPresses({ index = 0, any = true })),
	obsScenario("obsy a Lazarus Risen", jrSetup(PlayerType.PLAYER_LAZARUS), charPresses(nil, { { "ChangePlayerType 11", changeType(PlayerType.PLAYER_LAZARUS2) } })),
	-- Locked on save slot 1 (README): a restart that never gives the type ends the scenario with an INFO "character locked?" line.
	obsScenario("obsy b Tainted Jacob", jrSetup(PlayerType.PLAYER_JACOB_B), charPresses()),
	obsScenario("obsy b Eden", jrSetup(PlayerType.PLAYER_EDEN), charPresses()),
	-- Does a stored A survive exit and Continue, and does a lost one stay lost?
	obsScenario("obsy b continue with A stored", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, continued,
		{ "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }, LARGE_OBSY),
	obsScenario("obsy b continue after B loses Esau Jr.", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, loseEsauJr(), continued,
		{ "re-give c703", give(ESAU_JR) }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") }, { "Esau Jr. #4", jr("Esau Jr. #4") } }, LARGE_OBSY),
	-- Which id tells the two Birthright forms apart and stays stable across Flip, Esau Jr. and Continue?
	obsScenario("obsy b identity", { restart(T_LAZ), give(4), give(ESAU_JR), give(BIRTHRIGHT, 2) }, { { "ids after Birthright", ids("after Birthright") },
		{ "Flip", flipV("Flip") }, { "ids after Flip", ids("after Flip") }, { "Flip back", flipV("Flip back") }, { "ids after Flip back", ids("after Flip back") },
		{ "select type-29 twin", birthrightFlip, deadFirst }, { "Esau Jr. #1", jr("Esau Jr. #1") }, { "ids after Esau Jr. #1", ids("after Esau Jr. #1") },
		{ "Esau Jr. #2", jr("Esau Jr. #2") }, { "ids after Esau Jr. #2", ids("after Esau Jr. #2") }, continued, { "ids after Continue", ids("after Continue") },
		{ "Flip after Continue", flipV("Flip after Continue") }, { "ids after Flip after Continue", ids("after Flip after Continue") } }, LARGE_OBSY),
}

local OBS = {
	obsScenario("obs esaujr cross", tlazJr(), { jrFirst(), { "ChangePlayerType 38", changeType(DEAD_LAZ) }, { "ChangePlayerType 0", changeType(ISAAC) }, jrAgain() }),
	obsScenario("obs esaujr out", tlazJr(), { jrFirst(), { "ChangePlayerType 0", changeType(ISAAC) }, jrAgain() }),
	obsScenario("obs esaujr flip", tlazJr(), { jrFirst(), { "pocket of the form", pocketHeld }, { "Flip of the form", flip("Flip of the form") },
		{ "Flip back", flip("Flip back") }, jrAgain() }),
	obsScenario("obs esaujr flipped cross", tlazJr(), { { "Flip", flip("Flip") }, { "give c5", give(5) }, { "Flip back", flip("Flip back") },
		{ "Esau Jr.", esauJr("Esau Jr.") }, { "ChangePlayerType 38", changeType(DEAD_LAZ) }, jrAgain(),
		{ "Flip A", flip("Flip A") }, { "re-give c703 #2", regiveEsauJr() }, { "Esau Jr. #2", esauJr("Esau Jr. #2") },
		{ "Flip of the Esau Jr. form", flip("Flip of the Esau Jr. form") } }),
	obsScenario("obs esaujr birthright", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT) }, { "remove Birthright", remove(BIRTHRIGHT) },
		{ "settle", settled }, { "restart", restart(T_LAZ) }, { "give c4", give(4) }, { "give c703", give(ESAU_JR) }, { "give Birthright", give(BIRTHRIGHT) },
		{ "settle", settled }, jrFirst(), jrAgain() }),
	obsScenario("obs esaujr clicker", tlazJr(), { jrFirst(), { "give Clicker", give(CLICKER) }, { "Clicker", clicker }, { "Clicker roll", typeNow },
		{ "settle", settled }, jrAgain(),
		{ "re-give c703 #3", regiveEsauJr() }, { "Esau Jr. #3", esauJr("Esau Jr. #3") },
		{ "re-give c703 #4", regiveEsauJr() }, { "Esau Jr. #4", esauJr("Esau Jr. #4") } }),
	obsScenario("obs mirror", { restart(T_LAZ), give(4) }, { { "Flip", flip("Flip") }, { "give c5", give(5) }, { "Flip back", flip("Flip back") },
		{ "ChangePlayerType 38", changeType(DEAD_LAZ) }, { "pocket before Flip again", pocketHeld }, { "players before Flip again", playerCount },
		{ "Flip again", flip("Flip again") }, { "pocket after Flip again", pocketHeld }, { "players after Flip again", playerCount } }),
	obsScenario("obs esaujr birthright keep", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT) }, { "settle", settled }, jrAgain() }),
	obsScenario("obs esaujr cross35", tlazJr(), { jrFirst(), { "ChangePlayerType 35", changeType(T_FORGOTTEN) }, { "settle", settled }, jrAgain(),
		{ "re-give c703 #3", regiveEsauJr() }, { "Esau Jr. #3", esauJr("Esau Jr. #3") } }),
	obsScenario("obs esaujr dead seed", tlazJr(), { jrFirst(), jrAgain(), { "pocket before Flip on A", pocketHeld }, { "Flip on A", flip("Flip on A") } }),
	obsScenario("obs esaujr birthright flip", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT) }, { "settle", settled },
		{ "Flip", flip("Flip") } }),
	obsScenario("obsx cancelled Clicker", tlazJr(), { jrFirst(), giveClicker(),
		{ "cancel Clicker", cancelledClicker(false) }, jrAgain() }),
	obsScenario("obsx cancelled Clicker then change", tlazJr(), { jrFirst(), giveClicker(),
		{ "cancel Clicker and change type", cancelledClicker(true) }, jrAgain() }),
	obsScenario("obsx Clicker on returned original", tlazJr(), { jrFirst(), jrAgain(), giveClicker(),
		{ "Clicker", obsClicker }, jrTwice() }),
	obsScenario("obsx Clicker after Flip", tlazJr(), { jrFirst(), { "Flip of the form", flip("Flip of the form") },
		giveClicker(), { "Clicker", obsClicker }, jrTwice() }),
	obsScenario("obsx Clicker with Birthright", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT, 2) },
		{ "select type-29 twin", birthrightFlip, function() return Isaac.GetPlayer(0):GetPlayerType() == DEAD_LAZ end },
		giveClicker(), { "Clicker by type 29", function(ctx)
			if not ctx.t and (Isaac.GetPlayer(0):GetPlayerType() ~= T_LAZ or not playerOfType(DEAD_LAZ)) then
				error("expected type 29 in player 0 with the type-38 Birthright twin present")
			end
			return obsClicker(ctx)
		end }, jrTwice() }),
	obsScenario("obsx Isaac Esau Jr Clicker", jrSetup(ISAAC), { jrFirst(),
		giveClicker(), { "Clicker", obsClicker }, jrTwice() }),
	-- ReHUD 3021a90 tracker.lua:211: a merge survivor stored inside its 30-update settle, then returned. remove c4 stands in for the copy
	-- Clicker's removal can take; ChangePlayerType makes the merge deterministic.
	obsScenario("obsx merge 38 to 29 then Flip", { restart(T_LAZ), give(4) }, { { "Flip", flip("Flip") }, { "give c5", give(5) },
		{ "ChangePlayerType 29", changeType(T_LAZ) }, { "remove c4", remove(4) }, { "Flip at once", flip("Flip at once") },
		{ "stored settling", storedSettlingNow }, { "settle", settled }, { "Flip back", flip("Flip back") }, { "watch 60", idle(60) } }),
	obsScenario("obsx merge 29 to 38 then Esau Jr.", tlazJr(), { { "Flip", flip("Flip") }, { "give c5", give(5) }, { "Flip back", flip("Flip back") },
		{ "ChangePlayerType 38", changeType(DEAD_LAZ) }, { "remove c4", remove(4) }, { "Esau Jr. at once", esauJr("Esau Jr. at once") },
		{ "stored settling", storedSettlingNow }, { "settle", settled }, jrAgain(), { "watch 60", idle(60) } }),
	obsScenario("obsx form loses Esau Jr.", tlazJr(), {
		{ "record A", rememberOriginal }, jrFirst(), replaceEsauJr(), controlPresses() }),
	obsScenario("obsx form uses Clicker effect", tlazJr(), {
		{ "record A", rememberOriginal }, jrFirst(), { "give c1", give(1) }, { "use Clicker effect", useClickerEffect }, controlPresses() }),
	obsScenario("obsx Isaac form loses Esau Jr.", jrSetup(ISAAC), {
		{ "record A", rememberOriginal }, jrFirst(), replaceEsauJr(), controlPresses() }),
	obsScenario("obsx original loses Esau Jr.", tlazJr(), {
		{ "record A", rememberOriginal }, jrFirst(), { "record B", rememberForm },
		{ "Esau Jr. back to A", esauJr("Esau Jr. back to A") },
		{ "verify A returned", function(ctx)
			if seedOf(Isaac.GetPlayer(0)) ~= ctx.originalSeed then error("expected original A in player 0") end
		end },
		replaceEsauJr(), controlPresses() }),
}
for _, s in ipairs(OBSY) do OBS[#OBS + 1] = s end

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
	-- Three runs: ChangePlayerType out on the Esau Jr. form, then Esau Jr. again (swap refills its 1 charge, spent by the first press);
	-- a Flip of the Esau Jr. form, whose new Dead form is turned Isaac; and the 29->38 crossing on the Esau Jr. form of a flipped one.
	{ name = "P4c", kind = "small", steps = {
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("before Esau Jr.", origBeforeEsauJr),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", esauJrForm), changeType(ISAAC),
		look("after ChangePlayerType on the form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(0) on the Esau Jr. form")
			expect(ctx, label .. ": player 0 is the form", seedOf(Isaac.GetPlayer(0)), ctx.form)
			origStored(ctx, label)
		end),
		esauJr("Esau Jr. 2"), look("after Esau Jr. 2", function(ctx, label)
			engineInfo(ctx, "after Esau Jr. from the form turned Isaac")
			expect(ctx, label .. ": player 0 is the original", seedOf(Isaac.GetPlayer(0)), ctx.orig)
			expectOne(ctx, label, 4, ctx.floors[1], ctx.orig)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("before Esau Jr.", origBeforeEsauJr),
		esauJr("Esau Jr."), look("after Esau Jr.", esauJrForm), flip("Flip of the form"),
		look("after Flip of the form", function(ctx, label)
			engineInfo(ctx, "after a Flip of the Esau Jr. form")
			ctx.dead = seedOf(Isaac.GetPlayer(0))
			expect(ctx, label .. ": a new Dead form", ctx.dead ~= ctx.orig and ctx.dead ~= ctx.form and Isaac.GetPlayer(0):GetPlayerType() == DEAD_LAZ, true)
			expect(ctx, label .. ": form stored", dbg().roster.isSwapped(ctx.form), true)
			origStored(ctx, label)
		end),
		give(ESAU_JR), -- so the original stays revivable (invariant 3) once the Dead form is no Tainted Lazarus
		changeType(ISAAC), look("after ChangePlayerType on the Dead form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(0) on the Esau Jr. form's Dead form")
			expect(ctx, label .. ": form merged", dbg().roster.number(ctx.form), nil)
			origStored(ctx, label)
		end),
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), flip("Flip back"), give(ESAU_JR),
		look("before Esau Jr.", function(ctx, label)
			origBeforeEsauJr(ctx, label)
			for _, e in ipairs(entries()) do
				if e.id == 5 then ctx.dead = e.owner end
			end
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.dead)
		end),
		esauJr("Esau Jr."), look("after Esau Jr.", esauJrForm), changeType(DEAD_LAZ),
		look("after the crossing on the form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(38) on the Esau Jr. form")
			expect(ctx, label .. ": player 0 is the form", seedOf(Isaac.GetPlayer(0)), ctx.form)
			expect(ctx, label .. ": Dead form stored", dbg().roster.isSwapped(ctx.dead), true)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.dead)
			origStored(ctx, label)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
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

-- The obs scenarios run after P4c, the scenario they observe the engine for.
for i, s in ipairs(SCENARIOS) do
	if s.name == "P4c" then
		for k, o in ipairs(OBS) do table.insert(SCENARIOS, i + k, o) end
		break
	end
end

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
	P("RESULT", sc.name, verdict .. (ctx.lateContinue and "; late Continue mid-scenario" or ""))
	H.obs, H.cancelClicker, H.timing, H.pressHash = nil, nil, nil, nil
	H.lateContinue = H.expectStart == "continue" or nil -- the user may still Continue after the step gave up, during the next scenario
	H.si, H.pi, H.expectStart, H.press, H.full, H.fullPolled, H.watch = H.si + 1, 1, nil, nil, nil, nil, nil -- a timed-out press must not reach the next scenario
	H.ctx = { floors = {}, fails = {}, notes = {} }
end

local function tick()
	local H = HARNESS
	observe()
	if not H.running then return end
	local sc = SCENARIOS[H.si]
	if not sc then
		H.running, H.status = false, "DONE: exit to the menu, then tell Claude" -- exiting flushes log.txt (run 1)
		P("HARNESS DONE")
		return
	end
	if H.pi == 1 and H.only and sc.name:sub(1, #H.only) ~= H.only then
		P("RESULT", sc.name, "SKIP not " .. H.only .. " (" .. H.mode .. " mode)")
		H.si = H.si + 1
		return
	end
	if H.pi == 1 and not H.only and sc.kind == "large" and not sc.new and H.mode ~= "regression" then
		P("RESULT", sc.name, "SKIP large and not new (" .. H.mode .. " mode)")
		H.si = H.si + 1
		return
	end
	if sc.obsBudget then
		local ctx = H.ctx
		if ctx.obsInterrupted then return finish() end
		ctx.obsUpdates = (ctx.obsUpdates or 0) + 1
		if ctx.obsUpdates >= sc.obsBudget then
			P("INFO", sc.name, "scenario ceiling", sc.obsBudget, "updates")
			H.pending = nil
			return finish()
		end
	end
	if H.pending then return end
	local step = sc.steps[H.pi]
	if not step then return finish() end
	if not H.ctx.name then P("SCENARIO START", sc.name) end -- tools/run_report.py pairs it with a RESULT
	H.ctx.name, H.ctx.leftOk = sc.name, sc.leftOk
	local label = H.ctx.label
	H.ask = label and label:find("Continue") and label or nil -- the user's own step gets its own line, so it is not lost at the end of a long status
	H.status = sc.name .. " step " .. H.pi .. "/" .. #sc.steps .. ((label and not H.ask) and (": " .. label) or "")
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
	if H.ask and H.running then Isaac.RenderText(H.ask, 60, 44, 1, 1, 0, 1) end
end)

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	local H = HARNESS
	H.gen, H.continued = H.gen + 1, isContinued
	P("GAME START", H.gen, "continued", isContinued)
	if not H.started then
		if isContinued then P("HARNESS idle: start a new run to test") return end
		-- The mode file is data\rehud_test_harness\save<slot>.dat in the game folder (metadata.xml <directory>), written before launch:
		-- "regression" runs every scenario; "only <prefix>" just the scenarios whose name starts with it, whatever their kind; anything else, or none, runs the small ones and the new large ones.
		local raw = mod:LoadData()
		H.modLine = raw:match("^[^\r\n]*") -- the first line only: a STUCK line left below it never changes the mode
		local text = H.modLine:match("^%s*(.-)%s*$")
		H.only = text:match("^only (.+)$")
		H.started, H.running, H.mode = true, true, text == "regression" and "regression" or H.only and ("only " .. H.only) or "default"
		P("HARNESS START", #SCENARIOS, "scenarios,", H.mode, "mode, mod data of '" .. mod.Name .. "' read", string.format("%q", raw))
		return
	end
	if H.running and not H.expectStart then
		if not (isContinued and H.lateContinue) then return finish("unexpected game start (hold-R, new run or continue)") end
		P("INFO", H.ctx.name or SCENARIOS[H.si].name, "late Continue, ignored")
		H.lateContinue, H.ctx.lateContinue = nil, true
	end
	H.expectStart = nil
end)
