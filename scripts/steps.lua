-- Steps that change the run by script: types, items and cards given by the API, a step off a pedestal, and guards around a step.
local P = include("scripts.log").P
local action = include("scripts.wait").action
local engine = include("scripts.game")
local owned, cards, playerOfType = engine.owned, engine.cards, engine.playerOfType
local ids = include("scripts.ids")
local ESAU_JR, PRIMARY = ids.ESAU_JR, ids.PRIMARY

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

-- Not a press, so only the new-character half of the swap rule applies: there is no item to spend.
local function changeType(t)
	return action("ChangePlayerType " .. t, function() Isaac.GetPlayer(0):ChangePlayerType(t) end,
		function() return Isaac.GetPlayer(0):GetPlayerType() == t, "player 0 is type " .. Isaac.GetPlayer(0):GetPlayerType() end)
end

local function addCard(card)
	return action("AddCard " .. card, function()
		local p = Isaac.GetPlayer(0)
		local n = cards(p, card)
		p:AddCard(card)
		return n
	end, function(_, n) return cards(Isaac.GetPlayer(0), card) == n + 1, "card count did not rise by 1 (locked card?)" end)
end

local function obsInfo(what, f) return function(ctx) P("INFO", ctx.name, what, f(Isaac.GetPlayer(0))) end end

-- AddCollectible on the first player of type `t`.
local function giveType(id, t)
	return action("AddCollectible c" .. id .. " on type " .. t, function()
		local p = playerOfType(t)
		if not p then error("no player of type " .. t) end
		local n = owned(p, id)
		p:AddCollectible(id)
		return n
	end, function(_, n)
		local p = playerOfType(t)
		return p and owned(p, id) == n + 1, "owned copies did not rise by 1"
	end)
end

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
	giveEsau = giveEsau, changeType = changeType, addCard = addCard, obsInfo = obsInfo, giveType = giveType, stepOff = stepOff,
	onlyIf = onlyIf, holdsJr = holdsJr,
}
