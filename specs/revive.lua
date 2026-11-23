-- Recon, nothing asserted: Lazarus dies until his one revive source (plan S5b) has revived him once; each test ends at its source's revive; a source that gives no revive reaches game over, whose death certificate stops updates (session 3c) and waits for Space (session 3a); then one test restarts from that certificate, and the Missing Poster test restarts from it on a game over; what session 2 saw: lua-api-notes.md "Revives".
local P = include("scripts.log").P
local engine = include("scripts.game")
local owned, cards = engine.owned, engine.cards
local console = include("scripts.console")
local fresh, give, startNew = console.fresh, console.give, console.startNew
local expectStart = include("scripts.runner").expectStart
local steps = include("scripts.steps")
local addCard, addTrinket = steps.addCard, steps.addTrinket
local record = include("scripts.record")
local snap, try = record.snap, record.try
local fixtures = include("scripts.fixtures")
local fixture, freshRun = fixtures.fixture, fixtures.freshRun
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local ANKH, JUDAS_SHADOW, LAZARUS_RAGS, MISSING_POSTER, SOUL_LAZARUS, LAZARUS, ISAAC = ids.ANKH, ids.JUDAS_SHADOW, ids.LAZARUS_RAGS,
	ids.MISSING_POSTER, ids.SOUL_LAZARUS, ids.LAZARUS, ids.ISAAC

local game = Game()
local MAX_DEATHS = 2 -- the innate revive plus one source (session 3b)
local WATCH = 240 -- updates watched after each Kill(), 8 s: session 2's revives were alive by update 58

local function holdsPoster(p) return p:HasTrinket(MISSING_POSTER) end

