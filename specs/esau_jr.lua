-- Esau Jr. presses and the characters they store and bring back (plan S4). An Esau Jr. copy's first use creates a new character, its
-- Esau Jr. character; each test starts from its own fresh run (fixture).
local P = include("scripts.log").P
local engine = include("scripts.game")
local seedOf, ofType, owned, slots, itemCounts, countsText = engine.seedOf, engine.ofType, engine.owned, engine.slots, engine.itemCounts,
	engine.countsText
local rehud = include("scripts.rehud")
local dbg, keyOf, leftEntries = rehud.dbg, rehud.keyOf, rehud.leftEntries
local console = include("scripts.console")
local fresh, give, remove, stage = console.fresh, console.give, console.remove, console.stage
local steps_ = include("scripts.steps")
local giveEsau, changeType, info, stepOff, onlyIf, holdsJr = steps_.giveEsau, steps_.changeType, steps_.info, steps_.stepOff, steps_.onlyIf,
	steps_.holdsJr
local manual = include("scripts.manual")
local dropByHand, pickByHand, continued = manual.dropByHand, manual.pickByHand, manual.continued
local assertions = include("scripts.assert")
local expect, expectCount, oneC4, pre = assertions.expect, assertions.expectCount, assertions.oneC4, assertions.pre
local record = include("scripts.record")
local verdict, ids, slotsNow, pocketHeld, typeNow, playerCount, startChecked = record.verdict, record.ids, record.slotsNow, record.pocketHeld,
	record.typeNow, record.playerCount, record.startChecked
local settle = include("scripts.settle")
local look, settled, lookC = settle.look, settle.settled, settle.lookC
local press = include("scripts.press")
local flip, esauJr, clicker, obsClicker, birthrightFlip, dropPress, toSlot, deadFirst, swapCopies = press.flip, press.esauJr, press.clicker,
	press.obsClicker, press.birthrightFlip, press.dropPress, press.toSlot, press.deadFirst, press.swapCopies
local jrSteps = include("scripts.esau_jr_steps")
local regiveEsauJr, jrFirst, jrAgain, jrTwice, giveClicker, rememberOriginal, rememberForm, controlPresses, replaceEsauJr, useClickerEffect,
	jrPair, flipV, charPresses, esauLoses = jrSteps.regiveEsauJr, jrSteps.jrFirst, jrSteps.jrAgain, jrSteps.jrTwice, jrSteps.giveClicker,
	jrSteps.rememberOriginal, jrSteps.rememberForm, jrSteps.controlPresses, jrSteps.replaceEsauJr, jrSteps.useClickerEffect, jrSteps.jrPair,
	jrSteps.flipV, jrSteps.charPresses, jrSteps.esauLoses
local fixtures = include("scripts.fixtures")
local fixture, holding, TLAZ_JR, TLAZ_FLIPS = fixtures.fixture, fixtures.holdingJr, fixtures.TLAZ_JR, fixtures.TLAZ_FLIPS
local snapshot = include("scripts.snapshot")
local test, perCharacter = snapshot.test, snapshot.perCharacter
local characters = include("scripts.characters")
local track, named, who, whoInfo, merged = characters.track, characters.named, characters.who, characters.whoInfo, characters.merged
local enums = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT, YUM_HEART, SCHOOLBAG = enums.FLIP, enums.ESAU_JR, enums.CLICKER, enums.BIRTHRIGHT, enums.YUM_HEART,
	enums.SCHOOLBAG
local T_LAZ, DEAD_T_LAZ, JACOB, ISAAC, T_FORGOTTEN, ESAU, PRIMARY, SECONDARY = enums.T_LAZ, enums.DEAD_T_LAZ, enums.JACOB, enums.ISAAC,
	enums.T_FORGOTTEN, enums.ESAU, enums.PRIMARY, enums.SECONDARY

local game = Game()

