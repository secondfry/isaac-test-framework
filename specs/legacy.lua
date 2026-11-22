-- Temporary: HEAD df8ba84's scenario tables, unchanged, until each moves into its own spec (plan S4).
local P = include("scripts.log").P
local engine = include("scripts.game")
local itemConfig, seedOf, findPlayer, playerOfType, owned, wispsOf, heldItems, slots, helper, itemCounts, countsText = engine.itemConfig,
	engine.seedOf, engine.findPlayer, engine.playerOfType, engine.owned, engine.wispsOf, engine.heldItems, engine.slots, engine.helper,
	engine.itemCounts, engine.countsText
local rehud = include("scripts.rehud")
local dbg, entries, keyOf, leftEntries, storedSettling, ownerCount = rehud.dbg, rehud.entries, rehud.keyOf, rehud.leftEntries,
	rehud.storedSettling, rehud.ownerCount
local wait = include("scripts.wait")
local action, waitFor = wait.action, wait.waitFor
local console = include("scripts.console")
local restart, give, remove, stage, giveAnyone = console.restart, console.give, console.remove, console.stage, console.giveAnyone
local steps_ = include("scripts.steps")
local giveEsau, changeType, addCard, obsInfo, giveType, stepOff, onlyIf, holdsJr = steps_.giveEsau, steps_.changeType, steps_.addCard,
	steps_.obsInfo, steps_.giveType, steps_.stepOff, steps_.onlyIf, steps_.holdsJr
local copies = include("scripts.copies")
local wisp, killWisp, engineWisps, zodiacOn, grant3DB, listed = copies.wisp, copies.killWisp, copies.engineWisps, copies.zodiacOn,
	copies.grant3DB, copies.listed
local manual = include("scripts.manual")
local exitAndContinue, continued, dropByHand, pickByHand = manual.exitAndContinue, manual.continued, manual.dropByHand, manual.pickByHand
local assertions = include("scripts.assert")
local expect, expectN, expectOne, expectCount, own, c4c5, oneC4, twoC4, birthrightOwners, noneLeft = assertions.expect, assertions.expectN,
	assertions.expectOne, assertions.expectCount, assertions.own, assertions.c4c5, assertions.oneC4, assertions.twoC4,
	assertions.birthrightOwners, assertions.noneLeft
local record = include("scripts.record")
local verdict, ids, slotsNow, pocketHeld, typeNow, playerCount, storedSettlingNow, startObs, startObsChecked, innerLine, innerOn, innerInfo =
	record.verdict, record.ids, record.slotsNow, record.pocketHeld, record.typeNow, record.playerCount, record.storedSettlingNow,
	record.startObs, record.startObsChecked, record.innerLine, record.innerOn, record.innerInfo
local settle = include("scripts.settle")
local look, settled, idle, lookC = settle.look, settle.settled, settle.idle, settle.lookC
local press = include("scripts.press")
local endPress, flip, esauJr, soulJE, clicker, cancelledClicker, obsClicker, birthrightFlip, dropPress, primaryIs, jrToPrimary, deadFirst,
	swapCopies = press.endPress, press.flip, press.esauJr, press.soulJE, press.clicker, press.cancelledClicker, press.obsClicker,
	press.birthrightFlip, press.dropPress, press.primaryIs, press.jrToPrimary, press.deadFirst, press.swapCopies
local jrSteps = include("scripts.esau_jr_steps")
local regiveEsauJr, jrFirst, jrAgain, jrTwice, giveClicker, rememberOriginal, rememberForm, controlPresses, loseEsauJr, replaceEsauJr,
	useClickerEffect, jr, flipV, charPresses, esauLoses = jrSteps.regiveEsauJr, jrSteps.jrFirst, jrSteps.jrAgain, jrSteps.jrTwice,
	jrSteps.giveClicker, jrSteps.rememberOriginal, jrSteps.rememberForm, jrSteps.controlPresses, jrSteps.loseEsauJr, jrSteps.replaceEsauJr,
	jrSteps.useClickerEffect, jrSteps.jr, jrSteps.flipV, jrSteps.charPresses, jrSteps.esauLoses
local fixtures = include("scripts.fixtures")
local jrSetup, tlazJr, tlazFlips = fixtures.jrSetup, fixtures.tlazJr, fixtures.tlazFlips
local characters = include("scripts.characters")
local trackChars, named, who, whoInfo = characters.trackChars, characters.named, characters.who, characters.whoInfo
local strictObs = include("scripts.runner").strictObs
local enums = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT, YUM_HEART, SCHOOLBAG, STRAWMAN = enums.FLIP, enums.ESAU_JR, enums.CLICKER, enums.BIRTHRIGHT,
	enums.YUM_HEART, enums.SCHOOLBAG, enums.STRAWMAN
local T_LAZ, DEAD_LAZ, JE, ISAAC, CAIN, T_FORGOTTEN, KEEPER, ESAU, SECONDARY = enums.T_LAZ, enums.DEAD_LAZ, enums.JE, enums.ISAAC, enums.CAIN,
	enums.T_FORGOTTEN, enums.KEEPER, enums.ESAU, enums.SECONDARY

local game = Game()

local clickerLook = look("after Clicker", function(ctx, label)
	label = label .. " " .. ctx.uses
	local n = 0
	for i = 0, game:GetNumPlayers() - 1 do n = n + owned(Isaac.GetPlayer(i), 4) end
	expectN(ctx, label, 4, n, ctx.floors[1])
	noneLeft(ctx, label)
	if ctx.esau and not findPlayer(function(p) return keyOf(p) == ctx.esau end) then expect(ctx, label .. ": merged Esau's number", dbg().roster.number(ctx.esau), nil) end
end)

-- Clicker on Jacob until it is Jacob & Esau again, up to 20 uses (each refilled by the swap); each use is a checked swap followed by
-- a settled probe. A random character may never land on J&E, so a missed split is a note in the RESULT line, not a fail.
local function clickerLoop(ctx)
	if not ctx.phase then
		if ctx.back then return end
		if (ctx.uses or 0) >= 20 then table.insert(ctx.notes, "split (20 Clicker uses)") return end
		ctx.uses, ctx.phase = (ctx.uses or 0) + 1, "press"
		if Isaac.GetPlayer(0):GetActiveItem() ~= CLICKER then error("Clicker left the active slot") end
		local esau = playerOfType(PlayerType.PLAYER_ESAU)
		ctx.esau = esau and keyOf(esau)
	end
	if ctx.phase == "press" then
		if clicker(ctx) == "again" then return "again" end
		ctx.phase = "look"
	end
	if clickerLook(ctx) == "again" then return "again" end
	ctx.phase = nil
	ctx.back = Isaac.GetPlayer(0):GetPlayerType() == JE and playerOfType(PlayerType.PLAYER_ESAU) ~= nil
	return "again"
end

-- probes: engine facts the swaps rely on, as checks, so a game patch that changes one fails here first.

local function maxCharges(ctx)
	for _, c in ipairs({ { CLICKER, 6 }, { ESAU_JR, 1 }, { FLIP, 6 } }) do -- want: pre-REP+ items.xml
		expect(ctx, "MaxCharges c" .. c[1], itemConfig:GetCollectible(c[1]).MaxCharges, c[2])
	end
end

-- REP+ Flip takes 4 though MaxCharges reads 6 (user, in game; run 3).
local function pocketCharge(ctx)
	local p, s = Isaac.GetPlayer(0), ActiveSlot.SLOT_POCKET
	local function read() return p:GetActiveCharge(s) .. " + " .. p:GetBatteryCharge(s) end
	expect(ctx, "pocket item", p:GetActiveItem(s), FLIP)
	p:SetActiveCharge(6, s)
	expect(ctx, "SetActiveCharge(6, 2): charge + battery", read(), "4 + 2")
	p:SetActiveCharge(0, s)
	p:FullCharge(s)
	expect(ctx, "FullCharge(2) from 0: charge + battery", read(), "4 + 0")
end

local function onePress(label) return function(ctx) expect(ctx, label .. ": arms needed", ctx.arms, 1) end end

