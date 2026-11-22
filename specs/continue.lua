-- What Exit & Continue keeps: the stored twin, item copies, Esau Jr. characters and the temporary Esau. Each test asks the user for one
-- Exit & Continue, so the runner plays them last.
local P = include("scripts.log").P
local engine = include("scripts.game")
local findPlayer, withParent, owned = engine.findPlayer, engine.withParent, engine.owned
local rehud = include("scripts.rehud")
local dbg, keyOf, storedSettling = rehud.dbg, rehud.keyOf, rehud.storedSettling
local condition = include("scripts.wait").condition
local console = include("scripts.console")
local fresh, give, stage = console.fresh, console.give, console.stage
local steps = include("scripts.steps")
local changeType, addCard = steps.changeType, steps.addCard
local copies = include("scripts.copies")
local wisp, engineWisps = copies.wisp, copies.engineWisps
local manual = include("scripts.manual")
local exitAndContinue, continued = manual.exitAndContinue, manual.continued
local assertions = include("scripts.assert")
local expect, expectN, expectOne, expectCount, own, oneC4 = assertions.expect, assertions.expectN, assertions.expectOne,
	assertions.expectCount, assertions.own, assertions.oneC4
local record = include("scripts.record")
local startRecord, playerCount = record.start, record.playerCount
local settle = include("scripts.settle")
local look, settled = settle.look, settle.settled
local press = include("scripts.press")
local flip, soulJE = press.flip, press.soulJE
local jrSteps = include("scripts.esau_jr_steps")
local jrPair, loseEsauJr = jrSteps.jrPair, jrSteps.loseEsauJr
local jrSetup = include("scripts.fixtures").jrSetup
local ids = include("scripts.ids")
local T_LAZ, ISAAC, CAIN, FLIP, ESAU_JR, KEEPER, STRAWMAN = ids.T_LAZ, ids.ISAAC, ids.CAIN, ids.FLIP, ids.ESAU_JR, ids.KEEPER, ids.STRAWMAN

local game = Game()

-- A fixture: the run `setup` builds, ready once player 0 is of type `playerType` and, when `item` is given, owns it.
local function startsAs(name, setup, playerType, item)
	return { name = name, setup = setup, done = function()
		local p = Isaac.GetPlayer(0)
		if p:GetPlayerType() ~= playerType then return false, "player 0 is type " .. p:GetPlayerType() .. ", want " .. playerType end
		if item and owned(p, item) == 0 then return false, "player 0 owns no c" .. item end
		return true
	end }
end

