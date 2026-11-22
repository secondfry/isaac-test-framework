-- Lazarus with every revive dies until none is left (plan S5b): which revive the engine takes, in what order and into which type.
-- Recon: whether Kill() brings a revive, how long one takes, and the restart from a game over are unobserved (plan open point 3), so
-- each death logs what changed and nothing is asserted. Opt-in, played alone (tags revive): a death with no revive may leave a game
-- over screen. It kills on while player 0 lives, with or without a source held, so Lazarus's own revive is seen too.
local P = include("scripts.log").P
local engine = include("scripts.game")
local owned, cards = engine.owned, engine.cards
local console = include("scripts.console")
local fresh, give = console.fresh, console.give
local steps = include("scripts.steps")
local addCard, addTrinket, holdsTrinket = steps.addCard, steps.addTrinket, steps.holdsTrinket
local record = include("scripts.record")
local snap, try = record.snap, record.try
local fixture = include("scripts.fixtures").fixture
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local ANKH, JUDAS_SHADOW, LAZARUS_RAGS, MISSING_POSTER, SOUL_LAZARUS, LAZARUS = ids.ANKH, ids.JUDAS_SHADOW, ids.LAZARUS_RAGS,
	ids.MISSING_POSTER, ids.SOUL_LAZARUS, ids.LAZARUS

local game = Game()
local MAX_DEATHS, WATCH = 8, 240 -- updates watched after each Kill(), 8 s: no revive's duration has been observed

-- The revive sources `p` holds, as text.
local function sources(p)
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
		.. " players " .. game:GetNumPlayers() .. " hash " .. GetPtrHash(p) .. " room " .. game:GetLevel():GetCurrentRoomIndex() .. " | " .. (sources(p))
end

-- Kill() player 0, then watch WATCH updates, logging each change; again while the last death came back alive (IsDead false after
-- the watch) and fewer than MAX_DEATHS deaths.
local function dieUntilNoneLeft(ctx)
	if not ctx.t then
		local p = Isaac.GetPlayer(0)
		if not p then return P("INFO", ctx.name, "REVIVE ends: no player 0") end
		local held = sources(p)
		if (ctx.deaths or 0) >= MAX_DEATHS then return P("INFO", ctx.name, "REVIVE ends:", MAX_DEATHS, "deaths |", held) end
		ctx.deaths, ctx.t, ctx.last = (ctx.deaths or 0) + 1, 0, nil
		P("INFO", ctx.name, "REVIVE death", ctx.deaths, "Kill() on type", p:GetPlayerType(), "frame", game:GetFrameCount(), "|", held, "| Kill()",
			try(function() p:Kill() end))
	end
	ctx.t = ctx.t + 1
	local p = Isaac.GetPlayer(0)
	local now = state(p)
	if now ~= ctx.last then
		ctx.last = now
		P("INFO", ctx.name, "REVIVE death", ctx.deaths, "update", ctx.t, now)
	end
	if ctx.t < WATCH then return "again" end
	ctx.t = nil
	local alive = p ~= nil and try(function() return p:IsDead() end) == "false"
	snap(ctx, "death " .. ctx.deaths .. " / type", p and p:GetPlayerType() or "no player 0")
	snap(ctx, "death " .. ctx.deaths .. " / alive after " .. WATCH .. " updates", tostring(alive))
	if not alive then return P("INFO", ctx.name, "REVIVE ends: death", ctx.deaths, "left no live player 0") end
	return "again"
end

local LAZARUS_WITH_EVERY_REVIVE = fixture("Lazarus holding every revive", { fresh(LAZARUS), give(ANKH), give(JUDAS_SHADOW), give(LAZARUS_RAGS),
	addTrinket(MISSING_POSTER), addCard(SOUL_LAZARUS) }, LAZARUS)

return { name = "revive", tests = {
	snapshotTest("Lazarus with every revive dies until none is left", { "revive", "opt-in" }, LAZARUS_WITH_EVERY_REVIVE,
		{ { "die until no revive is left", dieUntilNoneLeft, nil, WATCH + 1 } }, { strict = true, limit = 300 + MAX_DEATHS * WATCH }),
} }
