-- Lazarus with one revive source dies until game over (plan S5b), one test per source: which revive the engine takes, into which type.
-- Session 2 (vanilla, every source on one Lazarus, deaths by Kill(), which returns nil): card 89 first (stays 8), the innate revive
-- (8 -> 11), Lazarus' Rags (stays 11), Ankh (11 -> 4), Judas' Shadow (4 -> 12); the sixth death, Missing Poster held, gave no revive and the
-- engine started a new game (continued false); each revive alive by update 58, same GetPtrHash. Each source alone is unobserved, so each
-- death logs what changed and nothing is asserted. Opt-in (tags revive): each test ends at its game over, the next restarts from there.
local P = include("scripts.log").P
local engine = include("scripts.game")
local owned, cards = engine.owned, engine.cards
local console = include("scripts.console")
local fresh, give = console.fresh, console.give
local expectStart = include("scripts.runner").expectStart
local steps = include("scripts.steps")
local addCard, addTrinket, holdsTrinket = steps.addCard, steps.addTrinket, steps.holdsTrinket
local record = include("scripts.record")
local snap, try = record.snap, record.try
local fixtures = include("scripts.fixtures")
local fixture, freshRun = fixtures.fixture, fixtures.freshRun
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local ANKH, JUDAS_SHADOW, LAZARUS_RAGS, MISSING_POSTER, SOUL_LAZARUS, LAZARUS = ids.ANKH, ids.JUDAS_SHADOW, ids.LAZARUS_RAGS,
	ids.MISSING_POSTER, ids.SOUL_LAZARUS, ids.LAZARUS

local game = Game()
local MAX_DEATHS, WATCH = 4, 240 -- updates watched after each Kill(), 8 s: session 2's revives were alive by update 58

-- The revive sources `p` holds, as text.
local function sources(p)
	if not p then return "no player 0" end
	local t = {}
	for _, id in ipairs({ ANKH, JUDAS_SHADOW, LAZARUS_RAGS }) do t[#t + 1] = "c" .. id .. " " .. owned(p, id) end
	t[#t + 1] = "trinket " .. MISSING_POSTER .. " " .. tostring(holdsTrinket(p, MISSING_POSTER))
	t[#t + 1] = "card " .. SOUL_LAZARUS .. " " .. cards(p, SOUL_LAZARUS)
	return table.concat(t, " ")
end

-- Player 0 as one line, each read that may throw on a dying player pcall'd.
local function state(p)
	if not p then return "no player 0" end
	return "type " .. p:GetPlayerType() .. " dead " .. try(function() return p:IsDead() end) .. " hearts " .. try(function() return p:GetHearts() end)
		.. " players " .. game:GetNumPlayers() .. " hash " .. GetPtrHash(p) .. " room " .. game:GetLevel():GetCurrentRoomIndex() .. " | " .. sources(p)
end

-- Kill() player 0 with a game over's new game expected, then watch WATCH updates, logging each change; a new game ends the step, a
-- revive alive after the watch kills again, up to MAX_DEATHS deaths.
local function dieUntilGameOver(ctx)
	local S = HARNESS.session
	if not ctx.t then
		local p = Isaac.GetPlayer(0)
		local held = sources(p)
		if (ctx.deaths or 0) >= MAX_DEATHS then return P("INFO", ctx.name, "REVIVE ends:", MAX_DEATHS, "deaths |", held) end
		ctx.deaths, ctx.t, ctx.last, ctx.gen = (ctx.deaths or 0) + 1, 0, nil, S.gen
		expectStart("new")
		P("INFO", ctx.name, "REVIVE death", ctx.deaths, "Kill() on type", p:GetPlayerType(), "frame", game:GetFrameCount(), "|", held, "| Kill()",
			try(function() p:Kill() end))
	end
	ctx.t = ctx.t + 1
	if S.gen ~= ctx.gen then
		local p = Isaac.GetPlayer(0)
		P("INFO", ctx.name, "REVIVE ends: death", ctx.deaths, "game over, new game type", p and p:GetPlayerType() or "none", "start seed",
			game:GetSeeds():GetStartSeedString())
		snap(ctx, "death " .. ctx.deaths .. " / game over", "true")
		ctx.t = nil
		return
	end
	local p = Isaac.GetPlayer(0)
	local now = state(p)
	if now ~= ctx.last then
		ctx.last = now
		P("INFO", ctx.name, "REVIVE death", ctx.deaths, "update", ctx.t, now)
	end
	if ctx.t < WATCH then return "again" end
	ctx.t = nil
	expectStart(nil)
	local alive = p ~= nil and try(function() return p:IsDead() end) == "false"
	snap(ctx, "death " .. ctx.deaths .. " / type", p and p:GetPlayerType() or "no player 0")
	snap(ctx, "death " .. ctx.deaths .. " / alive after " .. WATCH .. " updates", tostring(alive))
	snap(ctx, "death " .. ctx.deaths .. " / sources", sources(p))
	if not alive then return P("INFO", ctx.name, "REVIVE ends: death", ctx.deaths, "left no live player 0") end
	return "again"
end

-- Each source on a fresh Lazarus: its test name's words and the fixture.
local function holding(what, step) return fixture("Lazarus holding " .. what, { fresh(LAZARUS), step }, LAZARUS) end
local SOURCES = {
	{ "Soul of Lazarus", holding("Soul of Lazarus", addCard(SOUL_LAZARUS)) },
	{ "his own revive only", freshRun(LAZARUS) },
	{ "Lazarus' Rags", holding("Lazarus' Rags", give(LAZARUS_RAGS)) },
	{ "Ankh", holding("Ankh", give(ANKH)) },
	{ "Judas' Shadow", holding("Judas' Shadow", give(JUDAS_SHADOW)) },
	{ "Missing Poster", holding("Missing Poster", addTrinket(MISSING_POSTER)) },
}

local tests = {}
for _, s in ipairs(SOURCES) do
	tests[#tests + 1] = snapshotTest("Lazarus with " .. s[1] .. " dies until game over", { "revive", "opt-in" }, s[2],
		{ { "die until game over", dieUntilGameOver, nil, WATCH + 1 } }, { strict = true, limit = 300 + MAX_DEATHS * WATCH })
end

return { name = "revive", tests = tests }
