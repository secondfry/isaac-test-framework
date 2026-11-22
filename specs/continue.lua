-- What Exit & Continue keeps: the stored twin, item copies, Esau Jr. characters and the temporary Esau. Each test asks the user for one
-- Exit & Continue, so the runner plays them last.
local withParent = include("scripts.game").withParent
local rehud = include("scripts.rehud")
local keyOf, storedSettling, isSettling = rehud.keyOf, rehud.storedSettling, rehud.isSettling
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
local playerCount, helpersInfo, ids = record.playerCount, record.helpersInfo, record.ids
local settle = include("scripts.settle")
local look, settled = settle.look, settle.settled
local press = include("scripts.press")
local flip, soulJE = press.flip, press.soulJE
local jrSteps = include("scripts.esau_jr_steps")
local jrPair, loseEsauJr = jrSteps.jrPair, jrSteps.loseEsauJr
local fixtures = include("scripts.fixtures")
local snapshot = include("scripts.snapshot")
local snapshotTest, perCharacter = snapshot.test, snapshot.perCharacter
local enums = include("scripts.ids")
local ISAAC, CAIN, FLIP, ESAU_JR, KEEPER, STRAWMAN = enums.ISAAC, enums.CAIN, enums.FLIP, enums.ESAU_JR, enums.KEEPER, enums.STRAWMAN

local SNAPSHOT = { strict = true, limit = 1000 } -- 600 of a test's updates are the user's Exit & Continue
local isaacJr = fixtures.holdingJr("Isaac", ISAAC)

-- Tainted Lazarus flips with c4 from floor 1, the user exits and continues, and ChangePlayerType merges the stored twin: one c4, no Flip.
-- `beforeFlip`: a step ahead of the Flip, or nil.
local function continueTest(name, beforeFlip)
	-- Pacing alone decides whether the Flip stores the twin mid-settle, so the path each test takes is asserted.
	local function beforeExit(ctx, label)
		oneC4(ctx, label)
		expect(ctx, label .. ": stored form mid-settle", storedSettling() ~= "", beforeFlip == nil)
	end
	return { name = name, tags = { "continue", "rehud", "exit-continue", "new" }, fixture = fixtures.TLAZ_C4_FLOOR_2,
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

local tests = {
	-- Does a stored character survive Exit & Continue?
	snapshotTest("Esau Jr. character stored across Exit & Continue", { "continue", "rehud", "exit-continue" },
		isaacJr, { jrPair("Esau Jr. #1"), continued, jrPair("Esau Jr. #2"), jrPair("Esau Jr. #3") }, SNAPSHOT),
	-- Does a character lost with its Esau Jr. stay lost across Exit & Continue?
	snapshotTest("Esau Jr. lost, then Exit & Continue", { "continue", "rehud", "exit-continue" },
		isaacJr, { jrPair("Esau Jr. #1"), loseEsauJr(), continued, { "re-give c703", give(ESAU_JR) }, jrPair("Esau Jr. #2"),
			jrPair("Esau Jr. #3"), jrPair("Esau Jr. #4") }, SNAPSHOT),
	-- The temporary Esau and Strawman's Keeper across Exit & Continue: their Parent, ControllerIndex and numbers before and after.
	-- The Soul first: its swap wants 2 players, and giveitem goes to a Keeper once one exists.
	snapshotTest("temporary Esau and Strawman's Keeper across Exit & Continue", { "continue", "rehud", "rehud-2.8", "exit-continue" },
		fixtures.fixture("Isaac holding Soul of Jacob and Esau", { fresh(ISAAC), give(4), addCard(Card.CARD_SOUL_JACOB) }, ISAAC, fixtures.owns(4)),
		{ { "Soul of Jacob and Esau", soulJE }, { "give Strawman", give(STRAWMAN) },
			{ "Strawman Keeper", condition("Strawman Keeper", function() return withParent(KEEPER) ~= nil end) },
			{ "settle", settled }, { "helpers before the exit", helpersInfo("before the exit") }, continued,
			{ "players after Continue", playerCount }, { "settle 2", settled }, { "helpers after Continue", helpersInfo("after Continue") } }, SNAPSHOT),
	-- The Flip comes a few updates after restart, so the twin is stored mid-settle (the 20ca1f1 path).
	continueTest("Flip mid-settle, Exit & Continue, then ChangePlayerType"),
	-- The settle wait first, so the twin is stored settled, as in real play.
	continueTest("Flip once settled, Exit & Continue, then ChangePlayerType", look("before Flip", oneC4)),
	-- Copy kinds survive Exit & Continue, and Cain's saved innate items mean no second settle.
	{ name = "item copies survive Exit & Continue", tags = { "continue", "rehud", "exit-continue", "new" },
		fixture = fixtures.fresh(CAIN),
		steps = { look("start"), give(4), wisp(4), stage(2), wisp(46), look("before exit", copyKinds), exitAndContinue(),
			function(ctx) expect(ctx, "no re-settle after continue", isSettling(keyOf(Isaac.GetPlayer(0))), false) end,
			engineWisps("after continue", 4, 1), engineWisps("after continue", 46, 1), look("after continue", copyKinds) } },
}
-- Recon: what Exit & Continue keeps of each character's ids (record.ids) and state.
perCharacter(tests, "continue", "start, then Exit & Continue", fixtures.RECON_CHARACTERS, fixtures.character, function()
	return { { "ids before the exit", ids("before the exit") }, continued, { "ids after Continue", ids("after Continue") } }
end, true)

return { name = "continue", tests = tests }