-- Snapshot test kinds: their tags, and whether a step is strict (obsx, obsy, final I-M): it has a limit, and its miss ends the test, so
-- later presses cannot run on the wrong setup; a soft one (obs) is logged and skipped.
local SOFT = { tags = { "esau_jr", "rehud", "obs" } }
local OBSX = { tags = { "esau_jr", "rehud", "obs", "obsx" }, strict = true }
local OBSY_A = { tags = { "esau_jr", "rehud", "obs", "obsy-a" }, strict = true }
local OBSY_B = { tags = { "esau_jr", "rehud", "obs", "obsy-b" }, strict = true }
local FINAL = { tags = { "esau_jr", "rehud", "rehud-2.8" }, strict = true }
local function snapshotTest(kind, name, f, steps) return test(name, kind.tags, f, steps, kind) end

-- Jacob's c4 and Esau's c5, both from floor 1, each under its owner.
local function jeCopies(ctx, label)
	expectCount(ctx, label, 1, 4, ctx.floors[1], false, ctx.jacob)
	expectCount(ctx, label, 1, 5, ctx.floors[1], false, ctx.esau)
end

-- F: what Clicker out of a Tainted Lazarus character gave the live character, and which stored Flip twins' items it got (marked gone: merged).
local function beforeClicker(ctx) track() ctx.pre = itemCounts(Isaac.GetPlayer(0)) end
local ACTIVES = { [ESAU_JR] = true, [FLIP] = true, [CLICKER] = true, [SCHOOLBAG] = true }
local function clickerMerges(ctx)
	track()
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
			-- Only a Flip twin merges into the live character (roster.lua); an Esau Jr. character stays stored (user decision 2026-11-22).
			if #hit > 0 and c.storedBy == FLIP then merged(c)
			elseif #hit > 0 then table.insert(ctx.notes, "engine moved stored Esau Jr. character " .. c.name .. "'s items (unobserved)") end
		end
	end
end

local CHECKED = { "esau_jr", "rehud" }
local CHECKED_FINAL = { "esau_jr", "rehud", "rehud-2.8" }

