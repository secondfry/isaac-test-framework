-- Real presses of the swap items (Flip, Esau Jr., Clicker, a card) and the input, use and veto handlers they need.
local P = include("scripts.log").P
local act = include("scripts.wait").act
local callbacks = include("scripts.callbacks")
local engine = include("scripts.game")
local itemConfig, seedOf, cards, heldItems, chargeOf, byHash, slots = engine.itemConfig, engine.seedOf, engine.cards, engine.heldItems,
	engine.chargeOf, engine.byHash, engine.slots
local ids = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, DEAD_T_LAZ, T_FORGOTTEN, PRIMARY, SECONDARY = ids.FLIP, ids.ESAU_JR, ids.CLICKER, ids.DEAD_T_LAZ, ids.T_FORGOTTEN,
	ids.PRIMARY, ids.SECONDARY

local game = Game()
-- The press in flight (oneShot, full, watch...), the Clicker veto, and the triggered and pressed polls answered.
HARNESS.press = HARNESS.press or { fired = 0, pressed = 0 }

-- The presser's player count and type/seed, before and after a press.
local function presserState(index)
	local p = Isaac.GetPlayer(index or 0)
	return { count = game:GetNumPlayers(), who = p:GetPlayerType() .. "/" .. seedOf(p) }
end

-- A stored presser (Esau Jr., Flip without Birthright) has no vanilla accessor, but its charge + battery drop shows on its own entity
-- after its MC_USE_ITEM and before the engine stores it (runs 6-7), so the watch (set by press) keeps the first such reading as `seen`.
-- The presser is matched by GetPtrHash, as a new form can take its seed (obsx run2/run6 "obs esaujr flip", obsyb1-2).
-- shortcut: rests on J510's order; if a swap FAILs "seen with no drop", log every channel around the press again to find where the drop moved.
local function watchSee(channel, e)
	local w = HARNESS.press.watch
	if not (w and w.used and not w.seen and e) then return end -- MC_INPUT_ACTION is polled ~1470/s: cheap exit first
	local p = e:ToPlayer()
	if not (p and GetPtrHash(p) == w.hash and p:GetActiveItem(w.slot) == w.id) then return end
	local c = p:GetActiveCharge(w.slot) + p:GetBatteryCharge(w.slot)
	if c < w.total then w.seen = channel .. " charge+battery " .. w.total .. " -> " .. c end
end
local function onUse(_, item, _, p)
	local w = HARNESS.press.watch
	if w and item == w.id and p and GetPtrHash(p) == w.hash then w.used = true end
end
local function onPlayerUpdate(_, p) watchSee("POST_PLAYER_UPDATE", p) end

-- A real press, by player 0, of two kinds. oneShot: true once, on the first triggered poll of that button (cards and ACTION_ITEM;
-- one-shot, so a card press cannot also use the next pocket item). full: true to every triggered and pressed poll of that button
-- from its first poll (fullPolled) to the next MC_POST_UPDATE after it. With Flip in the pocket an update polls PILLCARD
-- triggered, pressed, triggered, and Flip reads the second triggered (the user's console probe), which the one-shot never answers; with
-- only cards held it polls triggered twice and never pressed (runs 4-5).
local function onInput(_, e, hook, button)
	local H = HARNESS.press
	watchSee("INPUT_ACTION", e)
	if not (H.oneShot or H.full) or hook == InputHook.GET_ACTION_VALUE or not e then return end -- polled ~1470/s: cheap exit first
	-- H.pressHash: the pressing entity's hash (press's `who`), false for any entity, nil for player 0.
	if H.pressHash ~= false and GetPtrHash(e) ~= (H.pressHash or GetPtrHash(Isaac.GetPlayer(0))) then return end
	if button == H.full or (type(H.full) == "table" and H.full[button]) then
		H.fullPolled = true
		if hook == InputHook.IS_ACTION_TRIGGERED then H.fired = H.fired + 1 else H.pressed = H.pressed + 1 end
		return true
	end
	if hook ~= InputHook.IS_ACTION_TRIGGERED or button ~= H.oneShot then return end
	H.oneShot, H.fired = nil, H.fired + 1
	return true
end

