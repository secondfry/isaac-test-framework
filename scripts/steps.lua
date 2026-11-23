-- Steps that change the run by script: types, items and cards given by the API, a step off a pedestal, and guards around a step.
local P = include("scripts.log").P
local wait = include("scripts.wait")
local act, condition = wait.act, wait.condition
local engine = include("scripts.game")
local owned, cards, ofType, withParent = engine.owned, engine.cards, engine.ofType, engine.withParent
local ids = include("scripts.ids")
local ESAU_JR, ESAU, KEEPER, PRIMARY = ids.ESAU_JR, ids.ESAU, ids.KEEPER, ids.PRIMARY

local game = Game()

-- AddCollectible c`id` on the player `find()` returns; `missing` is the error when it returns none.
local function addTo(label, find, id, missing)
	return act(label, function()
		local p = find()
		if not p then error(missing) end
		local n = owned(p, id)
		p:AddCollectible(id)
		return n
	end, function(_, n)
		local p = find()
		return p and owned(p, id) == n + 1, "owned copies did not rise by 1"
	end)
end

-- AddCollectible on Esau, or on GetPlayer(`index`) when given (a pressed index may hold an Esau Jr. form, not Esau).
local function giveEsau(id, index)
	return addTo("Esau AddCollectible c" .. id, function() return index and Isaac.GetPlayer(index) or ofType(ESAU) end, id,
		"no " .. (index and ("player at index " .. index) or "Esau (type 20)") .. " to give c" .. id)
end

-- AddCollectible on the first player of type `t`.
local function giveType(id, t) return addTo("AddCollectible c" .. id .. " on type " .. t, function() return ofType(t) end, id, "no player of type " .. t) end

-- Not a press, so only the new-character half of the swap rule applies: there is no item to spend.
local function changeType(t)
	return act("ChangePlayerType " .. t, function() Isaac.GetPlayer(0):ChangePlayerType(t) end,
		function() return Isaac.GetPlayer(0):GetPlayerType() == t, "player 0 is type " .. Isaac.GetPlayer(0):GetPlayerType() end)
end

local function addCard(card)
	return act("AddCard " .. card, function()
		local p = Isaac.GetPlayer(0)
		local n = cards(p, card)
		p:AddCard(card)
		return n
	end, function(_, n) return cards(Isaac.GetPlayer(0), card) == n + 1, "card count did not rise by 1 (locked card?)" end)
end

local function addTrinket(id)
	return act("AddTrinket " .. id, function() Isaac.GetPlayer(0):AddTrinket(id) end,
		function() return Isaac.GetPlayer(0):HasTrinket(id), "trinket " .. id .. " not held (locked trinket?)" end)
end

-- UseCard on player 0, the card not held (works for Soul of Jacob and Esau, docs/engine-facts.md), then up to 30 updates for the player
-- count to change; logs the count either way, as what other cards add is unobserved.
local function useCard(card)
	return act("UseCard " .. card, function(ctx)
		local n = game:GetNumPlayers()
		Isaac.GetPlayer(0):UseCard(card, 0)
		P("INFO", ctx.name, "UseCard", card, "players", n, "->", game:GetNumPlayers(), "in the call")
		return n
	end, function(ctx, n)
		local now = game:GetNumPlayers()
		if now == n and ctx.t < 30 then return false, "players still " .. n end
		P("INFO", ctx.name, "UseCard", card, "players", n, "->", now, "after", ctx.t, "updates")
		return true
	end)
end

-- An INFO line of `what`: f(player 0).
local function info(what, f) return function(ctx) P("INFO", ctx.name, what, f(Isaac.GetPlayer(0))) end end

-- Off the c45 pedestal, so the character a press brings cannot touch it.
local function stepOff(ctx)
	local p = Isaac.GetPlayer(0)
	p.Position, p.Velocity = p.Position + Vector(0, 80), Vector(0, 0)
end

local function onlyIf(what, cond, step)
	return function(ctx)
		if not ctx.t and not ctx.held and not cond() then
			table.insert(ctx.notes, "skipped: " .. what)
			return P("INFO", ctx.name, "skipped:", what)
		end
		return step(ctx)
	end
end
local function holdsJr() return Isaac.GetPlayer(0):GetActiveItem(PRIMARY) == ESAU_JR end

-- Waits for Strawman's Keeper to join after Strawman is given.
local keeperJoins = condition("Strawman Keeper", function() return withParent(KEEPER) ~= nil end)

return {
	keeperJoins = keeperJoins, giveEsau = giveEsau, giveType = giveType, changeType = changeType, addCard = addCard, addTrinket = addTrinket, useCard = useCard, info = info, stepOff = stepOff,
	onlyIf = onlyIf, holdsJr = holdsJr,
}