local tests = {
	{ name = "Tainted Lazarus keeps one c4 through two Esau Jr. presses", tags = CHECKED,
		fixture = fixtures.TLAZ_JR_FLOOR_2, steps = {
		look("after c4", oneC4), esauJr("Esau Jr. 1"), look("after Esau Jr. 1", oneC4), esauJr("Esau Jr. 2"), look("after Esau Jr. 2", oneC4),
	} },
	snapshotTest(SOFT, "Esau Jr. character turned Dead Tainted Lazarus, then Isaac, presses back", TLAZ_JR,
		{ jrFirst(), { "ChangePlayerType 38", changeType(DEAD_T_LAZ) }, { "ChangePlayerType 0", changeType(ISAAC) }, jrAgain() }),
	snapshotTest(SOFT, "Esau Jr. character turned Isaac presses back", TLAZ_JR, { jrFirst(), { "ChangePlayerType 0", changeType(ISAAC) }, jrAgain() }),
	snapshotTest(SOFT, "Esau Jr. character flips there and back, then presses back", TLAZ_JR, { jrFirst(), { "pocket of the form", pocketHeld },
		{ "Flip of the form", flip("Flip of the form") }, { "Flip back", flip("Flip back") }, jrAgain() }),
	snapshotTest(SOFT, "Esau Jr. character of a flipped-back Tainted Lazarus turned Dead Tainted Lazarus", TLAZ_JR, { { "Flip", flip("Flip") },
		{ "give c5", give(5) }, { "Flip back", flip("Flip back") }, { "Esau Jr.", esauJr("Esau Jr.") }, { "ChangePlayerType 38", changeType(DEAD_T_LAZ) },
		jrAgain(), { "Flip A", flip("Flip A") }, { "re-give c703 #2", regiveEsauJr() }, { "Esau Jr. #2", esauJr("Esau Jr. #2") },
		{ "Flip of the Esau Jr. form", flip("Flip of the Esau Jr. form") } }),
	snapshotTest(SOFT, "Birthright given and removed after Esau Jr.", TLAZ_JR, { jrFirst(), { "give Birthright", give(BIRTHRIGHT) },
		{ "remove Birthright", remove(BIRTHRIGHT) } }),
	snapshotTest(SOFT, "Esau Jr. with Birthright held from the start",
		{ name = "Tainted Lazarus holding Esau Jr. and Birthright", setup = { fresh(T_LAZ), give(4), give(ESAU_JR), give(BIRTHRIGHT) } },
		{ jrFirst(), jrAgain() }),
	snapshotTest(SOFT, "Clicker on the Esau Jr. character, then more presses", TLAZ_JR, { jrFirst(), { "give Clicker", give(CLICKER) },
		{ "Clicker", clicker }, { "Clicker roll", typeNow }, { "settle", settled }, jrAgain(),
		{ "re-give c703 #3", regiveEsauJr() }, { "Esau Jr. #3", esauJr("Esau Jr. #3") },
		{ "re-give c703 #4", regiveEsauJr() }, { "Esau Jr. #4", esauJr("Esau Jr. #4") } }),
	snapshotTest(SOFT, "Birthright on the Esau Jr. character, then it presses back", TLAZ_JR, { jrFirst(), { "give Birthright", give(BIRTHRIGHT) },
		{ "settle", settled }, jrAgain() }),
	snapshotTest(SOFT, "Esau Jr. character turned Tainted Forgotten presses back", TLAZ_JR, { jrFirst(), { "ChangePlayerType 35", changeType(T_FORGOTTEN) },
		{ "settle", settled }, jrAgain(), { "re-give c703 #3", regiveEsauJr() }, { "Esau Jr. #3", esauJr("Esau Jr. #3") } }),
	snapshotTest(SOFT, "Tainted Lazarus flips after an Esau Jr. round trip", TLAZ_JR, { jrFirst(), jrAgain(), { "pocket before Flip on A", pocketHeld },
		{ "Flip on A", flip("Flip on A") } }),
	snapshotTest(SOFT, "Birthright on the Esau Jr. character, then Flip", TLAZ_JR, { jrFirst(), { "give Birthright", give(BIRTHRIGHT) },
		{ "settle", settled }, { "Flip", flip("Flip") } }),
	snapshotTest(OBSX, "Clicker on Tainted Lazarus back from its Esau Jr. character", TLAZ_JR, { jrFirst(), jrAgain(), giveClicker(),
		{ "Clicker", obsClicker }, jrTwice() }),
	snapshotTest(OBSX, "Clicker on the Esau Jr. character after its Flip", TLAZ_JR, { jrFirst(), { "Flip of the form", flip("Flip of the form") },
		giveClicker(), { "Clicker", obsClicker }, jrTwice() }),
	snapshotTest(OBSX, "Clicker on a Birthright twin of the Esau Jr. character", TLAZ_JR, { jrFirst(), { "give Birthright", give(BIRTHRIGHT, 2) },
		{ "select type-29 twin", birthrightFlip, deadFirst },
		giveClicker(), { "Clicker by type 29", function(ctx)
			if not ctx.t then
				pre(Isaac.GetPlayer(0):GetPlayerType() == T_LAZ and ofType(DEAD_T_LAZ), "type 29 in player 0 with the type-38 Birthright twin present")
			end
			return obsClicker(ctx)
		end }, jrTwice() }),
	snapshotTest(OBSX, "Clicker on Isaac's Esau Jr. character", holding("Isaac", ISAAC), { jrFirst(), giveClicker(), { "Clicker", obsClicker }, jrTwice() }),
	snapshotTest(OBSX, "Tainted Lazarus's Esau Jr. character loses Esau Jr. and gets it back", TLAZ_JR, {
		{ "record A", rememberOriginal }, jrFirst(), replaceEsauJr(), controlPresses() }),
	snapshotTest(OBSX, "Tainted Lazarus's Esau Jr. character uses Clicker's effect", TLAZ_JR, {
		{ "record A", rememberOriginal }, jrFirst(), { "give c1", give(1) }, { "use Clicker effect", useClickerEffect }, controlPresses() }),
	snapshotTest(OBSX, "Isaac's Esau Jr. character loses Esau Jr. and gets it back", holding("Isaac", ISAAC), {
		{ "record A", rememberOriginal }, jrFirst(), replaceEsauJr(), controlPresses() }),
	snapshotTest(OBSX, "Tainted Lazarus loses Esau Jr. after a round trip, returns recorded", TLAZ_JR, {
		{ "record A", rememberOriginal }, jrFirst(), { "record B", rememberForm },
		{ "Esau Jr. back to A", esauJr("Esau Jr. back to A") },
		{ "verify A returned", function(ctx) pre(seedOf(Isaac.GetPlayer(0)) == ctx.originalSeed, "original A in player 0") end },
		replaceEsauJr(), controlPresses() }),
	-- Does A return after its Esau Jr. character held Esau Jr. in the Schoolbag's second slot? Variant: a real Clicker press meanwhile.
	snapshotTest(OBSY_A, "Esau Jr. through the Schoolbag's second slot", holding("Isaac", ISAAC), { jrPair("Esau Jr. #1"),
		{ "give Schoolbag", give(SCHOOLBAG) }, { "give c45", give(YUM_HEART) }, { "slots after c45", slotsNow },
		{ "Esau Jr. to secondary", toSlot("Esau Jr. to secondary", SECONDARY, ESAU_JR) },
		{ "Esau Jr. to primary", toSlot("Esau Jr. to primary", PRIMARY, ESAU_JR) }, jrPair("Esau Jr. #2"), jrPair("Esau Jr. #3") }),
	snapshotTest(OBSY_A, "Esau Jr. through the Schoolbag with a Clicker press", holding("Isaac", ISAAC), { jrPair("Esau Jr. #1"),
		{ "give Schoolbag", give(SCHOOLBAG) }, giveClicker(), { "slots after Clicker", slotsNow },
		{ "Clicker to primary", toSlot("Clicker to primary", PRIMARY, CLICKER) }, { "Clicker", verdict("Clicker", obsClicker) },
		{ "slots after the Clicker press", slotsNow }, { "Esau Jr. to primary", toSlot("Esau Jr. to primary", PRIMARY, ESAU_JR) },
		jrPair("Esau Jr. #2"), jrPair("Esau Jr. #3") }),
	-- Once A is lost, does A's Dead Tainted Lazarus X (or A) ever come back through B's Flips or presses?
	snapshotTest(OBSY_A, "Esau Jr. character's Flips after losing Esau Jr.", TLAZ_JR, { { "Flip", flipV("Flip") }, { "Flip back", flipV("Flip back") },
		jrPair("Esau Jr. #1"), replaceEsauJr(), { "Flip of B", flipV("Flip of B") }, { "Flip back to B", flipV("Flip back to B") },
		jrPair("Esau Jr. #2"), jrPair("Esau Jr. #3") }),
	-- Clicker's effect with Esau Jr. kept, on a character other than Lazarus.
	snapshotTest(OBSY_A, "Isaac's Esau Jr. character uses Clicker's effect", holding("Isaac", ISAAC), { jrPair("Esau Jr. #1"), { "give c1", give(1) },
		{ "use Clicker effect", useClickerEffect }, jrPair("Esau Jr. #2"), jrPair("Esau Jr. #3") }),
	snapshotTest(OBSY_A, "Esau Jr. presses by Jacob", holding("Jacob", JACOB), charPresses()),
	snapshotTest(OBSY_A, "Esau Jr. presses by Esau", { name = "Esau holding Esau Jr.", setup = { fresh(JACOB), give(4), giveEsau(ESAU_JR) } },
		charPresses({ index = 1 }, nil, esauLoses)),
	snapshotTest(OBSY_A, "Esau Jr. presses by The Forgotten and The Soul", holding("The Forgotten", PlayerType.PLAYER_THEFORGOTTEN), charPresses(nil, {
		jrPair("Esau Jr. as Forgotten #1"), jrPair("Esau Jr. as Forgotten #2"),
		{ "switch to the Soul", dropPress("switch to the Soul", function(p) return p:GetPlayerType() == PlayerType.PLAYER_THESOUL end,
			"ChangePlayerType 17", function(p) p:ChangePlayerType(PlayerType.PLAYER_THESOUL) end) } })),
	snapshotTest(OBSY_A, "Esau Jr. presses by Tainted Forgotten", holding("Tainted Forgotten", T_FORGOTTEN), charPresses({ index = 0, any = true })),
	snapshotTest(OBSY_A, "Esau Jr. presses by Lazarus Risen", holding("Lazarus", PlayerType.PLAYER_LAZARUS),
		charPresses(nil, { { "ChangePlayerType 11", changeType(PlayerType.PLAYER_LAZARUS2) } })),
	-- Locked on save slot 1 (README): a restart that never gives the type ends the test with an INFO "character locked?" line.
	snapshotTest(OBSY_B, "Esau Jr. presses by Tainted Jacob", holding("Tainted Jacob", PlayerType.PLAYER_JACOB_B), charPresses()),
	snapshotTest(OBSY_B, "Esau Jr. presses by Eden", holding("Eden", PlayerType.PLAYER_EDEN), charPresses()),
	-- Numbers are first seen (roster.lua observe), so Jacob 0, Esau 1 and Jacob's Esau Jr. character 2 (run 7's P4b).
	{ name = "Jacob's Esau Jr. character beside Esau gets character number 2", tags = CHECKED, fixture = fixture("Jacob holding Esau Jr. on floor 2",
		{ fresh(JACOB), give(4), giveEsau(5), give(ESAU_JR), stage(2) }, JACOB), steps = {
		look("start", function(ctx, label)
			ctx.jacob, ctx.esau = keyOf(Isaac.GetPlayer(0)), keyOf(ofType(ESAU))
			jeCopies(ctx, label)
		end),
		esauJr("Esau Jr. 1"), look("after Esau Jr. 1", function(ctx, label)
			local r, esau = dbg().roster, ofType(ESAU)
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
	-- Two copies, each keeping the character it last swapped out; Schoolbag holds both on A.
	{ name = "two Esau Jr. copies each bring back their own character", tags = CHECKED_FINAL, limit = 350, fixture = holding("Isaac", ISAAC), steps = {
		named("Isaac"), lookC("start"),
		esauJr("copy 1: Isaac -> A"), named("A"), give(5), give(SCHOOLBAG), give(ESAU_JR), info("A's slots", slots), lookC("A with two copies"),
		esauJr("copy 2: A -> B"), named("B"), give(6), lookC("B"),
		esauJr("copy 2: B -> A"), who("A"), lookC("A back"),
		swapCopies(), esauJr("copy 1: A -> Isaac"), who("Isaac"), lookC("Isaac back"),
		esauJr("copy 1: Isaac -> A"), who("A"), lookC("A again"),
		swapCopies(), esauJr("copy 2: A -> B"), who("B"), lookC("B again"),
	} },
	-- A drops Esau Jr. on a pedestal and takes it back; its press brings Isaac back (console 2026-11-22).
	{ name = "Esau Jr. dropped and picked up brings Isaac back", tags = { "esau_jr", "rehud", "rehud-2.8", "walk" }, limit = 1100,
		fixture = holding("Isaac", ISAAC), steps = {
		named("Isaac"), esauJr("Isaac -> A"), named("A"), give(5), lookC("A"),
		dropByHand, lookC("Esau Jr. on the pedestal"), pickByHand, stepOff, lookC("Esau Jr. picked back up"),
		esauJr("A presses the picked-up copy"), who("Isaac"), lookC("Isaac back"),
	} },
	-- LJ shares D's seed; each keeps its own character number and items through Flips and presses.
	{ name = "Tainted Lazarus's Esau Jr. character keeps its own items through Flips and presses", tags = CHECKED_FINAL, limit = 350,
		fixture = TLAZ_FLIPS, steps = {
		flip("Flip by D"), whoInfo("Flip by D"), lookC("after Flip by D"),
		onlyIf("player 0 holds no Esau Jr.", holdsJr, esauJr("Esau Jr. by player 0")), whoInfo("Esau Jr. by player 0"), lookC("after Esau Jr."),
		onlyIf("player 0 holds no Esau Jr.", holdsJr, esauJr("Esau Jr. again")), whoInfo("Esau Jr. again"), lookC("after Esau Jr. again"),
	} },
	-- Recon: Flip twins change after Esau Jr. (LJ <-> D, then DJ <-> LJ), then Clicker out of the live character; ReHUD sets each twin
	-- once (roster.lua partnerOf), so a failure here is expected. TRACE lines log the engine and ReHUD every update from its restart on,
	-- setup included, and none of the previous test's run.
	{ name = "Flip twins change after Esau Jr., then Clicker", tags = { "esau_jr", "rehud", "rehud-2.8", "opt-in" }, limit = 450,
		fixture = fixture(TLAZ_FLIPS.name .. ", traced", { TLAZ_FLIPS.setup[1], startChecked, { table.unpack(TLAZ_FLIPS.setup, 2) } }, DEAD_T_LAZ), steps = {
		give(ESAU_JR), esauJr("Esau Jr. D -> DJ"), named("DJ"), give(7), lookC("DJ"),
		flip("Flip DJ -> LJ"), who("LJ"), lookC("LJ back"), flip("Flip LJ -> DJ"), who("DJ"), lookC("DJ back"),
		give(SCHOOLBAG), give(CLICKER), give(1), beforeClicker, clicker, clickerMerges, lookC("after Clicker"),
	} },
	-- Recon: cf965b0 counts a newcomer holding Esau Jr. of the index's previous type as a swap even when the player count drops, and
	-- stores a vanished character whose twin is stored; this logs what the engine does to the twins.
	snapshotTest(FINAL, "Esau Jr. and Flip with Birthright twins", fixtures.TLAZ_JR_TWINS, {
		{ "players", playerCount }, { "Esau Jr.", verdict("Esau Jr.", esauJr("Esau Jr.")) }, { "players after Esau Jr.", playerCount }, { "settle", settled },
		{ "Esau Jr. back", verdict("Esau Jr. back", esauJr("Esau Jr. back")) }, { "players after Esau Jr. back", playerCount }, { "settle 2", settled },
		{ "Flip", verdict("Flip", flip("Flip")) }, { "players after Flip", playerCount } }),
	-- Recon (review questions 2026-11-22): GetPtrHash in the flipped cross and on a Flip of an Esau Jr. character, and whether A's stored
	-- Dead Tainted Lazarus returns when A (type 38) flips; the hash of a character that comes back on a stored one's seed with other items.
	snapshotTest(FINAL, "Esau Jr. character of a flipped-back Tainted Lazarus flips, then turns Dead Tainted Lazarus", TLAZ_JR, {
		{ "Flip", verdict("Flip", flip("Flip")) }, { "give c5", give(5) },
		{ "Flip back", verdict("Flip back", flip("Flip back")) }, { "Esau Jr.", verdict("Esau Jr.", esauJr("Esau Jr.")) },
		{ "Flip of the Esau Jr. form", verdict("Flip of the Esau Jr. form", flip("Flip of the Esau Jr. form")) },
		{ "Flip back to the form", verdict("Flip back to the form", flip("Flip back to the form")) }, { "ids of the form", ids("of the form") },
		{ "ChangePlayerType 38", changeType(DEAD_T_LAZ) }, jrAgain(), { "ids after the original returned", ids("after the original returned") },
		{ "Flip A (type 38)", verdict("Flip A (type 38)", flip("Flip A (type 38)")) }, { "ids after Flip A", ids("after Flip A") } }),
	snapshotTest(FINAL, "Tainted Lazarus loses Esau Jr. after a round trip, verdict per press", TLAZ_JR, { jrFirst(),
		{ "Esau Jr. back to A", verdict("Esau Jr. back to A", esauJr("Esau Jr. back to A")) },
		replaceEsauJr(), { "Esau Jr. after the loss", verdict("Esau Jr. after the loss", esauJr("Esau Jr. after the loss")) },
		{ "Esau Jr. after the loss #2", verdict("Esau Jr. after the loss #2", esauJr("Esau Jr. after the loss #2")) } }),
}
-- Recon: each character's Esau Jr. character, its return, and both across Exit & Continue.
perCharacter(tests, "esau_jr", "Esau Jr. press, press, Exit & Continue, press", fixtures.RECON_CHARACTERS,
	function(c) return fixtures.character(c, { give(ESAU_JR) }, fixtures.owns(ESAU_JR)) end,
	function(c) return { jrPair("Esau Jr. #1", c.who), jrPair("Esau Jr. #2", c.who), continued, jrPair("Esau Jr. #3", c.who) } end, true)

return { name = "esau_jr", tests = tests }
