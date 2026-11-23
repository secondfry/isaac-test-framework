-- Recon, nothing asserted: Lazarus dies until his one revive source (plan S5b) has revived him once; each test ends at its source's revive; a source that gives no revive reaches game over, whose death certificate waits for Space (session 3a); the last test restarts from that certificate; what session 2 saw: lua-api-notes.md "Revives".
local P = include("scripts.log").P
local engine = include("scripts.game")
local owned, cards = engine.owned, engine.cards
local console = include("scripts.console")
local fresh, give, startNew = console.fresh, console.give, console.startNew
local expectStart = include("scripts.runner").expectStart
local addCard = include("scripts.steps").addCard
local record = include("scripts.record")
local snap, try = record.snap, record.try
local fixtures = include("scripts.fixtures")
local fixture, freshRun = fixtures.fixture, fixtures.freshRun
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local ANKH, JUDAS_SHADOW, LAZARUS_RAGS, SOUL_LAZARUS, LAZARUS, ISAAC = ids.ANKH, ids.JUDAS_SHADOW, ids.LAZARUS_RAGS, ids.SOUL_LAZARUS, ids.LAZARUS,
	ids.ISAAC

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

-- A fresh Lazarus after `step`, which gives him `what`.
local function holding(what, step) return fixture("Lazarus holding " .. what, { fresh(LAZARUS), step }, LAZARUS) end
local function holdsItem(id) return function(p) return owned(p, id) > 0 end end
-- Each source on a fresh Lazarus: its test name's words, the fixture, and whether player 0 still holds it.
local SOURCES = {
	{ "Soul of Lazarus", holding("Soul of Lazarus", addCard(SOUL_LAZARUS)), function(p) return cards(p, SOUL_LAZARUS) > 0 end },
	{ "his own revive only", freshRun(LAZARUS), function(p) return p:GetPlayerType() == LAZARUS end },
	{ "Lazarus' Rags", holding("Lazarus' Rags", give(LAZARUS_RAGS)), holdsItem(LAZARUS_RAGS) },
	{ "Ankh", holding("Ankh", give(ANKH)), holdsItem(ANKH) },
	{ "Judas' Shadow", holding("Judas' Shadow", give(JUDAS_SHADOW)), holdsItem(JUDAS_SHADOW) },
}

local tests = {}
for _, s in ipairs(SOURCES) do
	tests[#tests + 1] = snapshotTest("Lazarus with " .. s[1] .. " dies until it revives him", { "revive", "opt-in" }, s[2],
		{ { "die until revived", dieUntilRevived(s[3]), nil, WATCH + 1 } }, { strict = true, limit = 300 + MAX_DEATHS * (WATCH + 1) })
end

-- Restart from the death certificate (user decision 2026-11-23: a Missing Poster test is built only if a console restart works there).
-- shortcut: whether updates and renders run on the certificate is unobserved (session 3a: 58 updates from Kill() to the Space-started game, as if updates stop there), and so are 2 renders per update; the CERT lines log both counts
local DEAD_UPDATES, NEW_GAME_WAIT = 120, 600 -- dead past session 3b's 57-update revive window before the restart; updates or renders it then waits for a new game

-- One CERT line: how long player 0 has been dead in updates and renders, the frame and IsDead.
local function certLine(ctx, at)
	local c, p = ctx.cert, Isaac.GetPlayer(0)
	P("INFO", ctx.name, "CERT at", at, "dead for", c.u, "updates,", c.r, "renders, frame", game:GetFrameCount(), "IsDead", p and try(function() return p:IsDead() end))
end

-- On each update and render while dead: the restart once dead DEAD_UPDATES updates or twice as many renders, then the press-Space prompt.
local function certificateTick(ctx)
	local c = ctx.cert
	if not c.sent and (c.u >= DEAD_UPDATES or c.r >= 2 * DEAD_UPDATES) then
		c.sent = { u = c.u, r = c.r }
		certLine(ctx, "restart")
		startNew("restart " .. ISAAC)
	elseif c.sent and not c.space and (c.u - c.sent.u >= NEW_GAME_WAIT or c.r - c.sent.r >= NEW_GAME_WAIT) then
		c.space = true
		P("INFO", ctx.name, "restart from the certificate gave no new game: press Space")
	end
end

-- Kill() player 0, who has no revive, then restart from his certificate; ends at the new game, a Space-started one included.
local function restartFromCertificate(ctx)
	local S, c = HARNESS.session, ctx.cert
	if not c then
		local p = Isaac.GetPlayer(0)
		ctx.cert = { u = 0, r = 0, gen = S.gen }
		expectStart("new") -- a Space-started game is this test's too
		P("INFO", ctx.name, "CERT Kill() on type", p:GetPlayerType(), "frame", game:GetFrameCount(), "| Kill()", try(function() p:Kill() end))
		return "again"
	end
	if S.gen ~= c.gen then
		if game:GetNumPlayers() == 0 then return "again" end -- no player 0 yet, as console.newGame
		ctx.cert = nil
		local since = c.sent and ((c.u - c.sent.u) .. " updates, " .. (c.r - c.sent.r) .. " renders") or ""
		local how = not c.sent and ("new game before the restart was sent, dead for " .. c.u .. " updates, " .. c.r .. " renders")
			or c.space and ("new game after the press-Space prompt, " .. since .. " after the restart")
			or ("restart from the certificate: new game after " .. since)
		return P("INFO", ctx.name, how, "| start seed", game:GetSeeds():GetStartSeedString(), "type", Isaac.GetPlayer(0):GetPlayerType(), "frame", game:GetFrameCount())
	end
	c.u = c.u + 1
	if c.u % 30 == 0 then certLine(ctx, "update") end
	certificateTick(ctx)
	return "again"
end

-- Counts renders while dead, as updates may stop on the certificate; the prompt is drawn only if renders run.
local function certificateRender(ctx)
	local c = ctx.cert
	if not c or HARNESS.session.gen ~= c.gen then return end
	c.r = c.r + 1
	if c.r % 60 == 0 then certLine(ctx, "render") end
	if c.space then Isaac.RenderText("HARNESS: press Space", 60, 58, 1, 1, 0, 1) end
	certificateTick(ctx)
end

local certificate = snapshotTest("restart from the death certificate", { "revive", "opt-in" }, freshRun(ISAAC),
	{ { "die and restart from the certificate", restartFromCertificate } })
certificate.onRender = certificateRender
tests[#tests + 1] = certificate

return { name = "revive", tests = tests }