local function clickerHeld(ctx)
	local p = Isaac.GetPlayer(0)
	expect(ctx, "Clicker after a real press: active, charge", p:GetActiveItem() .. ", " .. p:GetActiveCharge(), CLICKER .. ", 0")
end

local function cardBesideFlip(ctx)
	local p, slot = Isaac.GetPlayer(0), nil
	for i = 0, 3 do
		if p:GetCard(i) == Card.CARD_SOUL_JACOB then slot = slot or i end
	end
	expect(ctx, "Soul of J&E beside Flip: card slot", slot, 1)
end

-- Tainted Lazarus flips with c4, the user exits and continues, and ChangePlayerType merges the stored form: one c4, no c711.
local function continueSteps(beforeFlip)
	local steps = { restart(T_LAZ), give(4), stage(2), beforeFlip }
	-- Pacing alone decides whether the Flip stores the 29 form mid-settle, so the path each variant tests is checked.
	local function beforeExit(ctx, label)
		oneC4(ctx, label)
		expect(ctx, label .. ": stored form mid-settle", storedSettling() ~= "", beforeFlip == nil)
	end
	for _, s in ipairs({ flip("Flip"), look("before exit", beforeExit), exitAndContinue(), changeType(ISAAC),
		look("after continue and ChangePlayerType", function(ctx, label)
			expectOne(ctx, label, 4, ctx.floors[1], keyOf(Isaac.GetPlayer(0)))
			expectN(ctx, label, FLIP, 0)
		end) }) do
		steps[#steps + 1] = s
	end
	return steps
end

local function jeCopies(ctx, label)
	expectCount(ctx, label, 1, 4, ctx.floors[1], false, ctx.jacob)
	expectCount(ctx, label, 1, 5, ctx.floors[1], false, ctx.esau)
end

-- L1's copies: Cain's owned and innate c46 on floor 1, a c46 wisp from floor 2, an owned c4 and a c4 wisp from floor 1. The totals
-- catch a continue re-listing copies under the current floor.
local function copyKinds(ctx, label)
	own(ctx, label, 2, 46, ctx.floors[1], false)
	own(ctx, label, 1, 46, ctx.floors[2], true)
	own(ctx, label, 1, 4, ctx.floors[1], false)
	own(ctx, label, 1, 4, ctx.floors[1], true)
	expectCount(ctx, label, 3, 46)
	expectCount(ctx, label, 2, 4)
end

-- After Clicker out of Tainted Lazarus (S3): every c4 (floor 1, the stored form's) and c5 (floor 2, the Dead form's) the engine counts,
-- wisps aside, is listed once, floor kept, under the player holding it; the stored form is forgotten. A roll into the other form's type
-- keeps Flip and starts a fresh, unseen form (run 8), so ReHUD's count of characters is not checked then.
local function afterTLazClicker(ctx, label)
	local t = Isaac.GetPlayer(0):GetPlayerType()
	P("INFO", ctx.name, "Clicker rolled type", t) -- Q7
	local lazarus = t == T_LAZ or t == DEAD_LAZ
	for id, floor in pairs({ [4] = ctx.floors[1], [5] = ctx.floors[2] }) do
		local sum = 0
		for i = 0, game:GetNumPlayers() - 1 do
			local q = Isaac.GetPlayer(i)
			local n = q:GetCollectibleNum(id, false) - (wispsOf(q)[id] or 0)
			sum = sum + n
			expectCount(ctx, label .. " (player " .. i .. ")", n, id, nil, nil, keyOf(q))
		end
		expectCount(ctx, label .. " (all)", sum, id)
		expectCount(ctx, label .. " (all)", sum, id, floor)
	end
	expectN(ctx, label, FLIP, lazarus and 1 or 0)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
	if lazarus then return expect(ctx, label .. ": left entries", leftEntries(), 0) end
	noneLeft(ctx, label)
end

-- r1, after ChangePlayerType(29) on the Dead form with the 29 form stored: the stored form's c4 (floor 1) and the Dead form's c5 (floor 2)
-- both on player 0, floors kept, and the stored form forgotten.
local function r1Merged(ctx, label)
	local key = keyOf(Isaac.GetPlayer(0))
	ctx.merged = key
	expectOne(ctx, label, 4, ctx.floors[1], key)
	expectOne(ctx, label, 5, ctx.floors[2], key)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
end

-- r1, after the next Flip: a fresh Dead form whose only entry is its Flip; the stored survivor keeps c4 (floor 1), c5 (floor 2) and one
-- Flip (which floor's Flip survives is not checked: the oldest goes once the survivor settles).
local function r1Fresh(ctx, label)
	local key = keyOf(Isaac.GetPlayer(0))
	expect(ctx, label .. ": a new form", key ~= ctx.merged and key ~= ctx.stored, true)
	expectCount(ctx, label, 1, FLIP, nil, nil, key)
	local n = 0
	for _, e in ipairs(entries()) do
		if e.owner == key then n = n + 1 end
	end
	expect(ctx, label .. ": entries of the new form", n, 1)
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.merged)
	expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.merged)
	expectCount(ctx, label, 1, FLIP, nil, nil, ctx.merged)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
end

-- r1 mirror, after ChangePlayerType(38) on the 29 form with the Dead form stored: unobserved in game, so the merge run 8 showed for r1 is
-- expected, and the engine state is logged; a resumed stored form (its seed back at player 0) fails here.
local function mirrorMerged(ctx, label)
	local p = Isaac.GetPlayer(0)
	local key = keyOf(p)
	P("INFO", ctx.name, "engine after ChangePlayerType(38): type", p:GetPlayerType(), "seed", seedOf(p), "key", key, "was", ctx.active, "stored", ctx.stored,
		"pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET), "players", game:GetNumPlayers())
	expect(ctx, label .. ": player 0 keeps its seed", seedOf(p), ctx.activeSeed)
	expectOne(ctx, label, 4, ctx.floors[1], key)
	expectOne(ctx, label, 5, ctx.floors[2], key)
	expectN(ctx, label, FLIP, 1)
	expect(ctx, label .. ": stored form's number", dbg().roster.number(ctx.stored), nil)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
end

-- P4c: an Esau Jr. form of Tainted Lazarus taken out of Tainted Lazarus. ReHUD merges a stored form only into its recorded Flip partner,
-- so it assumes the engine leaves the Esau Jr. original stored (lupa X2, X3, Y1); unobserved, so each engine state is logged as INFO
-- and a different outcome fails the checks. ctx.orig: the Esau Jr. presser; ctx.form: the Esau Jr. form; ctx.dead: a Flip partner.
local function engineInfo(ctx, what)
	local p = Isaac.GetPlayer(0)
	P("INFO", ctx.name, "engine " .. what .. ": type", p:GetPlayerType(), "seed", seedOf(p), "key", keyOf(p), "original", ctx.orig, "form", ctx.form, "dead", ctx.dead,
		"primary", p:GetActiveItem(ActiveSlot.SLOT_PRIMARY), "pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET), "players", game:GetNumPlayers())
end
local function origStored(ctx, label)
	expect(ctx, label .. ": Esau Jr. original stored", dbg().roster.isSwapped(ctx.orig), true)
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.orig)
end
-- ctx keys are ReHUD keys: Tainted Lazarus's Esau Jr. form takes its Dead form's seed (lua-api-notes.md Seeds and keys).
local function esauJrForm(ctx, label)
	ctx.form = keyOf(Isaac.GetPlayer(0))
	expect(ctx, label .. ": a new form", ctx.form ~= ctx.orig and ctx.form ~= ctx.dead, true)
	origStored(ctx, label)
end
local function origBeforeEsauJr(ctx, label)
	ctx.orig, ctx.form, ctx.dead = keyOf(Isaac.GetPlayer(0)), nil, nil
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.orig)
end

-- Twelve obsx scenarios at 445 updates each, plus a 1-update SKIP per other scenario and HARNESS DONE, fit three minutes (5385 of 5400
-- with 56 scenarios: one more obsx scenario, or 15 more others, breaks it; the test asserts it); in runs 2-3 none came near.
local OBSX_STEP_LIMIT, OBSX_SCENARIO_LIMIT = 120, 445

