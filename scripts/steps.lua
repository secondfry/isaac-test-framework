-- Steps that change the run by script: types, items and cards given by the API, a step off a pedestal, and guards around a step.
local P = include("scripts.log").P
local act = include("scripts.wait").act
local engine = include("scripts.game")
local owned, cards, ofType = engine.owned, engine.cards, engine.ofType
local ids = include("scripts.ids")
local ESAU_JR, ESAU, PRIMARY = ids.ESAU_JR, ids.ESAU, ids.PRIMARY

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

local function holdsTrinket(p, id) return p:GetTrinket(0) == id or p:GetTrinket(1) == id end
local function addTrinket(id)
	return act("AddTrinket " .. id, function() Isaac.GetPlayer(0):AddTrinket(id) end,
		function() return holdsTrinket(Isaac.GetPlayer(0), id), "trinket " .. id .. " not held (locked trinket?)" end)
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

return {
	addTo = addTo, giveEsau = giveEsau, giveType = giveType, changeType = changeType, addCard = addCard, addTrinket = addTrinket, holdsTrinket = holdsTrinket, info = info, stepOff = stepOff,
	onlyIf = onlyIf, holdsJr = holdsJr,
}
