-- Characters added for a while, duos and Birthright (plan S4).
local P = include("scripts.log").P
local engine = include("scripts.game")
local ofType, owned, withParent, findPlayer, heldItems = engine.ofType, engine.owned, engine.withParent, engine.findPlayer, engine.heldItems
local rehud = include("scripts.rehud")
local dbg, entries, keyOf, countEntries, leftEntries = rehud.dbg, rehud.entries, rehud.keyOf, rehud.countEntries, rehud.leftEntries
local wait = include("scripts.wait")
local act, condition = wait.act, wait.condition
local console = include("scripts.console")
local fresh, give, remove, stage, giveAnyone = console.fresh, console.give, console.remove, console.stage, console.giveAnyone
local steps = include("scripts.steps")
local giveEsau, addCard, giveType = steps.giveEsau, steps.addCard, steps.giveType
local continued = include("scripts.manual").continued
local assertions = include("scripts.assert")
local expect, expectN, expectCount, oneC4, twoC4, birthrightOwners = assertions.expect, assertions.expectN, assertions.expectCount,
	assertions.oneC4, assertions.twoC4, assertions.birthrightOwners
local record = include("scripts.record")
local verdict, ids, startRecord = record.verdict, record.ids, record.start
local settle = include("scripts.settle")
local look, settled, lookC = settle.look, settle.settled, settle.lookC
local press = include("scripts.press")
local flip, soulJE, birthrightFlip, deadFirst = press.flip, press.soulJE, press.birthrightFlip, press.deadFirst
local jrSteps = include("scripts.esau_jr_steps")
local jrPair, flipV = jrSteps.jrPair, jrSteps.flipV
local tlazFlipped = include("scripts.fixtures").tlazFlipped
local named = include("scripts.characters").named
local enums = include("scripts.ids")
local FLIP, ESAU_JR, BIRTHRIGHT, STRAWMAN = enums.FLIP, enums.ESAU_JR, enums.BIRTHRIGHT, enums.STRAWMAN
local T_LAZ, DEAD_T_LAZ, ISAAC, KEEPER, ESAU = enums.T_LAZ, enums.DEAD_T_LAZ, enums.ISAAC, enums.KEEPER, enums.ESAU

local game = Game()

-- A fixture's done: player 0 is of type `t`.
local function playerIs(t)
	return function()
		local got = Isaac.GetPlayer(0):GetPlayerType()
		return got == t, "player 0 is type " .. got
	end
end
local function keeperPresent() return withParent(KEEPER) ~= nil, "no Strawman Keeper" end

-- shortcut: STEP_LIMIT, soft and snapshotTest copy legacy.lua's obs and obsScenario (strict only); move them to a shared module once
-- the other specs' snapshot tests need them too (S4 merge).
local STEP_LIMIT, TEST_LIMIT, CONTINUE_TEST_LIMIT = 120, 445, 1000

-- A snapshot test's step: tags later TRACE lines with `label`; its error, or its limit passed, logs "never happened" and ends the test.
local function soft(label, step, when, limit)
	local manualStep = type(step) == "table" and step
	return { label = label, run = manualStep and manualStep.run or step, manual = manualStep and manualStep.manual or nil, when = when,
		limit = limit or STEP_LIMIT }
end

