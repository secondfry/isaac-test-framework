-- Base character changes: Clicker and ChangePlayerType, on Tainted Lazarus and on Jacob and Esau.
local P = include("scripts.log").P
local engine = include("scripts.game")
local findPlayer, ofType, owned = engine.findPlayer, engine.ofType, engine.owned
local rehud = include("scripts.rehud")
local dbg, keyOf = rehud.dbg, rehud.keyOf
local console = include("scripts.console")
local fresh, give, remove, stage = console.fresh, console.give, console.remove, console.stage
local steps = include("scripts.steps")
local changeType, giveEsau = steps.changeType, steps.giveEsau
local assertions = include("scripts.assert")
local expect, expectN, expectOne, c4c5, noneLeft, fired = assertions.expect, assertions.expectN, assertions.expectOne, assertions.c4c5,
	assertions.noneLeft, assertions.fired
local record = include("scripts.record")
local pocketHeld, playerCount, storedSettlingNow, innerLine, innerOn, innerInfo, innerWatch = record.pocketHeld, record.playerCount,
	record.storedSettlingNow, record.innerLine, record.innerOn, record.innerInfo, record.innerWatch
local settle = include("scripts.settle")
local look, lookC, settled, idle = settle.look, settle.lookC, settle.settled, settle.idle
local press = include("scripts.press")
local flip, esauJr, clicker, cancelledClicker = press.flip, press.esauJr, press.clicker, press.cancelledClicker
local jrSteps = include("scripts.esau_jr_steps")
local jrFirst, jrAgain, giveClicker = jrSteps.jrFirst, jrSteps.jrAgain, jrSteps.giveClicker
local fixtures = include("scripts.fixtures")
local named = include("scripts.characters").named
local ids = include("scripts.ids")
local FLIP, CLICKER, ESAU_JR, ISAAC, T_LAZ, DEAD_T_LAZ, JACOB, ESAU, PRIMARY = ids.FLIP, ids.CLICKER, ids.ESAU_JR, ids.ISAAC, ids.T_LAZ,
	ids.DEAD_T_LAZ, ids.JACOB, ids.ESAU, ids.PRIMARY

local game = Game()
local TAGS, SNAPSHOT_TAGS, DISPUTE_TAGS = { "base_change", "rehud" }, { "base_change", "rehud", "obs" }, { "base_change", "rehud", "obs", "obsx" }

-- Fixtures: `setup` from a fresh run, then `done` as the precondition.
local function playerIs(t, what, extra)
	return function()
		local p = Isaac.GetPlayer(0)
		return p:GetPlayerType() == t and (not extra or extra(p)), "player 0 is not " .. what
	end
end
local function holdsJr(p) return p:GetActiveItem(PRIMARY) == ESAU_JR end
local function withEsau() return ofType(ESAU) ~= nil end
local function flipped() return { name = "Tainted Lazarus flipped", setup = fixtures.tlazFlipped(), done = playerIs(DEAD_T_LAZ, "Dead Tainted Lazarus") } end
local function tlazJr() return { name = "Tainted Lazarus holding Esau Jr.", setup = fixtures.tlazJr(), done = playerIs(T_LAZ, "Tainted Lazarus holding Esau Jr.", holdsJr) } end
local function tlazC4() return { name = "Tainted Lazarus holding c4", setup = { fresh(T_LAZ), give(4) }, done = playerIs(T_LAZ, "Tainted Lazarus") } end
local function jacobAndEsau(setup) return { name = "Jacob and Esau", setup = setup, done = playerIs(JACOB, "Jacob beside Esau", withEsau) } end

-- Snapshot tests: an obsx step that fails, or still waits after 120 updates, ends its test, which stops at 445 updates (setup and settle
-- waits included); an obs one is only skipped.
local DISPUTE_STEP_LIMIT, DISPUTE_LIMIT = 120, 445

-- A soft step that tags later TRACE lines with `label`; `strict`: with a step limit.
local function soft(label, step, strict) return { label = label, run = step, limit = strict and DISPUTE_STEP_LIMIT or nil } end