-- Called from MC_POST_UPDATE: true once the full press is over. It ends at the first update after its first poll, so it spans one
-- update's input whether that poll came from a render frame or the update; a press never polled stays down, and shows as fired 0.
local function fullOver(H)
	if H.fullPolled then H.full, H.fullPolled = nil, nil end
	return not H.full
end

-- How the use spent `id`, or nil and what was read. `b` is the presser before the press: its hash and full charge or card count.
-- A stored presser passes only on the drop its watch saw before the engine stored it.
local function spentHow(b, id, slot)
	local presser = byHash(b.hash)
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
	local w = HARNESS.press.watch
	if w and w.seen then return "spent stored presser charge, " .. w.seen end
	return nil, "stored presser seen with no drop after its use, " .. read
end

-- Ends any press in flight, so a finished or timed-out one cannot reach the next step.
local function endPress()
	local H = HARNESS.press
	H.oneShot, H.full, H.fullPolled, H.pressHash, H.watch, H.swapItem = nil, nil, nil, nil, nil, nil
end
-- A finished or given-up step's press state, the Clicker veto included.
local function teardown()
	endPress()
	HARNESS.press.cancelClicker = nil
end

local function arm(H, b)
	if b.full then H.full = b.button else H.oneShot = b.button end
	b.arms = b.arms + 1
end

-- Readies the presser `p` for a press of `id`: a card's count, or the active charged full (so a drop is visible) and watched; returns
-- the PRESS line's charge text.
local function prime(p, id, slot, b, H, label)
	if slot == "card" then
		b.cards = cards(p, id)
		if b.cards == 0 then error(label .. ": card " .. id .. " not held") end
		return ""
	end
	if p:GetActiveItem(slot) ~= id then error(label .. ": c" .. id .. " not in slot " .. slot) end
	-- ItemConfig MaxCharges reads 6 for Flip, but REP+ Flip takes 4, and SetActiveCharge(6, 2) gave 4 + 2 battery (user, in game);
	-- FullCharge without force fills the first bar only (run 3: charge 4, battery 0).
	if slot == ActiveSlot.SLOT_POCKET then p:FullCharge(slot)
	else p:SetActiveCharge(itemConfig:GetCollectible(id).MaxCharges, slot) end
	b.charge = p:GetActiveCharge(slot)
	-- Only active slots: watchSee reads GetActiveItem(slot), which a "card" slot would make throw in MC_INPUT_ACTION.
	H.watch = { hash = b.hash, id = id, slot = slot, total = b.charge + p:GetBatteryCharge(slot) }
	return " charge " .. b.charge .. " battery " .. p:GetBatteryCharge(slot)
end

-- Recon data: after a Continue a press made a new entity with the old seed and type, its items re-rolled (obsy b run 1). True, logged
-- as INFO, when a snapshot test's press (b.items set) spent and left the pressed index on its seed and type with a new entity or other items.
-- `c`: the presser's charge now; a gone presser's spend is the drop its watch saw before the engine stored it.
-- ctx.sameSeed tells record.verdict to drop this press's TIMING watch: the seed never changes, so it would wake on a later press.
local function sameSeedForm(ctx, label, b, presser, c, index)
	local H, p = HARNESS.press, Isaac.GetPlayer(index)
	local spent = (c and c < b.charge and ("charge " .. b.charge .. " -> " .. c)) or (not presser and H.watch and H.watch.seen)
	if not (spent and b.items and (GetPtrHash(p) ~= b.hash or heldItems(p) ~= b.items)) then return end
	local how = GetPtrHash(p) ~= b.hash and ("new form, same seed " .. b.seed .. ", hash " .. b.hash .. " -> " .. GetPtrHash(p)) or ("acted in place: same seed " .. b.seed)
	P("INFO", ctx.name, label, how .. ", items " .. b.items .. " -> " .. heldItems(p) .. ", " .. spent)
	endPress()
	ctx.arms, ctx.sameSeed = b.arms, label
	return true
end