-- A snapshot test: its fixture's `setup` steps and a settle wait, then the trace, then `stepPairs` ({ label, step, when, limit } or
-- lists of them), each soft and numbered, then a last settle wait.
local function snapshotTest(name, tags, setup, done, stepPairs, limit)
	local fixtureSteps, all, n = {}, { startRecord }, 0
	for _, s in ipairs(setup) do fixtureSteps[#fixtureSteps + 1] = soft("setup " .. (#fixtureSteps + 1), s) end
	fixtureSteps[#fixtureSteps + 1] = soft("setup settle", settled)
	local list = { table.unpack(stepPairs) }
	list[#list + 1] = { "settle", settled }
	for _, s in ipairs(list) do
		for _, pair in ipairs(type(s[1]) == "string" and { s } or s) do
			n = n + 1
			all[#all + 1] = soft(n .. " " .. pair[1], pair[2], pair[3], pair[4])
		end
	end
	return { name = name, tags = tags, fixture = { name = name, setup = fixtureSteps, done = done }, steps = all, snapshot = true,
		onStepError = "end", limit = limit or TEST_LIMIT }
end

-- Soul of Jacob and Esau's Esau after a room change: logs the transition, the room once it changes, every 10 updates while he stays,
-- and when he goes; still present after 150 updates, a note.
local function leaveRoom()
	local level = game:GetLevel()
	local cur, rooms = level:GetCurrentRoomIndex(), level:GetRooms()
	for i = 0, rooms.Size - 1 do
		local d = rooms:Get(i)
		if d.SafeGridIndex >= 0 and d.SafeGridIndex ~= cur then
			game:StartRoomTransition(d.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim and RoomTransitionAnim.WALK or 0)
			return d.SafeGridIndex
		end
	end
	error("no other room")
end
local function esauLeaves(ctx)
	ctx.t = (ctx.t or 0) + 1
	local e, room = withParent(ESAU), game:GetLevel():GetCurrentRoomIndex()
	if ctx.t == 1 then
		ctx.esauKey, ctx.esauRoom = e and keyOf(e), room
		local ok, res = pcall(leaveRoom)
		P("INFO", ctx.name, "leave the room: StartRoomTransition", ok and ("to " .. tostring(res)) or ("failed: " .. tostring(res)))
	elseif room ~= ctx.esauRoom then
		P("INFO", ctx.name, "room changed", ctx.esauRoom, "->", room, "after", ctx.t, "updates, summoned Esau", e and "present" or "gone")
		ctx.esauRoom = room
	end
	if not e then
		P("INFO", ctx.name, "summoned Esau gone after", ctx.t, "updates, room", room, "players", game:GetNumPlayers())
		ctx.t, ctx.esauGone = nil, true
		return
	end
	if ctx.t % 10 == 0 then P("INFO", ctx.name, "summoned Esau still present at update", ctx.t, "room", room) end
	if ctx.t >= 150 then
		table.insert(ctx.notes, "summoned Esau never left")
		ctx.t = nil
		return
	end
	return "again"
end

-- Each player's Parent (as a GetPlayer index), ControllerIndex and ReHUD key and number: which character a temporary one's number follows.
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

-- The Keeper killed: whether it leaves GetPlayer, and where ReHUD puts its items (ReHUD reads it as a merge, roster.lua shortcut).
local killKeeper = act("Kill the Strawman Keeper", function(ctx)
	local k = withParent(KEEPER)
	if not k then error("no Keeper") end
	ctx.keeperKey = keyOf(k)
	P("INFO", ctx.name, "Keeper ControllerIndex", k.ControllerIndex, "Isaac's", Isaac.GetPlayer(0).ControllerIndex)
	P("INFO", ctx.name, "Keeper Kill():", tostring(pcall(function() k:Kill() end)), "key", ctx.keeperKey)
end, function(ctx)
	if withParent(KEEPER) then return false, "Keeper still a player" end
	P("INFO", ctx.name, "Keeper left GetPlayer after", ctx.t, "updates")
	return true
end, 120)
local function keeperItems(ctx)
	local isaac, owners = keyOf(Isaac.GetPlayer(0)), {}
	for _, e in ipairs(entries()) do owners[#owners + 1] = "c" .. e.id .. ":" .. (e.owner == isaac and "Isaac" or e.owner == ctx.keeperKey and "Keeper" or tostring(e.owner)) end
	P("INFO", ctx.name, "after the Keeper left: Keeper number", tostring(dbg().roster.number(ctx.keeperKey)), "entries", table.concat(owners, " "), "Isaac engine items", heldItems(Isaac.GetPlayer(0)))
end

local CHECKED = { "characters", "rehud" }
local REHUD_2_8 = { "characters", "rehud", "rehud-2.8" }

return { name = "characters", tests = {
	{ name = "Birthright twins keep their items through two Flips and a new floor", tags = CHECKED,
		fixture = { name = "Tainted Lazarus flipped", setup = tlazFlipped(), done = playerIs(DEAD_T_LAZ) }, steps = {
			give(BIRTHRIGHT, 2), look("after Birthright", birthrightOwners),
			flip("Flip 1 of 2"), look("after Flip 1", birthrightOwners), flip("Flip 2 of 2"), look("after two Flips", birthrightOwners),
			stage(3), look("on stage 3", birthrightOwners),
		} },
	-- Run 7: Dead Tainted Lazarus, number 1, holds c711 from Basement II.
	{ name = "removing Birthright stores Dead Tainted Lazarus, and Flip brings him back", tags = CHECKED,
		fixture = { name = "Tainted Lazarus on floor 2", setup = { fresh(T_LAZ), give(4), stage(2) }, done = playerIs(T_LAZ) }, steps = {
			look("after c4", oneC4),
			give(BIRTHRIGHT, 2), look("after Birthright", function(ctx, label)
				oneC4(ctx, label)
				ctx.dead = keyOf(ofType(DEAD_T_LAZ))
			end),
			remove(BIRTHRIGHT, 1), look("after remove Birthright", function(ctx, label)
				oneC4(ctx, label)
				expect(ctx, label .. ": Dead form swapped", dbg().roster.isSwapped(ctx.dead), true)
				expect(ctx, label .. ": Dead form number", dbg().roster.number(ctx.dead), 1)
				expectCount(ctx, label, 1, FLIP, ctx.floors[2], nil, ctx.dead)
			end),
			stage(3), flip("Flip"), look("after Flip", function(ctx, label)
				oneC4(ctx, label)
				expect(ctx, label .. ": player 0 is the Dead form", keyOf(Isaac.GetPlayer(0)), ctx.dead)
				expectCount(ctx, label, 1, FLIP, ctx.floors[2], nil, ctx.dead)
				expect(ctx, label .. ": left entries", leftEntries(), 0)
			end),
		} },
	{ name = "temporary Esau from Soul of Jacob and Esau keeps his own items", tags = CHECKED,
		fixture = { name = "Isaac with two c4 on floor 2", setup = { fresh(ISAAC), give(4), give(4), stage(2) }, done = playerIs(ISAAC) }, steps = {
			look("before Soul of Jacob and Esau", twoC4),
			addCard(Card.CARD_SOUL_JACOB), soulJE, look("after Soul of Jacob and Esau", twoC4),
			-- ReHUD 2.8 lists the summoned Esau (user decision 2026-11-22): his c1 under him.
			giveEsau(1), look("after Esau c1", function(ctx, label) twoC4(ctx, label) expectN(ctx, label, 1, 1, nil, keyOf(ofType(ESAU))) end),
			stage(3), look("on stage 3", twoC4),
		} },
	-- Strawman's Keeper (type 14, a Parent) has his own number; giveitem then goes to him (in-game 2026-11-22).
	{ name = "Strawman's Keeper is a character with his own items", tags = REHUD_2_8, limit = 200,
		fixture = { name = "Isaac with Strawman's Keeper", setup = { fresh(ISAAC), give(4), give(STRAWMAN),
			condition("Strawman Keeper", function() return withParent(KEEPER) ~= nil end) }, done = keeperPresent }, steps = {
			named("Isaac"), named("Keeper", KEEPER),
			lookC("Keeper", function(ctx, label) expect(ctx, label .. ": Keeper has a number", dbg().roster.number(keyOf(withParent(KEEPER))) ~= nil, true) end),
			giveAnyone(5), lookC("after giveitem c5", function(ctx, label)
				local k = withParent(KEEPER)
				expect(ctx, "engine, not ReHUD: Keeper owns c5", owned(k, 5), 1)
				expectCount(ctx, label .. " (Keeper)", 1, 5, nil, nil, keyOf(k))
			end),
			giveType(6, KEEPER), lookC("after Keeper AddCollectible c6", function(ctx, label) expectCount(ctx, label, 1, 6, nil, nil, keyOf(withParent(KEEPER))) end),
		} },
	-- The summoned Esau (type 20, a Parent) has a number while present and none once he is gone; whether a room change takes him is recorded.
	{ name = "temporary Esau has a number until he leaves", tags = REHUD_2_8, limit = 350,
		fixture = { name = "Isaac holding Soul of Jacob and Esau", setup = { fresh(ISAAC), give(4), give(5), addCard(Card.CARD_SOUL_JACOB) },
			done = playerIs(ISAAC) }, steps = {
			soulJE, named("Esau", ESAU),
			lookC("summoned Esau present", function(ctx, label) expect(ctx, label .. ": Esau has a number", dbg().roster.number(keyOf(withParent(ESAU))) ~= nil, true) end),
			esauLeaves, lookC("after Esau left", function(ctx, label)
				if not ctx.esauGone then return end
				expect(ctx, label .. ": Esau's number", dbg().roster.number(ctx.esauKey), nil)
				expect(ctx, label .. ": Esau's entries", countEntries(function(e) return e.owner == ctx.esauKey end), 0)
			end),
		} },
	-- Review question (2026-11-22): the harness's GetData tag through Flip.
	snapshotTest("harness tag on Tainted Lazarus through Flip", REHUD_2_8, { fresh(T_LAZ), give(4) }, playerIs(T_LAZ), {
		{ "Flip", verdict("Flip", flip("Flip")) }, { "settle", settled }, { "Flip back", verdict("Flip back", flip("Flip back")) } }),
	snapshotTest("Strawman's Keeper killed", REHUD_2_8, { fresh(ISAAC), give(4), give(STRAWMAN),
		condition("Strawman Keeper", function() return withParent(KEEPER) ~= nil end), giveType(5, KEEPER) }, keeperPresent, {
		{ "helpers before the kill", helpersInfo("before the kill") }, { "kill the Keeper", killKeeper }, { "settle", settled },
		{ "where its items went", keeperItems }, { "helpers after the kill", helpersInfo("after the kill") } }),
	-- Which id tells the two Birthright twins apart and stays stable across Flip, Esau Jr. and Exit & Continue?
	snapshotTest("ids of the Birthright twins through Flip, Esau Jr. and Exit & Continue", { "characters", "rehud", "obs", "obsy-b", "exit-continue" },
		{ fresh(T_LAZ), give(4), give(ESAU_JR), give(BIRTHRIGHT, 2) }, playerIs(T_LAZ), {
		{ "ids after Birthright", ids("after Birthright") },
		{ "Flip", flipV("Flip") }, { "ids after Flip", ids("after Flip") }, { "Flip back", flipV("Flip back") }, { "ids after Flip back", ids("after Flip back") },
		{ "select type-29 twin", birthrightFlip, deadFirst }, jrPair("Esau Jr. #1"), { "ids after Esau Jr. #1", ids("after Esau Jr. #1") },
		jrPair("Esau Jr. #2"), { "ids after Esau Jr. #2", ids("after Esau Jr. #2") }, continued, { "ids after Continue", ids("after Continue") },
		{ "Flip after Continue", flipV("Flip after Continue") }, { "ids after Flip after Continue", ids("after Flip after Continue") } }, CONTINUE_TEST_LIMIT),
} }