-- A snapshot test: the fixture's setup and a settle wait unlogged, then the trace and `list`'s { tag, step } pairs (a pair may be a list
-- of pairs), each soft and numbered, then a last settle wait. `strict`: steps and limits as obsx.
local function snapshotTest(name, fixture, list, strict)
	local setup = {}
	for _, s in ipairs(fixture.setup) do setup[#setup + 1] = strict and soft("setup " .. (#setup + 1), s, true) or s end
	setup[#setup + 1] = strict and soft("setup settle", settled, true) or settled
	local all, n, withSettle = {}, 0, { table.unpack(list) } -- a copy: the caller's list stays as given
	withSettle[#withSettle + 1] = { "settle", settled }
	for _, s in ipairs(withSettle) do
		for _, pair in ipairs(type(s[1]) == "string" and { s } or s) do
			n = n + 1
			all[#all + 1] = soft(n .. " " .. pair[1], pair[2], strict)
		end
	end
	return { name = name, tags = strict and DISPUTE_TAGS or SNAPSHOT_TAGS, snapshot = true, traceUpdates = true, onStepError = strict and "end" or "skip",
		limit = strict and DISPUTE_LIMIT or nil, steps = all, fixture = { name = fixture.name, setup = setup, done = fixture.done } }
end

-- Clicker until `done(ctx)` holds after a use's look, up to `maxUses` uses (each refilled by the swap); `around(ctx, "before" | "after")`
-- runs around each press. A random character may never land on J&E, so a missed split is a note in the RESULT line, not a fail.
local function clickerUntil(done, maxUses, lookStep, around)
	return function(ctx)
		if not ctx.phase then
			if ctx.done then return end
			if (ctx.uses or 0) >= maxUses then table.insert(ctx.notes, "no split in " .. maxUses .. " Clicker uses") return end
			ctx.uses, ctx.phase = (ctx.uses or 0) + 1, "press"
			if Isaac.GetPlayer(0):GetActiveItem() ~= CLICKER then error("Clicker left the active slot") end
			around(ctx, "before")
		end
		if ctx.phase == "press" then
			if clicker(ctx) == "again" then return "again" end
			around(ctx, "after")
			ctx.phase = "look"
		end
		if lookStep(ctx) == "again" then return "again" end
		ctx.phase = nil
		ctx.done = done(ctx)
		return "again"
	end
end
local function split() return Isaac.GetPlayer(0):GetPlayerType() == JACOB and ofType(ESAU) ~= nil end

-- After each Clicker use: Jacob's four c4 and Esau's one still listed on floor 1, and a merged Esau's number gone.
local clickerLook = look("after Clicker", function(ctx, label)
	label = label .. " " .. ctx.uses
	local n = 0
	for i = 0, game:GetNumPlayers() - 1 do n = n + owned(Isaac.GetPlayer(i), 4) end
	expectN(ctx, label, 4, n, ctx.floors[1])
	noneLeft(ctx, label)
	if ctx.esau and not findPlayer(function(p) return keyOf(p) == ctx.esau end) then expect(ctx, label .. ": merged Esau's number", dbg().roster.number(ctx.esau), nil) end
end)
-- Esau's key before each press, for clickerLook.
local function keepEsau(ctx, when)
	if when ~= "before" then return end
	local esau = ofType(ESAU)
	ctx.esau = esau and keyOf(esau)
end

-- Clicker until Jacob & Esau is merged and split back, up to 12 uses (each about 1 in 7 to land on J&E, runs 2-8), INNER lines around each press.
local function mergedAndSplit(ctx)
	if game:GetNumPlayers() == 1 then ctx.wasMerged = true end
	return ctx.wasMerged and split()
end
local function innerAround(ctx, when) P("INFO", ctx.name, "INNER " .. when .. " Clicker " .. ctx.uses, innerLine()) end

-- A vetoed Clicker fires no MC_USE_ITEM (lua-api-notes.md); `change`: ChangePlayerType 35 in the same update.
local function vetoed(change)
	local cancel = cancelledClicker(change)
	return function(ctx)
		if cancel(ctx) == "again" then return "again" end
		fired(ctx, "vetoed Clicker", ModCallbacks.MC_USE_ITEM, CLICKER, 0)
	end
end

local tests = {
	{ name = "ChangePlayerType out of Tainted Lazarus merges the stored twin", tags = TAGS, fixture = flipped(), steps = {
		look("before ChangePlayerType"), changeType(ISAAC),
		look("after ChangePlayerType", function(ctx, label)
			c4c5(ctx, label)
			local key = keyOf(Isaac.GetPlayer(0))
			expectOne(ctx, label .. " (Isaac owns)", 4, nil, key)
			expectOne(ctx, label .. " (Isaac owns)", 5, nil, key)
			expectN(ctx, label, FLIP, 0)
		end),
	} },
	{ name = "Clicker on Jacob and Esau until they split", tags = TAGS,
		fixture = jacobAndEsau({ fresh(JACOB), give(4), give(4), give(4), give(4), giveEsau(4), give(CLICKER), stage(2) }),
		steps = { look("start"), clickerUntil(split, 20, clickerLook, keepEsau) } },
	-- Inner Eye on both twins (Jacob 1, Esau 2), Clicker merges them and, when it rolls J&E, splits them; INNER lines log every player's
	-- c2 per update, so the log shows whether the engine drops a c2 (and whose) or ReHUD mislists it. A failure here is expected data.
	{ name = "Clicker merges and splits Jacob and Esau holding Inner Eye", tags = { "base_change", "rehud", "rehud-2.8", "opt-in" }, limit = 750,
		traceUpdates = true, onUpdate = innerWatch, fixture = jacobAndEsau({ fresh(JACOB) }), steps = {
			innerOn, give(2), giveEsau(2), giveEsau(2), give(CLICKER), give(1), give(1), named("Jacob"), named("Esau", ESAU),
			lookC("start", innerInfo("start")), clickerUntil(mergedAndSplit, 12, lookC("after Clicker"), innerAround), innerInfo("end"),
		} },
	snapshotTest("ChangePlayerType into Dead Tainted Lazarus with the twin stored, then Flip", tlazC4(), { { "Flip", flip("Flip") }, { "give c5", give(5) },
		{ "Flip back", flip("Flip back") }, { "ChangePlayerType 38", changeType(DEAD_T_LAZ) }, { "pocket before Flip again", pocketHeld },
		{ "players before Flip again", playerCount }, { "Flip again", flip("Flip again") }, { "pocket after Flip again", pocketHeld },
		{ "players after Flip again", playerCount } }),
	snapshotTest("a cancelled Clicker on the Esau Jr. character", tlazJr(), { jrFirst(), giveClicker(), { "cancel Clicker", vetoed(false) }, jrAgain() }, true),
	snapshotTest("a cancelled Clicker, then ChangePlayerType in the same update", tlazJr(), { jrFirst(), giveClicker(),
		{ "cancel Clicker and change type", vetoed(true) }, jrAgain() }, true),
	-- ReHUD 3021a90 tracker.lua:211: a merge survivor stored inside its 30-update settle, then returned. remove c4 stands in for the copy
	-- Clicker's removal can take; ChangePlayerType makes the merge deterministic.
	snapshotTest("ChangePlayerType into Tainted Lazarus merges the stored twin, then Flip at once", tlazC4(), { { "Flip", flip("Flip") },
		{ "give c5", give(5) }, { "ChangePlayerType 29", changeType(T_LAZ) }, { "remove c4", remove(4) }, { "Flip at once", flip("Flip at once") },
		{ "stored settling", storedSettlingNow }, { "settle", settled }, { "Flip back", flip("Flip back") }, { "watch 60", idle(60) } }, true),
	snapshotTest("ChangePlayerType into Dead Tainted Lazarus merges the stored twin, then Esau Jr. at once", tlazJr(), { { "Flip", flip("Flip") },
		{ "give c5", give(5) }, { "Flip back", flip("Flip back") }, { "ChangePlayerType 38", changeType(DEAD_T_LAZ) }, { "remove c4", remove(4) },
		{ "Esau Jr. at once", esauJr("Esau Jr. at once") }, { "stored settling", storedSettlingNow }, { "settle", settled }, jrAgain(),
		{ "watch 60", idle(60) } }, true),
}

return { name = "base_change", tests = tests }