-- An obs step: tags later OBS lines with `tag` (unique within its scenario); a step that errors (its postcondition never came) is
-- logged as INFO and skipped, not failed; in an obsx or obsy scenario it also ends the scenario, so later presses cannot run on the
-- wrong setup. `limit` overrides the step ceiling (a Continue waits for the user).
local function obs(tag, step, when, stopOnError, limit)
	limit = limit or OBSX_STEP_LIMIT
	return function(ctx)
		if ctx.obsInterrupted or (not ctx.t and when and not when(ctx)) then return end
		local H = HARNESS
		if H.obs and H.obs.step ~= tag then H.obs.step = tag; P("OBS u" .. H.obs.u, "step " .. tag .. " begins") end
		local ok, res = pcall(step, ctx)
		if ok and stopOnError and res == "again" and not ctx.held and ctx.t >= limit then
			ok, res = false, "obsx ceiling " .. limit .. " updates" .. (ctx.why and (": " .. ctx.why) or "")
		end
		if ok then return res end
		P("INFO", ctx.name, tag, "never happened:", res)
		ctx.obsInterrupted = stopOnError
		ctx.t, ctx.held, ctx.before, ctx.label, ctx.why = nil, nil, nil, nil, nil
		endPress(H)
		H.cancelClicker, H.timing = nil, nil
	end
end