-- Every character swap: player 0 presses `id` (active in `slot`, or a held card with slot "card"), and it is done only when a new
-- character appears (`count` players after, when given) and the use spent the charge or the card.
-- A pocket active takes the full press; cards and ACTION_ITEM the one-shot (one-shot: run 2; full press: runs 4-5).
-- `who` (obsy): { index = GetPlayer index of the presser, any = answer every entity's polls }; its press is a full one of ACTION_ITEM
-- and ACTION_PILLCARD both, as which button and entity use a second player's or Tainted Forgotten's active is unknown.
local function press(label, id, slot, count, ceiling, who)
	local index = who and who.index or 0
	local button = slot == ActiveSlot.SLOT_PRIMARY and ButtonAction.ACTION_ITEM or ButtonAction.ACTION_PILLCARD
	if who then button = { [ButtonAction.ACTION_ITEM] = true, [ButtonAction.ACTION_PILLCARD] = true } end
	return act(label, function(ctx)
		local p, H = Isaac.GetPlayer(index), HARNESS.press
		local b = presserState(index)
		ctx.mark = callbacks.mark() -- assert.fired counts from here
		H.pressHash, H.swapItem = nil, id -- characters.track: a character leaving play now is stored (Esau Jr., Flip) or not
		if who and who.any then H.pressHash = false elseif who then H.pressHash = GetPtrHash(p) end
		-- shortcut: the full press answers both triggered polls of its update, safe only while the pocket holds no card (a card reads
		-- the first, Flip the second); Flip's charge of 4 is spent by one use, so it cannot flip twice. Revisit for a card beside Flip.
		b.seed, b.button, b.full, b.index, b.hash = seedOf(p), button, slot == ActiveSlot.SLOT_POCKET or who ~= nil, index, GetPtrHash(p)
		-- Only a recon test takes a same-seed new form as a press (see below); one with assertions (F, G trace too) needs a new character.
		local trace = HARNESS.record.trace
		if trace and not trace.asserting then b.items = heldItems(p) end
		local read = prime(p, id, slot, b, H, label)
		b.arms, b.fired, b.pressed = 0, H.fired, H.pressed
		arm(H, b)
		P("PRESS", label, "button", who and "ITEM+PILLCARD" or button, (b.full and "full" or "one-shot") .. read, who and ("player " .. index .. (who.any and ", any entity" or "")) or "")
		return b
	end, function(ctx, b)
		local H, a = HARNESS.press, presserState(index)
		local polls = "arms " .. b.arms .. ", fired " .. (H.fired - b.fired) .. ", pressed " .. (H.pressed - b.pressed)
		if a.who == b.who and a.count == b.count then
			-- A use that spends the charge and swaps nothing (obs2: Flip on a 38 whose other form is gone) never swaps later: stop early.
			local presser = byHash(b.hash)
			local c = slot ~= "card" and chargeOf(presser, id, slot)
			if sameSeedForm(ctx, label, b, presser, c, index) then return true end
			if c and c < b.charge and ctx.t >= 30 then error(label .. ": charge spent " .. b.charge .. " -> " .. c .. ", no new character after " .. ctx.t .. " updates") end
			-- shortcut: re-arms until a new character shows (the one-shot each update, the full press one update after its release, so
			-- each is a fresh press), in case the first poll was not the use logic; a press shown late could fire twice, harmless while the
			-- presser holds no battery or second card; count uses per swap before a test gives either.
			if b.full then
				if b.released then arm(H, b); b.released = nil elseif fullOver(H) then b.released = true end
			elseif not H.oneShot then arm(H, b) end
			return false, "no new character, " .. polls -- fired 0: the use logic never polled the press
		end
		H.oneShot, H.full, H.fullPolled, H.pressHash = nil, nil, nil, nil
		if count and a.count ~= count then return false, a.count .. " players, want " .. count end
		local how, read = spentHow(b, id, slot)
		if not how then
			-- A spend not found 30 updates after the new character never shows (obs3 birthright "Esau Jr. again"): stop early.
			b.newAt = b.newAt or ctx.t
			if ctx.t - b.newAt >= 30 then error(label .. ": new character but spent nothing: " .. read .. " after " .. ctx.t .. " updates") end
			return false, "spent nothing: " .. read
		end
		H.watch, H.swapItem, ctx.arms = nil, nil, b.arms
		P("SWAP", label, b.who, "->", a.who, "players", b.count, "->", a.count, how, polls)
		return true
	end, ceiling)
end

local function flip(label) return press(label, FLIP, ActiveSlot.SLOT_POCKET) end
local function esauJr(label) return press(label, ESAU_JR, ActiveSlot.SLOT_PRIMARY) end
-- On Isaac, not beside Flip: a card beside a pocket active sits in slot 1 (run 5) and is untested with either press.
local soulJE = press("Soul of Jacob and Esau", Card.CARD_SOUL_JACOB, "card", 2)

local clicker = press("Clicker", CLICKER, ActiveSlot.SLOT_PRIMARY)

-- Clicker's callbacks, logged in a recon test that ends at its first missing step (obsx, obsy).
local function clickerCallback(name, p, slot)
	local trace, ctx = HARNESS.record.trace, HARNESS.session.ctx
	if not trace or ctx.onStepError ~= "end" then return end
	P("INFO", ctx.name, name, "update", trace.u + 1, "type", p:GetPlayerType(),
		"seed", seedOf(p), "slot", slot, "charge", slot >= 0 and p:GetActiveCharge(slot) or "n/a")
end

-- Let ReHUD's default-priority PRE callback see the attempt before returning the veto.
local function onVetoPre(_, _, _, p, _, slot)
	clickerCallback("MC_PRE_USE_ITEM", p, slot)
	local cancelled = HARNESS.press.cancelClicker
	if not cancelled or GetPtrHash(p) ~= cancelled.hash then return end
	cancelled.pre = (cancelled.pre or 0) + 1
	return true
end

local function onClickerUse(_, _, _, p, _, slot) clickerCallback("MC_USE_ITEM", p, slot) end

-- Read the completed input and apply the optional type change before ReHUD observes this update.
local function onVetoUpdate()
	local H, ctx = HARNESS.press, HARNESS.session.ctx
	local b = H.cancelClicker
	if not b or not b.pre then return end
	H.cancelClicker, H.oneShot = nil, nil
	b.observed = true
	local p, u = Isaac.GetPlayer(0), HARNESS.record.trace.u + 1
	P("INFO", ctx.name, "cancelled Clicker", "update", u,
		"type", b.who, "->", presserState().who, "charge", b.charge, "->", chargeOf(p, CLICKER, PRIMARY),
		"MC_PRE_USE_ITEM calls", b.pre, "MC_USE_ITEM calls", callbacks.since(b.mark, ModCallbacks.MC_USE_ITEM, CLICKER))
	if not b.change then return end
	if seedOf(p) ~= b.seed then
		P("INFO", ctx.name, "same-update ChangePlayerType skipped: presser seed disappeared")
		return
	end
	p:ChangePlayerType(T_FORGOTTEN)
	P("INFO", ctx.name, "same-update ChangePlayerType", "update", u, "type", Isaac.GetPlayer(0):GetPlayerType())
end

-- shortcut: one veto per press, matched by GetPtrHash of player 0; extend it if a second player must press.
local function cancelledClicker(change)
	return act("cancelled Clicker", function(ctx)
		local H, p = HARNESS.press, Isaac.GetPlayer(0)
		if p:GetActiveItem(PRIMARY) ~= CLICKER then error("Clicker not held in the primary slot") end
		p:SetActiveCharge(itemConfig:GetCollectible(CLICKER).MaxCharges, PRIMARY)
		local b = presserState()
		b.seed, b.hash, b.change = seedOf(p), GetPtrHash(p), change
		b.charge, b.button, b.arms = p:GetActiveCharge(PRIMARY), ButtonAction.ACTION_ITEM, 0
		ctx.mark = callbacks.mark()
		b.mark = ctx.mark
		H.cancelClicker = b
		arm(H, b)
		return b
	end, function(ctx, b)
		local H = HARNESS.press
		if b.observed then return true end
		if not H.oneShot and ctx.t < 10 then arm(H, b) end
		return false, "press did not reach MC_PRE_USE_ITEM"
	end, 10)
end

local clickerWithin60 = press("Clicker", CLICKER, PRIMARY, nil, 60)

local birthrightFlip = flip("put type 29 in player 0")

-- A real drop press by player 0 (one-shot, re-armed every 10 updates) until `cond(p)`; after 60 updates `fallback(p)` once, pcall'd.
-- Nothing is pressed when `cond` already holds.
local function dropPress(label, cond, fallbackName, fallback)
	return act(label, function(ctx)
		ctx.fell, ctx.already = nil, cond(Isaac.GetPlayer(0))
		if not ctx.already then HARNESS.press.oneShot = ButtonAction.ACTION_DROP end
	end, function(ctx)
		local H, p = HARNESS.press, Isaac.GetPlayer(0)
		if cond(p) then
			H.oneShot = nil
			P("INFO", ctx.name, label, "after", ctx.t, "updates by", ctx.already and "nothing (already so)" or ctx.fell and fallbackName or "drop press",
				"|", slots(p), "type", p:GetPlayerType())
			return true
		end
		if ctx.t == 60 then
			H.oneShot, ctx.fell = nil, true
			local ok, err = pcall(fallback, p)
			P("INFO", ctx.name, label, "drop press changed nothing in 60 updates,", fallbackName, ok and "called" or ("failed: " .. tostring(err)))
		elseif not ctx.fell and not H.oneShot and ctx.t % 10 == 0 then H.oneShot = ButtonAction.ACTION_DROP end
		return false, slots(p) .. " type " .. p:GetPlayerType()
	end)
end
local function swapActives(p) p:SwapActiveItems() end
-- Item `id` into `slot` by a drop press, SwapActiveItems as the fallback.
local function toSlot(label, slot, id) return dropPress(label, function(p) return p:GetActiveItem(slot) == id end, "SwapActiveItems", swapActives) end

-- Every GetPlayer index's type and entity, for a press whose effect is unobserved.
local function lineupText()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		t[#t + 1] = i .. ":t" .. p:GetPlayerType() .. "/" .. GetPtrHash(p)
	end
	return table.concat(t, " ")
end

-- Recon: one real drop press, by player 0 or with who.any by any entity, then up to 30 updates for a type or entity to change; logs what
-- changed, or that nothing did. No fallback: what the press does is the question (Tainted Forgotten's: plan open point 5).
local function dropOnce(label, who)
	return act(label, function()
		local H = HARNESS.press
		H.oneShot, H.pressHash = ButtonAction.ACTION_DROP, nil
		if who and who.any then H.pressHash = false end
		return lineupText()
	end, function(ctx, before)
		local now = lineupText()
		if now == before and ctx.t < 30 then return false, "nothing changed" end
		local polled = HARNESS.press.oneShot == nil -- the one-shot clears on the first triggered poll it answers
		endPress()
		P("INFO", ctx.name, label, "drop press:", now == before and "nothing changed in 30 updates" or ("changed after " .. ctx.t .. " updates"), "|",
			before, "->", now, "| polled", polled)
		return true
	end)
end

local function deadFirst() return Isaac.GetPlayer(0):GetPlayerType() == DEAD_T_LAZ end

-- Player 0 swaps its two Esau Jr. copies (primary and Schoolbag) by a real drop press, SwapActiveItems as the fallback. Both slots hold
-- c703, so marked charges (primary 0, secondary 1) show the swap.
local function swapCopies()
	local function marked(p) return p:GetActiveCharge(PRIMARY) == 1 and p:GetActiveCharge(SECONDARY) == 0 end
	local drop = dropPress("swap the Esau Jr. copies", marked, "SwapActiveItems", swapActives)
	return function(ctx)
		if not ctx.t then
			local p = Isaac.GetPlayer(0)
			if p:GetActiveItem(PRIMARY) ~= ESAU_JR or p:GetActiveItem(SECONDARY) ~= ESAU_JR then error("Esau Jr. not in both slots: " .. slots(p)) end
			p:SetActiveCharge(0, PRIMARY)
			p:SetActiveCharge(1, SECONDARY)
		end
		return drop(ctx)
	end
end

return {
	onUse = onUse, onPlayerUpdate = onPlayerUpdate, onInput = onInput, onVetoPre = onVetoPre, onClickerUse = onClickerUse,
	onVetoUpdate = onVetoUpdate, endPress = endPress, teardown = teardown, press = press, flip = flip, esauJr = esauJr, soulJE = soulJE,
	clicker = clicker, cancelledClicker = cancelledClicker, clickerWithin60 = clickerWithin60, birthrightFlip = birthrightFlip, dropPress = dropPress,
	toSlot = toSlot, dropOnce = dropOnce, deadFirst = deadFirst, swapCopies = swapCopies,
}
