-- Recon, nothing asserted: Lazarus dies until his one revive source (plan S5b) has revived him once; each test ends at its source's revive; a source that gives no revive reaches game over, whose death certificate waits for Space (session 3a); what session 2 saw: lua-api-notes.md "Revives".
local P = include("scripts.log").P
local engine = include("scripts.game")
local owned, cards = engine.owned, engine.cards
local console = include("scripts.console")
local fresh, give = console.fresh, console.give
local addCard = include("scripts.steps").addCard
local record = include("scripts.record")
local snap, try = record.snap, record.try
local fixtures = include("scripts.fixtures")
local fixture, freshRun = fixtures.fixture, fixtures.freshRun
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local ANKH, JUDAS_SHADOW, LAZARUS_RAGS, SOUL_LAZARUS, LAZARUS = ids.ANKH, ids.JUDAS_SHADOW, ids.LAZARUS_RAGS, ids.SOUL_LAZARUS, ids.LAZARUS

local game = Game()
local MAX_DEATHS = 2 -- the innate revive plus one source (session 3b)
local WATCH = 240 -- updates watched after each Kill(), 8 s: session 2's revives were alive by update 58

-- The revive sources `p` holds, as text.
local function sources(p)
	if not p then return "no player 0" end
	local t = {}
	for _, id in ipairs({ ANKH, JUDAS_SHADOW, LAZARUS_RAGS }) do t[#t + 1] = "c" .. id .. " " .. owned(p, id) end
	t[#t + 1] = "card " .. SOUL_LAZARUS .. " " .. cards(p, SOUL_LAZARUS)
	return table.concat(t, " ")
end

-- Player 0 as one line, each read that may throw on a dying player pcall'd.
local function state(p)
	if not p then return "no player 0" end
	return "type " .. p:GetPlayerType() .. " dead " .. try(function() return p:IsDead() end) .. " hearts " .. try(function() return p:GetHearts() end)
		.. " players " .. game:GetNumPlayers() .. " hash " .. GetPtrHash(p) .. " room " .. game:GetLevel():GetCurrentRoomIndex() .. " | " .. sources(p)
end

-- Kill() player 0 while `holds(p)` (the test's source unused), each death watched WATCH updates logging each change; ends once it is used.
local function dieUntilRevived(holds)
	return function(ctx)
		local p = Isaac.GetPlayer(0)
		if not ctx.t then
			if not (p and holds(p)) then return P("INFO", ctx.name, "REVIVE ends: source used by death", ctx.deaths or 0, "|", sources(p)) end
			if (ctx.deaths or 0) >= MAX_DEATHS then return P("INFO", ctx.name, "REVIVE ends:", MAX_DEATHS, "deaths, source unused |", sources(p)) end
			ctx.deaths, ctx.t, ctx.last, ctx.hash, ctx.dead, ctx.back = (ctx.deaths or 0) + 1, 0, nil, GetPtrHash(p), false, nil
			P("INFO", ctx.name, "REVIVE death", ctx.deaths, "Kill() on type", p:GetPlayerType(), "frame", game:GetFrameCount(), "|", sources(p), "| Kill()",
				try(function() p:Kill() end))
			return "again"
		end
		ctx.t = ctx.t + 1
		local now, dead = state(p), p and try(function() return p:IsDead() end)
		if now ~= ctx.last then
			ctx.last = now
			P("INFO", ctx.name, "REVIVE death", ctx.deaths, "update", ctx.t, now)
		end
		if dead == "true" then ctx.dead = true
		elseif ctx.dead and not ctx.back then
			ctx.back = ctx.t
			P("INFO", ctx.name, "REVIVE death", ctx.deaths, "alive again after", ctx.t, "updates")
		end
		if ctx.t < WATCH then return "again" end
		ctx.t = nil
		snap(ctx, "death " .. ctx.deaths .. " / type", p and p:GetPlayerType() or "no player 0")
		snap(ctx, "death " .. ctx.deaths .. " / alive after " .. WATCH .. " updates", tostring(dead == "false"))
		snap(ctx, "death " .. ctx.deaths .. " / hash kept", tostring(p ~= nil and GetPtrHash(p) == ctx.hash))
		snap(ctx, "death " .. ctx.deaths .. " / sources", sources(p))
		if dead ~= "false" then return P("INFO", ctx.name, "REVIVE ends: death", ctx.deaths, "left no live player 0 after", WATCH, "updates") end
		return "again"
	end
end

-- Each source on a fresh Lazarus: its test name's words, the fixture, and whether player 0 still holds it.
local function holding(what, step) return fixture("Lazarus holding " .. what, { fresh(LAZARUS), step }, LAZARUS) end
local function item(id) return function(p) return owned(p, id) > 0 end end
local SOURCES = {
	{ "Soul of Lazarus", holding("Soul of Lazarus", addCard(SOUL_LAZARUS)), function(p) return cards(p, SOUL_LAZARUS) > 0 end },
	{ "his own revive only", freshRun(LAZARUS), function(p) return p:GetPlayerType() == LAZARUS end },
	{ "Lazarus' Rags", holding("Lazarus' Rags", give(LAZARUS_RAGS)), item(LAZARUS_RAGS) },
	{ "Ankh", holding("Ankh", give(ANKH)), item(ANKH) },
	{ "Judas' Shadow", holding("Judas' Shadow", give(JUDAS_SHADOW)), item(JUDAS_SHADOW) },
}

local tests = {}
for _, s in ipairs(SOURCES) do
	tests[#tests + 1] = snapshotTest("Lazarus with " .. s[1] .. " dies until it revives him", { "revive", "opt-in" }, s[2],
		{ { "die until revived", dieUntilRevived(s[3]), nil, WATCH + 1 } }, { strict = true, limit = 300 + MAX_DEATHS * (WATCH + 1) })
end

return { name = "revive", tests = tests }