-- An obs scenario: `pre` unlogged (ending in a settle wait), then the logger, then `steps` as { tag, step } pairs, each soft and
-- numbered, then a last settle wait; a step may be a list of pairs, a pair may carry its step ceiling 4th. Markers: c4 before the
-- first swap, c5 right after it. `opts`: kind (default "small"), budget (the scenario ceiling, default OBSX_SCENARIO_LIMIT) and strict
-- (steps and ceilings as obsx whatever the name).
local function obsScenario(name, pre, steps, opts)
	opts = opts or {}
	local all, n = {}, 0
	local stopOnError = opts.strict or strictObs(name)
	for _, s in ipairs(pre) do
		all[#all + 1] = stopOnError and obs("setup " .. (#all + 1), s, nil, true) or s
	end
	all[#all + 1] = stopOnError and obs("setup settle", settled, nil, true) or settled
	all[#all + 1] = startObs
	steps[#steps + 1] = { "settle", settled }
	for _, s in ipairs(steps) do
		for _, pair in ipairs(type(s[1]) == "string" and { s } or s) do
			n = n + 1
			all[#all + 1] = obs(n .. " " .. pair[1], pair[2], pair[3], stopOnError, pair[4])
		end
	end
	return { name = name, kind = opts.kind or "small", steps = all, obsBudget = stopOnError and (opts.budget or OBSX_SCENARIO_LIMIT) }
end

-- obsy: INFO-only follow-ups to obsx runs 1-4, run as two modes ("only obsy a", "only obsy b"), each worst case under 5400 updates
-- (3 minutes) counting the 1-update SKIPs of every other scenario (tests/test_harness.py asserts both). Each stops at
-- OBSX_SCENARIO_LIMIT updates, a Continue one at 1000 with 600 for the user's exit and Continue.
local OBSY_CONTINUE_LIMIT = 1000
local LARGE_OBSY = { kind = "large", budget = OBSY_CONTINUE_LIMIT }

local OBSY = {
	-- Does A return after its form held Esau Jr. in the Schoolbag's second slot? Variant: a real Clicker press meanwhile.
	obsScenario("obsy a schoolbag", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, { "give Schoolbag", give(SCHOOLBAG) }, { "give c45", give(YUM_HEART) },
		{ "slots after c45", slotsNow },
		{ "Esau Jr. to secondary", dropPress("Esau Jr. to secondary", function(p) return p:GetActiveItem(SECONDARY) == ESAU_JR end, "SwapActiveItems", function(p) p:SwapActiveItems() end) },
		{ "Esau Jr. to primary", jrToPrimary() }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	obsScenario("obsy a schoolbag Clicker", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, { "give Schoolbag", give(SCHOOLBAG) }, giveClicker(),
		{ "slots after Clicker", slotsNow }, { "Clicker to primary", dropPress("Clicker to primary", primaryIs(CLICKER), "SwapActiveItems", function(p) p:SwapActiveItems() end) },
		{ "Clicker", verdict("Clicker", obsClicker) }, { "slots after the Clicker press", slotsNow }, { "Esau Jr. to primary", jrToPrimary() },
		{ "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Once A is lost, does A's Dead form X (or A) ever come back through B's Flips or presses?
	obsScenario("obsy a Dead form after A lost", tlazJr(), { { "Flip", flipV("Flip") }, { "Flip back", flipV("Flip back") }, { "Esau Jr. #1", jr("Esau Jr. #1") },
		replaceEsauJr(), { "Flip of B", flipV("Flip of B") }, { "Flip back to B", flipV("Flip back to B") }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Clicker's effect with Esau Jr. kept, on a non-Lazarus character.
	obsScenario("obsy a Isaac Clicker effect", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, { "give c1", give(1) },
		{ "use Clicker effect", useClickerEffect }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }),
	-- Other characters.
	obsScenario("obsy a J&E by Jacob", jrSetup(JE), charPresses()),
	obsScenario("obsy a J&E by Esau", { restart(JE), give(4), giveEsau(ESAU_JR) }, charPresses({ index = 1 }, nil, esauLoses)),
	obsScenario("obsy a Forgotten and Soul", jrSetup(PlayerType.PLAYER_THEFORGOTTEN), charPresses(nil, {
		{ "Esau Jr. as Forgotten #1", jr("Esau Jr. as Forgotten #1") }, { "Esau Jr. as Forgotten #2", jr("Esau Jr. as Forgotten #2") },
		{ "switch to the Soul", dropPress("switch to the Soul", function(p) return p:GetPlayerType() == PlayerType.PLAYER_THESOUL end,
			"ChangePlayerType 17", function(p) p:ChangePlayerType(PlayerType.PLAYER_THESOUL) end) } })),
	obsScenario("obsy a Tainted Forgotten", jrSetup(T_FORGOTTEN), charPresses({ index = 0, any = true })),
	obsScenario("obsy a Lazarus Risen", jrSetup(PlayerType.PLAYER_LAZARUS), charPresses(nil, { { "ChangePlayerType 11", changeType(PlayerType.PLAYER_LAZARUS2) } })),
	-- Locked on save slot 1 (README): a restart that never gives the type ends the scenario with an INFO "character locked?" line.
	obsScenario("obsy b Tainted Jacob", jrSetup(PlayerType.PLAYER_JACOB_B), charPresses()),
	obsScenario("obsy b Eden", jrSetup(PlayerType.PLAYER_EDEN), charPresses()),
	-- Does a stored A survive exit and Continue, and does a lost one stay lost?
	obsScenario("obsy b continue with A stored", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, continued,
		{ "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") } }, LARGE_OBSY),
	obsScenario("obsy b continue after B loses Esau Jr.", jrSetup(ISAAC), { { "Esau Jr. #1", jr("Esau Jr. #1") }, loseEsauJr(), continued,
		{ "re-give c703", give(ESAU_JR) }, { "Esau Jr. #2", jr("Esau Jr. #2") }, { "Esau Jr. #3", jr("Esau Jr. #3") }, { "Esau Jr. #4", jr("Esau Jr. #4") } }, LARGE_OBSY),
	-- Which id tells the two Birthright forms apart and stays stable across Flip, Esau Jr. and Continue?
	obsScenario("obsy b identity", { restart(T_LAZ), give(4), give(ESAU_JR), give(BIRTHRIGHT, 2) }, { { "ids after Birthright", ids("after Birthright") },
		{ "Flip", flipV("Flip") }, { "ids after Flip", ids("after Flip") }, { "Flip back", flipV("Flip back") }, { "ids after Flip back", ids("after Flip back") },
		{ "select type-29 twin", birthrightFlip, deadFirst }, { "Esau Jr. #1", jr("Esau Jr. #1") }, { "ids after Esau Jr. #1", ids("after Esau Jr. #1") },
		{ "Esau Jr. #2", jr("Esau Jr. #2") }, { "ids after Esau Jr. #2", ids("after Esau Jr. #2") }, continued, { "ids after Continue", ids("after Continue") },
		{ "Flip after Continue", flipV("Flip after Continue") }, { "ids after Flip after Continue", ids("after Flip after Continue") } }, LARGE_OBSY),
}

local OBS = {
	obsScenario("obs esaujr cross", tlazJr(), { jrFirst(), { "ChangePlayerType 38", changeType(DEAD_LAZ) }, { "ChangePlayerType 0", changeType(ISAAC) }, jrAgain() }),
	obsScenario("obs esaujr out", tlazJr(), { jrFirst(), { "ChangePlayerType 0", changeType(ISAAC) }, jrAgain() }),
	obsScenario("obs esaujr flip", tlazJr(), { jrFirst(), { "pocket of the form", pocketHeld }, { "Flip of the form", flip("Flip of the form") },
		{ "Flip back", flip("Flip back") }, jrAgain() }),
	obsScenario("obs esaujr flipped cross", tlazJr(), { { "Flip", flip("Flip") }, { "give c5", give(5) }, { "Flip back", flip("Flip back") },
		{ "Esau Jr.", esauJr("Esau Jr.") }, { "ChangePlayerType 38", changeType(DEAD_LAZ) }, jrAgain(),
		{ "Flip A", flip("Flip A") }, { "re-give c703 #2", regiveEsauJr() }, { "Esau Jr. #2", esauJr("Esau Jr. #2") },
		{ "Flip of the Esau Jr. form", flip("Flip of the Esau Jr. form") } }),
	obsScenario("obs esaujr birthright", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT) }, { "remove Birthright", remove(BIRTHRIGHT) },
		{ "settle", settled }, { "restart", restart(T_LAZ) }, { "give c4", give(4) }, { "give c703", give(ESAU_JR) }, { "give Birthright", give(BIRTHRIGHT) },
		{ "settle", settled }, jrFirst(), jrAgain() }),
	obsScenario("obs esaujr clicker", tlazJr(), { jrFirst(), { "give Clicker", give(CLICKER) }, { "Clicker", clicker }, { "Clicker roll", typeNow },
		{ "settle", settled }, jrAgain(),
		{ "re-give c703 #3", regiveEsauJr() }, { "Esau Jr. #3", esauJr("Esau Jr. #3") },
		{ "re-give c703 #4", regiveEsauJr() }, { "Esau Jr. #4", esauJr("Esau Jr. #4") } }),
	obsScenario("obs mirror", { restart(T_LAZ), give(4) }, { { "Flip", flip("Flip") }, { "give c5", give(5) }, { "Flip back", flip("Flip back") },
		{ "ChangePlayerType 38", changeType(DEAD_LAZ) }, { "pocket before Flip again", pocketHeld }, { "players before Flip again", playerCount },
		{ "Flip again", flip("Flip again") }, { "pocket after Flip again", pocketHeld }, { "players after Flip again", playerCount } }),
	obsScenario("obs esaujr birthright keep", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT) }, { "settle", settled }, jrAgain() }),
	obsScenario("obs esaujr cross35", tlazJr(), { jrFirst(), { "ChangePlayerType 35", changeType(T_FORGOTTEN) }, { "settle", settled }, jrAgain(),
		{ "re-give c703 #3", regiveEsauJr() }, { "Esau Jr. #3", esauJr("Esau Jr. #3") } }),
	obsScenario("obs esaujr dead seed", tlazJr(), { jrFirst(), jrAgain(), { "pocket before Flip on A", pocketHeld }, { "Flip on A", flip("Flip on A") } }),
	obsScenario("obs esaujr birthright flip", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT) }, { "settle", settled },
		{ "Flip", flip("Flip") } }),
	obsScenario("obsx cancelled Clicker", tlazJr(), { jrFirst(), giveClicker(),
		{ "cancel Clicker", cancelledClicker(false) }, jrAgain() }),
	obsScenario("obsx cancelled Clicker then change", tlazJr(), { jrFirst(), giveClicker(),
		{ "cancel Clicker and change type", cancelledClicker(true) }, jrAgain() }),
	obsScenario("obsx Clicker on returned original", tlazJr(), { jrFirst(), jrAgain(), giveClicker(),
		{ "Clicker", obsClicker }, jrTwice() }),
	obsScenario("obsx Clicker after Flip", tlazJr(), { jrFirst(), { "Flip of the form", flip("Flip of the form") },
		giveClicker(), { "Clicker", obsClicker }, jrTwice() }),
	obsScenario("obsx Clicker with Birthright", tlazJr(), { jrFirst(), { "give Birthright", give(BIRTHRIGHT, 2) },
		{ "select type-29 twin", birthrightFlip, function() return Isaac.GetPlayer(0):GetPlayerType() == DEAD_LAZ end },
		giveClicker(), { "Clicker by type 29", function(ctx)
			if not ctx.t and (Isaac.GetPlayer(0):GetPlayerType() ~= T_LAZ or not playerOfType(DEAD_LAZ)) then
				error("expected type 29 in player 0 with the type-38 Birthright twin present")
			end
			return obsClicker(ctx)
		end }, jrTwice() }),
	obsScenario("obsx Isaac Esau Jr Clicker", jrSetup(ISAAC), { jrFirst(),
		giveClicker(), { "Clicker", obsClicker }, jrTwice() }),
	-- ReHUD 3021a90 tracker.lua:211: a merge survivor stored inside its 30-update settle, then returned. remove c4 stands in for the copy
	-- Clicker's removal can take; ChangePlayerType makes the merge deterministic.
	obsScenario("obsx merge 38 to 29 then Flip", { restart(T_LAZ), give(4) }, { { "Flip", flip("Flip") }, { "give c5", give(5) },
		{ "ChangePlayerType 29", changeType(T_LAZ) }, { "remove c4", remove(4) }, { "Flip at once", flip("Flip at once") },
		{ "stored settling", storedSettlingNow }, { "settle", settled }, { "Flip back", flip("Flip back") }, { "watch 60", idle(60) } }),
	obsScenario("obsx merge 29 to 38 then Esau Jr.", tlazJr(), { { "Flip", flip("Flip") }, { "give c5", give(5) }, { "Flip back", flip("Flip back") },
		{ "ChangePlayerType 38", changeType(DEAD_LAZ) }, { "remove c4", remove(4) }, { "Esau Jr. at once", esauJr("Esau Jr. at once") },
		{ "stored settling", storedSettlingNow }, { "settle", settled }, jrAgain(), { "watch 60", idle(60) } }),
	obsScenario("obsx form loses Esau Jr.", tlazJr(), {
		{ "record A", rememberOriginal }, jrFirst(), replaceEsauJr(), controlPresses() }),
	obsScenario("obsx form uses Clicker effect", tlazJr(), {
		{ "record A", rememberOriginal }, jrFirst(), { "give c1", give(1) }, { "use Clicker effect", useClickerEffect }, controlPresses() }),
	obsScenario("obsx Isaac form loses Esau Jr.", jrSetup(ISAAC), {
		{ "record A", rememberOriginal }, jrFirst(), replaceEsauJr(), controlPresses() }),
	obsScenario("obsx original loses Esau Jr.", tlazJr(), {
		{ "record A", rememberOriginal }, jrFirst(), { "record B", rememberForm },
		{ "Esau Jr. back to A", esauJr("Esau Jr. back to A") },
		{ "verify A returned", function(ctx)
			if seedOf(Isaac.GetPlayer(0)) ~= ctx.originalSeed then error("expected original A in player 0") end
		end },
		replaceEsauJr(), controlPresses() }),
}
for _, s in ipairs(OBSY) do OBS[#OBS + 1] = s end

local FINAL -- set in the block below: a function, as the main chunk is near Lua's 200-locals limit
;(function()
-- Soul of Jacob and Esau's Esau leaves when Isaac leaves the room (wiki); without a room change by 60 updates he is killed (wiki: no
-- consequences); logs every 10 updates while he stays, and when he goes.
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
	local e = helper(ESAU)
	if ctx.t == 1 then
		ctx.esauKey = e and keyOf(e)
		local ok, res = pcall(leaveRoom)
		P("INFO", ctx.name, "leave the room: StartRoomTransition", ok and ("to " .. tostring(res)) or ("failed: " .. tostring(res)))
	end
	if not e then
		P("INFO", ctx.name, "summoned Esau gone after", ctx.t, "updates, after", ctx.how or "the room change", "room", game:GetLevel():GetCurrentRoomIndex(), "players", game:GetNumPlayers())
		ctx.t, ctx.esauGone = nil, true
		return
	end
	if ctx.t % 10 == 0 then P("INFO", ctx.name, "summoned Esau still present at update", ctx.t, "room", game:GetLevel():GetCurrentRoomIndex()) end
	if ctx.t == 60 then
		ctx.how = "Kill()"
		P("INFO", ctx.name, "summoned Esau Kill():", tostring(pcall(function() e:Kill() end)))
	end
	if ctx.t >= 150 then
		table.insert(ctx.notes, "summoned Esau never left")
		ctx.t = nil
		return
	end
	return "again"
end

-- Clicker until Jacob & Esau is merged and split back, up to 12 uses (each about 1 in 7 to land on J&E, runs 2-8), a look after each.
local function jeClickerLoop(ctx)
	if not ctx.phase then
		if ctx.split then return end
		if (ctx.uses or 0) >= 12 then table.insert(ctx.notes, "no split in 12 Clicker uses") return end
		ctx.uses, ctx.phase = (ctx.uses or 0) + 1, "press"
		if Isaac.GetPlayer(0):GetActiveItem() ~= CLICKER then error("Clicker left the active slot") end
		P("INFO", ctx.name, "INNER before Clicker " .. ctx.uses, innerLine())
	end
	if ctx.phase == "press" then
		if clicker(ctx) == "again" then return "again" end
		P("INFO", ctx.name, "INNER after Clicker " .. ctx.uses, innerLine())
		ctx.phase = "look"
	end
	if ctx.gLook(ctx) == "again" then return "again" end
	ctx.phase = nil
	if game:GetNumPlayers() == 1 then ctx.wasMerged = true end
	ctx.split = ctx.wasMerged and Isaac.GetPlayer(0):GetPlayerType() == JE and playerOfType(ESAU) ~= nil
	return "again"
end

-- F: what Clicker out of a Tainted Lazarus form gave the live character, and which stored Flip partners' items it got (marked gone: merged).
local function beforeClicker(ctx) trackChars() ctx.pre = itemCounts(Isaac.GetPlayer(0)) end
local ACTIVES = { [ESAU_JR] = true, [FLIP] = true, [CLICKER] = true, [SCHOOLBAG] = true }
local function clickerMerges(ctx)
	trackChars()
	local now, gained = itemCounts(Isaac.GetPlayer(0)), {}
	for id, n in pairs(now) do
		if n > (ctx.pre[id] or 0) then gained[id] = n - (ctx.pre[id] or 0) end
	end
	P("INFO", ctx.name, "Clicker: type", Isaac.GetPlayer(0):GetPlayerType(), "items gained", countsText(gained), "players", game:GetNumPlayers())
	for _, c in pairs(HARNESS.chars.list) do
		if c.state == "stored" then
			local hit = {}
			for id in pairs(c.items) do
				if gained[id] and not ACTIVES[id] then hit[#hit + 1] = "c" .. id end
			end
			P("INFO", ctx.name, "Clicker: stored", c.name, "items", countsText(c.items), "found on the live one:", #hit > 0 and table.concat(hit, " ") or "none")
			-- Only a Flip partner merges into the live form (roster.lua); an Esau Jr. character stays stored (user decision 2026-11-22).
			if #hit > 0 and c.storedBy == FLIP then c.state = "gone"
			elseif #hit > 0 then table.insert(ctx.notes, "engine moved stored Esau Jr. character " .. c.name .. "'s items (unobserved)") end
		end
	end
end

local function steps(...)
	local t = {}
	for _, list in ipairs({ ... }) do
		for _, s in ipairs(list) do t[#t + 1] = s end
	end
	return t
end

FINAL = {
	-- A: two copies, each keeping the character it last swapped out; Schoolbag holds both on A.
	{ name = "final A two Esau Jr. copies", kind = "small", budget = 350, steps = {
		restart(ISAAC), give(4), give(ESAU_JR), named("Isaac"), lookC("start"),
		esauJr("copy 1: Isaac -> A"), named("A"), give(5), give(SCHOOLBAG), give(ESAU_JR), obsInfo("A's slots", slots), lookC("A with two copies"),
		esauJr("copy 2: A -> B"), named("B"), give(6), lookC("B"),
		esauJr("copy 2: B -> A"), who("A"), lookC("A back"),
		swapCopies(), esauJr("copy 1: A -> Isaac"), who("Isaac"), lookC("Isaac back"),
		esauJr("copy 1: Isaac -> A"), who("A"), lookC("A again"),
		swapCopies(), esauJr("copy 2: A -> B"), who("B"), lookC("B again"),
	} },
	-- B: A drops Esau Jr. on a pedestal and takes it back; its press brings Isaac back (console 2026-11-22).
	{ name = "final B Esau Jr. dropped and picked up", kind = "small", budget = 1100, steps = {
		restart(ISAAC), give(4), give(ESAU_JR), named("Isaac"), esauJr("Isaac -> A"), named("A"), give(5), lookC("A"),
		dropByHand, lookC("Esau Jr. on the pedestal"), pickByHand, stepOff, lookC("Esau Jr. picked back up"),
		esauJr("A presses the picked-up copy"), who("Isaac"), lookC("Isaac back"),
	} },
	-- C: LJ shares D's seed; each keeps its own row and items through Flips and presses.
	{ name = "final C Tainted Lazarus Esau Jr.", kind = "small", budget = 350, steps = steps(tlazFlips(), {
		flip("Flip by D"), whoInfo("Flip by D"), lookC("after Flip by D"),
		onlyIf("player 0 holds no Esau Jr.", holdsJr, esauJr("Esau Jr. by player 0")), whoInfo("Esau Jr. by player 0"), lookC("after Esau Jr."),
		onlyIf("player 0 holds no Esau Jr.", holdsJr, esauJr("Esau Jr. again")), whoInfo("Esau Jr. again"), lookC("after Esau Jr. again"),
	}) },
	-- D: Strawman's Keeper (type 14, a Parent) has its own row; giveitem then goes to it (in-game 2026-11-22).
	{ name = "final D Strawman", kind = "small", budget = 200, steps = {
		restart(ISAAC), give(4), give(STRAWMAN), waitFor("Strawman Keeper", function() return helper(KEEPER) ~= nil end), named("Isaac"), named("Keeper", KEEPER),
		lookC("Keeper", function(ctx, label) expect(ctx, label .. ": Keeper has a number", dbg().roster.number(keyOf(helper(KEEPER))) ~= nil, true) end),
		giveAnyone(5), lookC("after giveitem c5", function(ctx, label)
			local k = helper(KEEPER)
			expect(ctx, "engine, not ReHUD: Keeper owns c5", owned(k, 5), 1)
			expectCount(ctx, label .. " (Keeper)", 1, 5, nil, nil, keyOf(k))
		end),
		giveType(6, KEEPER), lookC("after Keeper AddCollectible c6", function(ctx, label) expectCount(ctx, label, 1, 6, nil, nil, keyOf(helper(KEEPER))) end),
	} },
	-- E: the summoned Esau (type 20, a Parent) has a row while present and none once he is gone.
	{ name = "final E Soul of Jacob and Esau", kind = "small", budget = 350, steps = {
		restart(ISAAC), give(4), give(5), addCard(Card.CARD_SOUL_JACOB), soulJE, named("Esau", ESAU),
		lookC("summoned Esau present", function(ctx, label) expect(ctx, label .. ": Esau has a number", dbg().roster.number(keyOf(helper(ESAU))) ~= nil, true) end),
		esauLeaves, lookC("after Esau left", function(ctx, label)
			if not ctx.esauGone then return end
			expect(ctx, label .. ": Esau's number", dbg().roster.number(ctx.esauKey), nil)
			expect(ctx, label .. ": Esau's entries", ownerCount(ctx.esauKey), 0)
		end),
	} },
	-- F (observation): Flip partners change after Esau Jr. (LJ <-> D, then DJ <-> LJ), then Clicker out of the live form; ReHUD sets each
	-- partner once (roster.lua partnerOf), so a failure here is expected. OBS lines log the engine and ReHUD every update.
	{ name = "final F Flip partners", kind = "small", budget = 450, onlyPicked = true, steps = steps({ startObsChecked }, tlazFlips(), {
		give(ESAU_JR), esauJr("Esau Jr. D -> DJ"), named("DJ"), give(7), lookC("DJ"),
		flip("Flip DJ -> LJ"), who("LJ"), lookC("LJ back"), flip("Flip LJ -> DJ"), who("DJ"), lookC("DJ back"),
		give(SCHOOLBAG), give(CLICKER), give(1), beforeClicker, clicker, clickerMerges, lookC("after Clicker"),
	}) },
	-- G (observation): Inner Eye on both twins (Jacob 1, Esau 2), Clicker merges them and, when it rolls J&E, splits them; INNER lines log
	-- every player's c2 per update, so the log shows whether the engine drops a c2 (and whose) or ReHUD mislists it.
	{ name = "final G Jacob and Esau Clicker split", kind = "small", budget = 750, onlyPicked = true, steps = {
		restart(JE), startObsChecked, innerOn, give(2), giveEsau(2), giveEsau(2), give(CLICKER), give(1), give(1), named("Jacob"), named("Esau", ESAU),
		lookC("start", innerInfo("start")), function(ctx) ctx.gLook = lookC("after Clicker") end, jeClickerLoop, innerInfo("end"),
	} },
}

local STRICT = { strict = true } -- each final observation stops at its first missing step and at 445 updates
-- Observation only (INFO, OBS lines every update): cf965b0 counts a newcomer holding Esau Jr. of the index's previous type as a swap even
-- when the player count drops, and stores a vanished character whose partner is stored; this logs what the engine does to the twins.
FINAL[#FINAL + 1] = obsScenario("final I Birthright twins Esau Jr.", { restart(T_LAZ), give(4), give(ESAU_JR), give(BIRTHRIGHT, 2) }, {
	{ "players", playerCount }, { "Esau Jr.", verdict("Esau Jr.", esauJr("Esau Jr.")) }, { "players after Esau Jr.", playerCount }, { "settle", settled },
	{ "Esau Jr. back", verdict("Esau Jr. back", esauJr("Esau Jr. back")) }, { "players after Esau Jr. back", playerCount }, { "settle 2", settled },
	{ "Flip", verdict("Flip", flip("Flip")) }, { "players after Flip", playerCount } }, STRICT)

-- Each player's Parent (as a GetPlayer index), ControllerIndex and ReHUD key and number: which character a helper's row follows.
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

-- Observation only: the Keeper killed; whether it leaves GetPlayer, and where ReHUD puts its items (ReHUD reads it as a merge, roster.lua shortcut).
local killKeeper = action("Kill the Strawman Keeper", function(ctx)
	local k = helper(KEEPER)
	if not k then error("no Keeper") end
	ctx.keeperKey = keyOf(k)
	P("INFO", ctx.name, "Keeper ControllerIndex", k.ControllerIndex, "Isaac's", Isaac.GetPlayer(0).ControllerIndex)
	P("INFO", ctx.name, "Keeper Kill():", tostring(pcall(function() k:Kill() end)), "key", ctx.keeperKey)
end, function(ctx)
	if helper(KEEPER) then return false, "Keeper still a player" end
	P("INFO", ctx.name, "Keeper left GetPlayer after", ctx.t, "updates")
	return true
end, 120)
local function keeperItems(ctx)
	local isaac, owners = keyOf(Isaac.GetPlayer(0)), {}
	for _, e in ipairs(entries()) do owners[#owners + 1] = "c" .. e.id .. ":" .. (e.owner == isaac and "Isaac" or e.owner == ctx.keeperKey and "Keeper" or tostring(e.owner)) end
	P("INFO", ctx.name, "after the Keeper left: Keeper number", tostring(dbg().roster.number(ctx.keeperKey)), "entries", table.concat(owners, " "), "Isaac engine items", heldItems(Isaac.GetPlayer(0)))
end
-- Observation only, review questions (2026-11-22): GetData tag through Flip; GetPtrHash in the flipped cross and on a Flip of an Esau Jr.
-- form, and whether A's stored Dead form returns when A (type 38) flips; the hash of a form that comes back on a stored form's seed with
-- other items; the summoned Esau across Exit & Continue (large: the user's Continue).
FINAL[#FINAL + 1] = obsScenario("final K tag through Flip", { restart(T_LAZ), give(4) }, { { "Flip", verdict("Flip", flip("Flip")) },
	{ "settle", settled }, { "Flip back", verdict("Flip back", flip("Flip back")) } }, STRICT)
FINAL[#FINAL + 1] = obsScenario("final L flipped cross", tlazJr(), { { "Flip", verdict("Flip", flip("Flip")) }, { "give c5", give(5) },
	{ "Flip back", verdict("Flip back", flip("Flip back")) }, { "Esau Jr.", verdict("Esau Jr.", esauJr("Esau Jr.")) },
	{ "Flip of the Esau Jr. form", verdict("Flip of the Esau Jr. form", flip("Flip of the Esau Jr. form")) },
	{ "Flip back to the form", verdict("Flip back to the form", flip("Flip back to the form")) }, { "ids of the form", ids("of the form") },
	{ "ChangePlayerType 38", changeType(DEAD_LAZ) }, jrAgain(), { "ids after the original returned", ids("after the original returned") },
	{ "Flip A (type 38)", verdict("Flip A (type 38)", flip("Flip A (type 38)")) }, { "ids after Flip A", ids("after Flip A") } }, STRICT)
FINAL[#FINAL + 1] = obsScenario("final M original loses Esau Jr.", tlazJr(), { jrFirst(), { "Esau Jr. back to A", verdict("Esau Jr. back to A", esauJr("Esau Jr. back to A")) },
	replaceEsauJr(), { "Esau Jr. after the loss", verdict("Esau Jr. after the loss", esauJr("Esau Jr. after the loss")) },
	{ "Esau Jr. after the loss #2", verdict("Esau Jr. after the loss #2", esauJr("Esau Jr. after the loss #2")) } }, STRICT)
FINAL[#FINAL + 1] = obsScenario("final J Strawman Keeper leaves", { restart(ISAAC), give(4), give(STRAWMAN), waitFor("Strawman Keeper", function() return helper(KEEPER) ~= nil end),
	giveType(5, KEEPER) }, { { "helpers before the kill", helpersInfo("before the kill") }, { "kill the Keeper", killKeeper }, { "settle", settled },
	{ "where its items went", keeperItems }, { "helpers after the kill", helpersInfo("after the kill") } }, STRICT)
-- The summoned Esau and a Strawman Keeper across Exit & Continue: their Parent, ControllerIndex and rows before and after.
-- The Soul first: its swap wants 2 players, and giveitem goes to a Keeper once one exists.
FINAL[#FINAL + 1] = obsScenario("final N summoned Esau across Continue", { restart(ISAAC), give(4), addCard(Card.CARD_SOUL_JACOB) },
	{ { "Soul of Jacob and Esau", soulJE }, { "give Strawman", give(STRAWMAN) }, { "Strawman Keeper", waitFor("Strawman Keeper", function() return helper(KEEPER) ~= nil end) },
		{ "settle", settled }, { "helpers before the exit", helpersInfo("before the exit") }, continued,
		{ "players after Continue", playerCount }, { "settle 2", settled }, { "helpers after Continue", helpersInfo("after Continue") } },
	{ kind = "large", budget = OBSY_CONTINUE_LIMIT, strict = true })
end)()