-- shortcut: STEP_LIMIT, step, snapshotTest and helpersInfo copy specs/legacy.lua's obs, obsScenario and helpersInfo, which other specs
-- need too; move them to a shared module when legacy.lua goes (plan S4's last merge).
local STEP_LIMIT, TEST_LIMIT = 120, 1000 -- a test's limit: 600 of its updates are the user's Exit & Continue

-- A snapshot test's step: tags later TRACE lines with `label`; its error, or its limit passed, ends the test. A manual step keeps its prompt.
local function step(label, s, when, limit)
	local manualStep = type(s) == "table" and s
	return { label = label, run = manualStep and manualStep.run or s, manual = manualStep and manualStep.manual or nil, when = when,
		limit = limit or STEP_LIMIT }
end

-- A snapshot test from `fixture`, its setup steps and a settle wait unlogged, then the trace and `list` as { label, step, when, limit }
-- pairs (or lists of them), numbered, then a last settle wait.
local function snapshotTest(name, tags, fixture, list)
	local setup = {}
	for i, s in ipairs(fixture.setup) do setup[i] = step("setup " .. i, s) end
	setup[#setup + 1] = step("setup settle", settled)
	local all, n = { startRecord }, 0
	list = { table.unpack(list) } -- a copy: the caller's table may be shared
	list[#list + 1] = { "settle", settled }
	for _, s in ipairs(list) do
		for _, pair in ipairs(type(s[1]) == "string" and { s } or s) do
			n = n + 1
			all[#all + 1] = step(n .. " " .. pair[1], pair[2], pair[3], pair[4])
		end
	end
	return { name = name, tags = tags, fixture = { name = fixture.name, setup = setup, done = fixture.done }, steps = all, snapshot = true,
		onStepError = "end", limit = TEST_LIMIT }
end

-- Each player's Parent (as a GetPlayer index), ControllerIndex and ReHUD key and number: which character a temporary character's number follows.
local function helpersInfo(what)
	return function(ctx)
		for i = 0, game:GetNumPlayers() - 1 do
			local p = Isaac.GetPlayer(i)
			local parent = p.Parent and select(2, findPlayer(function(q) return GetPtrHash(q) == GetPtrHash(p.Parent) end))
			P("INFO", ctx.name, "HELPERS", what, "index", i, "type", p:GetPlayerType(), "parent", p.Parent and ("index " .. tostring(parent)) or "none",
				"ctrl", p.ControllerIndex, "key", keyOf(p), "number", tostring(dbg().roster.number(keyOf(p))))
		end
	end
end

local isaacJr = startsAs("Isaac holding Esau Jr.", jrSetup(ISAAC), ISAAC, ESAU_JR)

-- Tainted Lazarus flips with c4 from floor 1, the user exits and continues, and ChangePlayerType merges the stored twin: one c4, no Flip.
-- `beforeFlip`: a step ahead of the Flip, or nil.
local function continueTest(name, beforeFlip)
	-- Pacing alone decides whether the Flip stores the twin mid-settle, so the path each test takes is asserted.
	local function beforeExit(ctx, label)
		oneC4(ctx, label)
		expect(ctx, label .. ": stored form mid-settle", storedSettling() ~= "", beforeFlip == nil)
	end
	return { name = name, tags = { "continue", "rehud", "exit-continue", "new" },
		fixture = startsAs("Tainted Lazarus with c4 on floor 2", { fresh(T_LAZ), give(4), stage(2) }, T_LAZ, 4),
		steps = { beforeFlip or {}, flip("Flip"), look("before exit", beforeExit), exitAndContinue(), changeType(ISAAC),
			look("after continue and ChangePlayerType", function(ctx, label)
				expectOne(ctx, label, 4, ctx.floors[1], keyOf(Isaac.GetPlayer(0)))
				expectN(ctx, label, FLIP, 0)
			end) } }
end

-- L1's copies: Cain's owned and innate c46 on floor 1, a c46 wisp from floor 2, an owned c4 and a c4 wisp from floor 1. The totals
-- catch a Continue re-listing copies under the current floor.
local function copyKinds(ctx, label)
	own(ctx, label, 2, 46, ctx.floors[1], false)
	own(ctx, label, 1, 46, ctx.floors[2], true)
	own(ctx, label, 1, 4, ctx.floors[1], false)
	own(ctx, label, 1, 4, ctx.floors[1], true)
	expectCount(ctx, label, 3, 46)
	expectCount(ctx, label, 2, 4)
end

return { name = "continue", tests = {
	-- Does a stored character survive Exit & Continue?
	snapshotTest("Esau Jr. character stored across Exit & Continue", { "continue", "rehud", "obs", "obsy-b", "continue-a-stored", "exit-continue" },
		isaacJr, { jrPair("Esau Jr. #1"), continued, jrPair("Esau Jr. #2"), jrPair("Esau Jr. #3") }),
	-- Does a character lost with its Esau Jr. stay lost across Exit & Continue?
	snapshotTest("Esau Jr. lost, then Exit & Continue", { "continue", "rehud", "obs", "obsy-b", "continue-b-loses", "exit-continue" },
		isaacJr, { jrPair("Esau Jr. #1"), loseEsauJr(), continued, { "re-give c703", give(ESAU_JR) }, jrPair("Esau Jr. #2"),
			jrPair("Esau Jr. #3"), jrPair("Esau Jr. #4") }),
	-- The temporary Esau and Strawman's Keeper across Exit & Continue: their Parent, ControllerIndex and numbers before and after.
	-- The Soul first: its swap wants 2 players, and giveitem goes to a Keeper once one exists.
	snapshotTest("temporary Esau and Strawman's Keeper across Exit & Continue", { "continue", "rehud", "rehud-2.8", "exit-continue" },
		startsAs("Isaac holding Soul of Jacob and Esau", { fresh(ISAAC), give(4), addCard(Card.CARD_SOUL_JACOB) }, ISAAC, 4),
		{ { "Soul of Jacob and Esau", soulJE }, { "give Strawman", give(STRAWMAN) },
			{ "Strawman Keeper", condition("Strawman Keeper", function() return withParent(KEEPER) ~= nil end) },
			{ "settle", settled }, { "helpers before the exit", helpersInfo("before the exit") }, continued,
			{ "players after Continue", playerCount }, { "settle 2", settled }, { "helpers after Continue", helpersInfo("after Continue") } }),
	-- The Flip comes a few updates after restart, so the twin is stored mid-settle (the 20ca1f1 path).
	continueTest("Flip mid-settle, Exit & Continue, then ChangePlayerType"),
	-- The settle wait first, so the twin is stored settled, as in real play.
	continueTest("Flip once settled, Exit & Continue, then ChangePlayerType", look("before Flip", oneC4)),
	-- Copy kinds survive Exit & Continue, and Cain's saved innate items mean no second settle.
	{ name = "item copies survive Exit & Continue", tags = { "continue", "rehud", "exit-continue", "new" },
		fixture = startsAs("Cain", { fresh(CAIN) }, CAIN),
		steps = { look("start"), give(4), wisp(4), stage(2), wisp(46), look("before exit", copyKinds), exitAndContinue(),
			function(ctx) expect(ctx, "no re-settle after continue", dbg().roster.isSettling(keyOf(Isaac.GetPlayer(0))), false) end,
			engineWisps("after continue", 4, 1), engineWisps("after continue", 46, 1), look("after continue", copyKinds) } },
} }
