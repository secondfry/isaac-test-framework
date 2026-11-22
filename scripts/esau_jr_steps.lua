-- Esau Jr. step lists: presses with verdicts, re-gives, losing the copy, Clicker on the presser and the returns that follow.
local P = include("scripts.log").P
local act = include("scripts.wait").act
local engine = include("scripts.game")
local seedOf, bySeed, owned, pedestals = engine.seedOf, engine.bySeed, engine.owned, engine.pedestals
local give = include("scripts.console").give
local presses = include("scripts.press")
local press, flip, esauJr = presses.press, presses.flip, presses.esauJr
local steps = include("scripts.steps")
local giveEsau, holdsJr = steps.giveEsau, steps.holdsJr
local verdict = include("scripts.record").verdict
local pre = include("scripts.assert").pre
local ids = include("scripts.ids")
local ESAU_JR, CLICKER, D6, PRIMARY = ids.ESAU_JR, ids.CLICKER, ids.D6, ids.PRIMARY

local function regiveEsauJr()
	local g = give(ESAU_JR)
	return function(ctx)
		if not ctx.t and holdsJr() then return P("INFO", ctx.name, "Esau Jr. still in the active slot, no re-give") end
		return g(ctx)
	end
end

local function jrFirst() return { { "Esau Jr.", esauJr("Esau Jr.") }, { "give c5", give(5) } } end
local function jrAgain() return { { "re-give c703", regiveEsauJr() }, { "Esau Jr. again", esauJr("Esau Jr. again") } } end

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
		P("INFO", ctx.name, label, "A seed", ctx.originalSeed, "present", bySeed(ctx.originalSeed) ~= nil)
		if ctx.formSeed then
			P("INFO", ctx.name, label, "B seed", ctx.formSeed, "present", bySeed(ctx.formSeed) ~= nil)
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
			pre(Isaac.GetPlayer(0):GetActiveItem(PRIMARY) == ESAU_JR, "Esau Jr. before giving D6")
		end },
		{ "give D6", give(D6) },
		{ "check D6 in primary", function(ctx)
			local p = Isaac.GetPlayer(0)
			if p:GetActiveItem(PRIMARY) ~= D6 then error("D6 did not replace Esau Jr.") end
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

local useClickerEffect = act("UseActiveItem Clicker", function()
	local p = Isaac.GetPlayer(0)
	pre(p:GetActiveItem(PRIMARY) == ESAU_JR, "Esau Jr. in primary before UseActiveItem")
	local before = { seed = seedOf(p), who = p:GetPlayerType() }
	p:UseActiveItem(CLICKER, 0)
	return before
end, function(ctx, before)
	local p = bySeed(before.seed)
	local who = p and p:GetPlayerType()
	local primary = p and p:GetActiveItem(PRIMARY)
	P("INFO", ctx.name, "UseActiveItem Clicker type", before.who, "->", who, "changed", who ~= nil and who ~= before.who,
		"primary", ESAU_JR, "->", primary)
	if not who or who == before.who then error("UseActiveItem did not verify a type change on the presser") end
	if primary ~= ESAU_JR then error("Esau Jr. did not stay in primary after UseActiveItem") end
	return true
end)

local function jr(label, who) return verdict(label, press(label, ESAU_JR, PRIMARY, nil, nil, who), who and who.index, true) end
local function jrPair(label, who) return { label, jr(label, who) } end
local function flipV(label) return verdict(label, flip(label)) end

-- Press, press back, press to the form again, the form loses Esau Jr. (D6) and gets it back, two presses. `first`: pairs
-- before the presses; `lose`: pairs for the loss (default: player 0's D6 and re-give).
local function charPresses(who, first, lose)
	return { first or {}, jrPair("Esau Jr. #1", who), jrPair("Esau Jr. #2", who), jrPair("Esau Jr. #3", who),
		lose or replaceEsauJr(), jrPair("Esau Jr. #4", who), jrPair("Esau Jr. #5", who) }
end
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

return {
	regiveEsauJr = regiveEsauJr, jrFirst = jrFirst, jrAgain = jrAgain, jrTwice = jrTwice, giveClicker = giveClicker,
	rememberOriginal = rememberOriginal, rememberForm = rememberForm, controlPresses = controlPresses, loseEsauJr = loseEsauJr,
	replaceEsauJr = replaceEsauJr, useClickerEffect = useClickerEffect, jrPair = jrPair, flipV = flipV, charPresses = charPresses, esauLoses = esauLoses,
}