-- kind "large": needs the user to exit and Continue; runs last. new = true until it has passed in game (then clear it by hand); set it
-- again whenever its steps or checks change. leftOk = true lets left entries pass the invariant (for a scenario where a player leaves).
local SCENARIOS = {
	{ name = "probes", kind = "small", steps = {
		restart(ISAAC), maxCharges, give(ESAU_JR), esauJr("Esau Jr."), onePress("Esau Jr."),
		give(CLICKER), give(1), clicker, clickerHeld, -- c1 after Clicker, so Clicker's 50% item removal takes c1, not Clicker
		restart(T_LAZ), addCard(Card.CARD_SOUL_JACOB), cardBesideFlip,
		restart(T_LAZ), pocketCharge, flip("Flip"), onePress("Flip"),
	} },
	{ name = "test3", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), look("before ChangePlayerType"), changeType(ISAAC),
		look("after ChangePlayerType", function(ctx, label)
			c4c5(ctx, label)
			local key = keyOf(Isaac.GetPlayer(0))
			expectOne(ctx, label .. " (Isaac owns)", 4, nil, key)
			expectOne(ctx, label .. " (Isaac owns)", 5, nil, key)
			expectN(ctx, label, FLIP, 0)
		end),
	} },
	{ name = "birthright", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), give(BIRTHRIGHT, 2), look("after Birthright", birthrightOwners),
		flip("Flip 1 of 2"), look("after Flip 1", birthrightOwners), flip("Flip 2 of 2"), look("after two Flips", birthrightOwners),
		stage(3), look("on stage 3", birthrightOwners),
	} },
	-- Run 7: the Dead form, number 1, holds c711 from Basement II.
	{ name = "P3", kind = "small", steps = {
		restart(T_LAZ), give(4), stage(2), look("after c4", oneC4),
		give(BIRTHRIGHT, 2), look("after Birthright", function(ctx, label)
			oneC4(ctx, label)
			ctx.dead = keyOf(playerOfType(DEAD_LAZ))
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
	{ name = "P4a", kind = "small", steps = {
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("after c4", oneC4),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", oneC4), esauJr("Esau Jr. 2"), look("after Esau Jr. 2", oneC4),
	} },
	-- Three runs: ChangePlayerType out on the Esau Jr. form, then Esau Jr. again (swap refills its 1 charge, spent by the first press);
	-- a Flip of the Esau Jr. form, whose new Dead form is turned Isaac; and the 29->38 crossing on the Esau Jr. form of a flipped one.
	{ name = "P4c", kind = "small", budget = 600, steps = {
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("before Esau Jr.", origBeforeEsauJr),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", esauJrForm), changeType(ISAAC),
		look("after ChangePlayerType on the form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(0) on the Esau Jr. form")
			expect(ctx, label .. ": player 0 is the form", keyOf(Isaac.GetPlayer(0)), ctx.form)
			origStored(ctx, label)
		end),
		esauJr("Esau Jr. 2"), look("after Esau Jr. 2", function(ctx, label)
			engineInfo(ctx, "after Esau Jr. from the form turned Isaac")
			expect(ctx, label .. ": player 0 is the original", keyOf(Isaac.GetPlayer(0)), ctx.orig)
			expectOne(ctx, label, 4, ctx.floors[1], ctx.orig)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
		restart(T_LAZ), give(4), give(ESAU_JR), stage(2), look("before Esau Jr.", origBeforeEsauJr),
		esauJr("Esau Jr."), look("after Esau Jr.", esauJrForm), flip("Flip of the form"),
		look("after Flip of the form", function(ctx, label)
			engineInfo(ctx, "after a Flip of the Esau Jr. form")
			ctx.dead = keyOf(Isaac.GetPlayer(0))
			expect(ctx, label .. ": a new Dead form", ctx.dead ~= ctx.orig and ctx.dead ~= ctx.form and Isaac.GetPlayer(0):GetPlayerType() == DEAD_LAZ, true)
			expect(ctx, label .. ": form stored", dbg().roster.isSwapped(ctx.form), true)
			origStored(ctx, label)
		end),
		give(ESAU_JR), -- so the original stays revivable (invariant 3) once the Dead form is no Tainted Lazarus
		changeType(ISAAC), look("after ChangePlayerType on the Dead form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(0) on the Esau Jr. form's Dead form")
			expect(ctx, label .. ": form merged", dbg().roster.number(ctx.form), nil)
			origStored(ctx, label)
		end),
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), flip("Flip back"), give(ESAU_JR),
		look("before Esau Jr.", function(ctx, label)
			origBeforeEsauJr(ctx, label)
			for _, e in ipairs(entries()) do
				if e.id == 5 then ctx.dead = e.owner end
			end
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.dead)
		end),
		esauJr("Esau Jr."), look("after Esau Jr.", esauJrForm), changeType(DEAD_LAZ),
		look("after the crossing on the form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(38) on the Esau Jr. form")
			expect(ctx, label .. ": player 0 is the form", keyOf(Isaac.GetPlayer(0)), ctx.form)
			expect(ctx, label .. ": Dead form stored", dbg().roster.isSwapped(ctx.dead), true)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.dead)
			origStored(ctx, label)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
	} },
	-- Numbers are first seen (roster.lua observe), so Jacob 0, Esau 1 and Jacob's Esau Jr. form 2 (run 7's P4b).
	{ name = "S4", kind = "small", steps = {
		restart(JE), give(4), giveEsau(5), give(ESAU_JR), stage(2),
		look("start", function(ctx, label)
			ctx.jacob, ctx.esau = keyOf(Isaac.GetPlayer(0)), keyOf(playerOfType(PlayerType.PLAYER_ESAU))
			jeCopies(ctx, label)
		end),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", function(ctx, label)
			local r, esau = dbg().roster, playerOfType(PlayerType.PLAYER_ESAU)
			ctx.form = keyOf(Isaac.GetPlayer(0))
			expect(ctx, "engine, not ReHUD: Esau's owned c5 after Jacob's Esau Jr. (Q9)", esau and owned(esau, 5), 1)
			jeCopies(ctx, label)
			expect(ctx, label .. ": Jacob swapped", r.isSwapped(ctx.jacob), true)
			expect(ctx, label .. ": numbers Jacob, Esau, form", tostring(r.number(ctx.jacob)) .. "," .. tostring(r.number(ctx.esau)) .. "," .. tostring(r.number(ctx.form)), "0,1,2")
			expect(ctx, label .. ": left entries", leftEntries(), 0)
			expect(ctx, label .. ": characterCount", dbg().tracker.characterCount, 3)
		end),
		esauJr("Esau Jr. 2"), look("after Esau Jr. 2", function(ctx, label)
			jeCopies(ctx, label)
			expect(ctx, label .. ": player 0 is Jacob", keyOf(Isaac.GetPlayer(0)), ctx.jacob)
			expect(ctx, label .. ": form swapped", dbg().roster.isSwapped(ctx.form), true)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
	} },
	{ name = "P1", kind = "small", steps = {
		restart(ISAAC), give(4), give(4), stage(2), look("before Soul of Jacob and Esau", twoC4),
		addCard(Card.CARD_SOUL_JACOB), soulJE, look("after Soul of Jacob and Esau", twoC4),
		-- ReHUD 2.8 lists the summoned Esau (user decision 2026-11-22): his c1 under him.
		giveEsau(1), look("after Esau c1", function(ctx, label) twoC4(ctx, label) expectN(ctx, label, 1, 1, nil, keyOf(playerOfType(PlayerType.PLAYER_ESAU))) end),
		stage(3), look("on stage 3", twoC4),
	} },
	{ name = "P2", kind = "small", steps = {
		restart(JE), give(4), give(4), give(4), give(4), giveEsau(4), give(CLICKER), stage(2), look("start"), clickerLoop,
	} },
	-- One entry per copy, by kind (clocked: wisps), floors kept; a lost copy takes the oldest entry of its kind.
	{ name = "S1", kind = "small", steps = {
		restart(CAIN), look("start", function(ctx, label)
			own(ctx, label, 2, 46, ctx.floors[1], false) -- owned + innate
			expectCount(ctx, label, 0, 46, nil, true)
		end),
		give(4), stage(2), give(4), look("two c4", function(ctx, label)
			own(ctx, label, 1, 4, ctx.floors[1], false)
			own(ctx, label, 1, 4, ctx.floors[2], false)
		end),
		wisp(4), look("c4 wisp", function(ctx, label)
			own(ctx, label, 2, 4, nil, false)
			own(ctx, label, 1, 4, ctx.floors[2], true)
		end),
		stage(3), engineWisps("after stage (Q3)", 4, 1), wisp(4), look("second c4 wisp", function(ctx, label)
			own(ctx, label, 1, 4, ctx.floors[2], true)
			own(ctx, label, 1, 4, ctx.floors[3], true)
		end),
		killWisp(4), look("one c4 wisp killed", function(ctx, label)
			own(ctx, label, 1, 4, nil, true)
			own(ctx, label, 1, 4, ctx.floors[3], true)
			own(ctx, label, 2, 4, nil, false)
		end),
		remove(4), look("c4 removed", function(ctx, label)
			own(ctx, label, 1, 4, nil, false)
			own(ctx, label, 1, 4, ctx.floors[2], false)
			own(ctx, label, 1, 4, ctx.floors[3], true)
		end),
		killWisp(4), look("last c4 wisp killed", function(ctx, label)
			own(ctx, label, 0, 4, nil, true)
			own(ctx, label, 1, 4, ctx.floors[2], false)
			own(ctx, label, 2, 46, ctx.floors[1], false)
		end),
	} },
	-- Zodiac and 3 Dollar Bill copies are clocked. Settled before each grant, so neither is learned as innate.
	{ name = "S1b", kind = "small", steps = {
		restart(ISAAC), look("start"), give(392), zodiacOn("on the floor given", 30), stage(2), zodiacOn("on stage 2"),
		look("Zodiac", function(ctx, label)
			expectCount(ctx, label, 1, ctx.zodiac, ctx.zodiacFloor, true)
			expectCount(ctx, label, 0, ctx.zodiac, nil, false)
			expectCount(ctx, label, 1, 392, ctx.floors[1], false)
		end),
		stage(3), zodiacOn("on stage 3"), look("Zodiac on stage 3", function(ctx, label) -- Q2
			if ctx.zodiac == ctx.zodiacOld then
				table.insert(ctx.notes, "Zodiac rolled the same item")
				return expectCount(ctx, label, 1, ctx.zodiac, nil, true)
			end
			expectCount(ctx, label, 0, ctx.zodiacOld)
			expectCount(ctx, label, 1, ctx.zodiac, ctx.floors[3], true)
		end),
		restart(ISAAC), look("before 3 Dollar Bill"), give(191), grant3DB, listed,
		look("3 Dollar Bill", function(ctx, label) expectCount(ctx, label, 0, ctx.grant, nil, false) end),
		grant3DB, listed, look("next 3 Dollar Bill grant", function(ctx, label)
			if Isaac.GetPlayer(0):GetCollectibleNum(ctx.grantOld, false) > 0 then return table.insert(ctx.notes, "3 Dollar Bill still grants c" .. ctx.grantOld) end
			expectCount(ctx, label, 0, ctx.grantOld, nil, true)
		end),
	} },
	-- ChangePlayerType re-settles: the new type's innate c46 is learned, the wisp and the Zodiac copy stay clocked.
	{ name = "S2", kind = "small", steps = {
		restart(ISAAC), look("start"), give(392), stage(2), zodiacOn("on stage 2"), wisp(46),
		look("Zodiac and a c46 wisp", function(ctx, label)
			own(ctx, label, 1, 46, nil, true)
			own(ctx, label, 0, 46, nil, false)
			own(ctx, label, 1, ctx.zodiac, nil, true)
		end),
		changeType(CAIN), look("as Cain", function(ctx, label)
			own(ctx, label, 1, 46, nil, false) -- innate
			own(ctx, label, 1, 46, nil, true) -- wisp
			local z = Isaac.GetPlayer(0):GetZodiacEffect()
			P("INFO", ctx.name, "Zodiac item after ChangePlayerType", z, "was", ctx.zodiac) -- Q5
			if z == 0 then return table.insert(ctx.notes, "ChangePlayerType dropped the Zodiac item") end
			own(ctx, label, 1, z, nil, true)
			own(ctx, label, 0, z, nil, false)
		end),
		killWisp(46), look("c46 wisp killed", function(ctx, label)
			own(ctx, label, 1, 46, nil, false)
			own(ctx, label, 0, 46, nil, true)
		end),
	} },
	{ name = "S3", kind = "small", budget = 200, steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), give(CLICKER), stage(3),
		look("before Clicker", function(ctx, label)
			for _, e in ipairs(entries()) do
				if e.id == 4 then ctx.stored = e.owner end
			end
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.stored)
			own(ctx, label, 1, 5, ctx.floors[2])
		end),
		clicker, look("after Clicker", afterTLazClicker),
	} },
	-- R1: ChangePlayerType(29) on the Dead form, with the 29 form stored, merges the two and keeps Flip; the next Flip brings a fresh Dead form (run 8).
	{ name = "r1", kind = "small", budget = 250, steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5),
		look("before", function(ctx, label)
			for _, e in ipairs(entries()) do
				if e.id == 4 then ctx.stored = e.owner end
			end
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.stored)
		end),
		changeType(T_LAZ), look("after ChangePlayerType", r1Merged), flip("Flip after"), look("after Flip", r1Fresh),
	} },
	-- r1 the other way: the 29 form turned 38 with the Dead form stored (unobserved; expects r1's merge).
	{ name = "r1 mirror", kind = "small", budget = 200, steps = {
		restart(T_LAZ), give(4), stage(2), flip("Flip"), give(5), flip("Flip back"),
		look("before", function(ctx, label)
			ctx.active, ctx.activeSeed = keyOf(Isaac.GetPlayer(0)), seedOf(Isaac.GetPlayer(0))
			for _, e in ipairs(entries()) do
				if e.id == 5 then ctx.stored = e.owner end
			end
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.active)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.stored)
		end),
		changeType(DEAD_LAZ), look("after ChangePlayerType", mirrorMerged),
	} },
	-- The Flip comes about 5 updates after restart, so the 29 form is stored mid-settle (the 20ca1f1 path).
	{ name = "continue", kind = "large", new = true, steps = continueSteps() },
	-- The settle wait first, so the 29 form is stored settled, as in real play.
	{ name = "continue settled", kind = "large", new = true, steps =continueSteps(look("before Flip", oneC4)) },
	-- Copy kinds survive a continue, and Cain's saved innate row means no second settle.
	{ name = "L1", kind = "large", new = true, steps = {
		restart(CAIN), look("start"), give(4), wisp(4), stage(2), wisp(46), look("before exit", copyKinds), exitAndContinue(),
		function(ctx) expect(ctx, "no re-settle after continue", dbg().roster.isSettling(keyOf(Isaac.GetPlayer(0))), false) end,
		engineWisps("after continue", 4, 1), engineWisps("after continue", 46, 1), look("after continue", copyKinds),
	} },
}

-- The final scenarios run after r1 mirror, before the large ones.
for i, s in ipairs(SCENARIOS) do
	if s.name == "r1 mirror" then
		for k, f in ipairs(FINAL) do table.insert(SCENARIOS, i + k, f) end
		break
	end
end

-- The obs scenarios run after P4c, the scenario they observe the engine for.
for i, s in ipairs(SCENARIOS) do
	if s.name == "P4c" then
		for k, o in ipairs(OBS) do table.insert(SCENARIOS, i + k, o) end
		break
	end
end

return SCENARIOS
