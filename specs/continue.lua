-- What Exit & Continue keeps: the stored twin, item copies, Esau Jr. characters and the temporary Esau. Each test asks the user for one
-- Exit & Continue, so the runner plays them last.
local rehud = include("scripts.rehud")
local keyOf, storedSettling, isSettling = rehud.keyOf, rehud.storedSettling, rehud.isSettling
local console = include("scripts.console")
local fresh, give, stage = console.fresh, console.give, console.stage
local steps = include("scripts.steps")
local changeType, addCard, keeperJoins = steps.changeType, steps.addCard, steps.keeperJoins
local copies = include("scripts.copies")
local wisp, engineWisps = copies.wisp, copies.engineWisps
local manual = include("scripts.manual")
local exitAndContinue, dropByHand, pickByHand = manual.exitAndContinue, manual.dropByHand, manual.pickByHand
local assertions = include("scripts.assert")
local expect, expectN, expectOne, expectCount, own, oneC4 = assertions.expect, assertions.expectN, assertions.expectOne,
	assertions.expectCount, assertions.own, assertions.oneC4
local record = include("scripts.record")
local playerCount, parentsInfo, idsInfo, watchLineup = record.playerCount, record.parentsInfo, record.idsInfo, record.watchLineup
local settle = include("scripts.settle")
local look, settled = settle.look, settle.settled
local press = include("scripts.press")
local flip, soulJE = press.flip, press.soulJE
local jrSteps = include("scripts.esau_jr_steps")
local jrPair, loseEsauJr, flipV, regiveEsauJr = jrSteps.jrPair, jrSteps.loseEsauJr, jrSteps.flipV, jrSteps.regiveEsauJr
local fixtures = include("scripts.fixtures")
local snapshot = include("scripts.snapshot")
local snapshotTest, perCharacter, continued = snapshot.test, snapshot.perCharacter, snapshot.continued
local ids = include("scripts.ids")
local ISAAC, CAIN, FLIP, ESAU_JR, STRAWMAN, YUM_HEART, BIRTHRIGHT = ids.ISAAC, ids.CAIN, ids.FLIP, ids.ESAU_JR, ids.STRAWMAN,
	ids.YUM_HEART, ids.BIRTHRIGHT
local stepOff = steps.stepOff

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
	return { name = name, tags = { "continue", "rehud", "exit-continue" }, fixture = fixtures.TLAZ_C4_FLOOR_2,
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
			{ "Strawman Keeper", keeperJoins },
			{ "settle", settled }, { "parents before the exit", parentsInfo("before the exit") }, continued,
			{ "players after Continue", playerCount }, { "settle 2", settled }, { "parents after Continue", parentsInfo("after Continue") } }, SNAPSHOT),
	-- The Flip comes a few updates after restart, so the twin is stored mid-settle (ReHUD roster.lua innateRows: a type still settling is left out of the save).
	continueTest("Flip mid-settle, Exit & Continue, then ChangePlayerType"),
	-- The settle wait first, so the twin is stored settled, as in real play.
	continueTest("Flip once settled, Exit & Continue, then ChangePlayerType", look("before Flip", oneC4)),
	-- Copy kinds survive Exit & Continue, and Cain's saved innate items mean no second settle.
	{ name = "item copies survive Exit & Continue", tags = { "continue", "rehud", "exit-continue" },
		fixture = fixtures.freshRun(CAIN),
		steps = { look("start"), give(4), wisp(4), stage(2), wisp(46), look("before exit", copyKinds), exitAndContinue(),
			function(ctx) expect(ctx, "no re-settle after continue", isSettling(keyOf(Isaac.GetPlayer(0))), false) end,
			engineWisps("after continue", 4, 1), engineWisps("after continue", 46, 1), look("after continue", copyKinds) } },
}
-- Recon for ReHUD matching a character back from Exit & Continue by its owned items: the WATCH lines log each player's items on the
-- 10 updates from each Continue and each new character (a fresh Esau Jr. character's 0-2 extra items included). c5, c6, c7 mark
-- who is who.
local REWORK = { "continue", "rehud-rework", "recon", "vanilla", "exit-continue" }
local function watched(t) t.onUpdate = watchLineup(10) return t end
local WALK = 450 -- manual.walk's ceiling
-- A drops copy 1 (holding Isaac) unpressed and makes B with copy 2; after the Continue copy 2 is displaced (giveitem destroys it,
-- docs/engine-facts.md) so the walk swaps Yum Heart for copy 1, whose press brings back Isaac.
tests[#tests + 1] = watched(snapshotTest("Esau Jr. copy picked up after Exit & Continue brings its character back",
	{ "walk", table.unpack(REWORK) }, isaacJr, {
		jrPair("copy 1: Isaac -> A"), { "give c5", give(5) }, { "A drops copy 1", dropByHand, nil, WALK }, { "give copy 2", give(ESAU_JR) },
		jrPair("copy 2: A -> B"), { "give c6", give(6) }, continued, { "give c45, displacing copy 2", give(YUM_HEART) },
		{ "B picks up copy 1", pickByHand, nil, WALK }, { "step off", stepOff }, jrPair("copy 1: B -> Isaac") },
	{ strict = true, limit = 2400 }))
-- A flips to Dead B and back, A's Esau Jr. makes LJ (on B's seed), LJ flips to B, B's Esau Jr. makes DLJ; who does DLJ's Flip bring after the Continue?
tests[#tests + 1] = watched(snapshotTest("Tainted Lazarus's Esau Jr. characters across Exit & Continue, then a Flip", REWORK, fixtures.TLAZ_JR, {
	{ "Flip A -> B", flipV("Flip A -> B") }, { "give c5", give(5) }, { "Flip B -> A", flipV("Flip B -> A") }, jrPair("Esau Jr. A -> LJ"),
	{ "give c6", give(6) }, { "Flip LJ -> B", flipV("Flip LJ -> B") }, { "re-give c703", regiveEsauJr() }, jrPair("Esau Jr. B -> DLJ"),
	{ "give c7", give(7) }, { "ids before the exit", idsInfo("before the exit") }, continued, { "ids after Continue", idsInfo("after Continue") },
	{ "Flip by DLJ", flipV("Flip by DLJ") }, { "ids after Flip", idsInfo("after Flip") } }, SNAPSHOT))
-- Lazarus Jr. (LJ) given Birthright: is its twin the stored Dead Lazarus D (D's label and c5) or a new character? Then Flip and Exit & Continue.
tests[#tests + 1] = watched(snapshotTest("Lazarus Jr. given Birthright, Flip, then Exit & Continue", REWORK, fixtures.TLAZ_JR, {
	{ "Flip A -> D", flipV("Flip A -> D") }, { "give c5", give(5) }, { "Flip D -> A", flipV("Flip D -> A") }, jrPair("Esau Jr. A -> LJ"),
	{ "give c6", give(6) }, { "ids of LJ", idsInfo("of LJ") }, { "give Birthright", give(BIRTHRIGHT) }, { "players after Birthright", playerCount },
	{ "ids after Birthright", idsInfo("after Birthright") }, { "Flip", flipV("Flip") }, { "ids after Flip", idsInfo("after Flip") },
	continued, { "ids after Continue", idsInfo("after Continue") } }, SNAPSHOT))

-- Recon: what Exit & Continue keeps of each character's ids (record.idsInfo) and state.
perCharacter(tests, "continue", "start, then Exit & Continue", fixtures.RECON_CHARACTERS, fixtures.character, function()
	return { { "ids before the exit", idsInfo("before the exit") }, continued, { "ids after Continue", idsInfo("after Continue") } }
end, true)

return { name = "continue", tests = tests }