-- The revive sources `p` holds, as text.
local function sources(p)
	if not p then return "no player 0" end
	local t = {}
	for _, id in ipairs({ ANKH, JUDAS_SHADOW, LAZARUS_RAGS }) do t[#t + 1] = "c" .. id .. " " .. owned(p, id) end
	t[#t + 1] = "card " .. SOUL_LAZARUS .. " " .. cards(p, SOUL_LAZARUS)
	t[#t + 1] = "trinket " .. MISSING_POSTER .. " " .. tostring(holdsPoster(p))
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

-- One source's test: `f` its fixture, `die` its step.
local function sourceTest(what, f, die)
	return snapshotTest("Lazarus with " .. what .. " dies until it revives him", { "revive", "opt-in" }, f,
		{ { "die until revived", die, nil, WATCH + 1 } }, { strict = true, limit = 300 + MAX_DEATHS * (WATCH + 1) })
end

local tests = {}
for _, s in ipairs(SOURCES) do tests[#tests + 1] = sourceTest(s[1], s[2], dieUntilRevived(s[3])) end

-- Restart from the death certificate (user decision 2026-11-23: a Missing Poster test is built only if a console restart works there).
-- shortcut: updates stop on the certificate at 57 dead and renders run on (session 3c), but 2 renders per update there is unobserved (no updates); the CERT lines log both counts
local DEAD_UPDATES, NEW_GAME_WAIT = 120, 600 -- dead past session 3b's 57-update revive window before the restart; updates or renders it then waits for a new game

-- One CERT line: how long player 0 has been dead in updates and renders, the frame and IsDead.
local function certLine(ctx, at)
	local c, p = ctx.cert, Isaac.GetPlayer(0)
	P("INFO", ctx.name, "CERT at", at, "dead for", c.u, "updates,", c.r, "renders, frame", game:GetFrameCount(), "IsDead", p and try(function() return p:IsDead() end))
end

-- On each update and render while dead: the restart once dead DEAD_UPDATES updates or twice as many renders (c.onSend first), then the press-Space prompt.
local function certificateTick(ctx)
	local c = ctx.cert
	if not c.sent and (c.u >= DEAD_UPDATES or c.r >= 2 * DEAD_UPDATES) then
		c.sent = { u = c.u, r = c.r }
		certLine(ctx, "restart")
		if c.onSend then c.onSend(ctx) end
		startNew("restart " .. ISAAC)
	elseif c.sent and not c.space and (c.u - c.sent.u >= NEW_GAME_WAIT or c.r - c.sent.r >= NEW_GAME_WAIT) then
		c.space = true
		P("INFO", ctx.name, "restart from the certificate gave no new game: press Space")
	end
end

-- Watches a death that may reach the certificate: its counts from now, and a new game is the test's own, a Space-started one included.
local function certificateArm(ctx, onSend)
	ctx.cert = { u = 0, r = 0, gen = HARNESS.session.gen, onSend = onSend }
	expectStart("new")
end

-- Once the certificate's new game has come: logs how and drops ctx.cert; "again" while it has no player 0 yet, as console.newGame.
local function certificateEnds(ctx)
	if game:GetNumPlayers() == 0 then return "again" end
	local c = ctx.cert
	ctx.cert = nil
	local since = c.sent and ((c.u - c.sent.u) .. " updates, " .. (c.r - c.sent.r) .. " renders") or ""
	local how = not c.sent and ("new game before the restart was sent, dead for " .. c.u .. " updates, " .. c.r .. " renders")
		or c.space and ("new game after the press-Space prompt, " .. since .. " after the restart")
		or ("restart from the certificate: new game after " .. since)
	return P("INFO", ctx.name, how, "| start seed", game:GetSeeds():GetStartSeedString(), "type", Isaac.GetPlayer(0):GetPlayerType(), "frame", game:GetFrameCount())
end

-- Kill() player 0, who has no revive, then restart from his certificate; ends at the new game, a Space-started one included.
local function restartFromCertificate(ctx)
	local c = ctx.cert
	if not c then
		local p = Isaac.GetPlayer(0)
		certificateArm(ctx)
		P("INFO", ctx.name, "CERT Kill() on type", p:GetPlayerType(), "frame", game:GetFrameCount(), "| Kill()", try(function() p:Kill() end))
		return "again"
	end
	if HARNESS.session.gen ~= c.gen then return certificateEnds(ctx) end
	c.u = c.u + 1
	if c.u % 30 == 0 then certLine(ctx, "update") end
	certificateTick(ctx)
	return "again"
end

-- Counts renders while dead, as updates stop on the certificate (session 3c); returns the press-Space line for the runner to show.
local function certificateRender(ctx)
	local c = ctx.cert
	if not c or HARNESS.session.gen ~= c.gen then return end
	c.r = c.r + 1
	if c.r % 60 == 0 then certLine(ctx, "render") end
	certificateTick(ctx)
	return c.space and "press Space" or nil
end

local certificate = snapshotTest("restart from the death certificate", { "revive", "opt-in" }, freshRun(ISAAC),
	{ { "die and restart from the certificate", restartFromCertificate } })
certificate.onRender = certificateRender
tests[#tests + 1] = certificate

-- Missing Poster (user decision 2026-11-23, after the certificate restart worked in session 3c): after the certificate test, so the restart has worked in this session before this test relies on it.
-- shortcut: a death still dead DEAD_UPDATES updates (or twice the renders) on is taken for a game over, so a Missing Poster revive slower than that is restarted (unobserved; the other revives took 57 updates); raise the bound if a session shows one
local POSTER_KEPT = "Missing Poster gave no revive, Poster kept: The Lost likely locked"

-- Before the certificate's restart: player 0's state at the game over; a Poster still held makes the test a SKIP.
local function posterGameOver(ctx)
	local p = Isaac.GetPlayer(0)
	local kept = p ~= nil and holdsPoster(p)
	snap(ctx, "death " .. ctx.deaths .. " / game over", "true")
	snap(ctx, "death " .. ctx.deaths .. " / type", p and p:GetPlayerType() or "no player 0")
	snap(ctx, "death " .. ctx.deaths .. " / sources", sources(p))
	local why = kept and POSTER_KEPT or "Missing Poster gave no revive, Poster gone"
	if kept then ctx.skip = why end
	P("INFO", ctx.name, why, "| death", ctx.deaths)
end

local posterDie = dieUntilRevived(holdsPoster)
-- Dies as a source test while the Poster is held; a death that stays dead is watched as a certificate, restarted from, and the test ends at the new game.
local function posterDeaths(ctx)
	local c = ctx.cert
	if c and HARNESS.session.gen ~= c.gen then
		ctx.t = nil -- the death's watch ends with its run
		local res = certificateEnds(ctx)
		if res ~= "again" and not c.sent then table.insert(ctx.notes, "game over state unread: new game before the restart") end
		return res
	end
	local res = posterDie(ctx)
	if not (ctx.t and ctx.dead and not ctx.back) then
		if c then -- revived, or the watch ended
			ctx.cert = nil
			expectStart(nil)
		end
		return res
	end
	if not c then certificateArm(ctx, posterGameOver) end
	ctx.cert.u = ctx.cert.u + 1
	certificateTick(ctx)
	return res
end

local poster = sourceTest("Missing Poster", holding("Missing Poster", addTrinket(MISSING_POSTER)), posterDeaths)
poster.onRender = certificateRender
tests[#tests + 1] = poster

return { name = "revive", tests = tests }
