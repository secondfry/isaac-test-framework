-- ReHUD 2.8 regressions, named by their old ids (plan S4): Tainted Lazarus's stored forms through Clicker, ChangePlayerType and Esau Jr.
local P = include("scripts.log").P
local engine = include("scripts.game")
local seedOf, wispsOf = engine.seedOf, engine.wispsOf
local rehud = include("scripts.rehud")
local dbg, keyOf, countEntries, leftEntries, ownerOf = rehud.dbg, rehud.keyOf, rehud.countEntries, rehud.leftEntries, rehud.ownerOf
local console = include("scripts.console")
local give, stage = console.give, console.stage
local changeType = include("scripts.steps").changeType
local assertions = include("scripts.assert")
local expect, expectN, expectOne, expectCount, own, noneLeft = assertions.expect, assertions.expectN, assertions.expectOne,
	assertions.expectCount, assertions.own, assertions.noneLeft
local look = include("scripts.settle").look
local press = include("scripts.press")
local flip, esauJr, clicker = press.flip, press.esauJr, press.clicker
local fixtures = include("scripts.fixtures")
local FLIPPED, HOLDS_JR = fixtures.FLIPPED, fixtures.TLAZ_JR_FLOOR_2
local ids = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, ISAAC, T_LAZ, DEAD_T_LAZ = ids.FLIP, ids.ESAU_JR, ids.CLICKER, ids.ISAAC, ids.T_LAZ, ids.DEAD_T_LAZ

local game = Game()
local TAGS = { "regressions", "rehud", "rehud-2.8" }

-- After Clicker out of Tainted Lazarus (S3): every c4 (floor 1, the stored form's) and c5 (floor 2, the Dead form's) the engine counts,
-- wisps aside, is listed once, floor kept, under the player holding it; the stored form is forgotten. A roll into the other form's type
-- keeps Flip and starts a fresh, unseen form (run 8), so ReHUD's count of characters is not checked then.
local function afterTLazClicker(ctx, label)
	local t = Isaac.GetPlayer(0):GetPlayerType()
	P("INFO", ctx.name, "Clicker rolled type", t) -- Q7
	local lazarus = t == T_LAZ or t == DEAD_T_LAZ
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
	expect(ctx, label .. ": entries of the new form", countEntries(function(e) return e.owner == key end), 1)
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
-- and a different outcome fails the assertions. ctx.orig: the Esau Jr. presser; ctx.form: the Esau Jr. form; ctx.dead: a Flip partner.
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
	ctx.orig = keyOf(Isaac.GetPlayer(0))
	expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.orig)
end

-- Limits: P4c's 600 updates shared by its three parts, as when it played them in one test.
return { name = "regressions", tests = {
	-- ChangePlayerType out on the Esau Jr. form, then Esau Jr. again (the swap refills its 1 charge, spent by the first press).
	{ name = "(P4c 1) Esau Jr. character turned Isaac", tags = TAGS, limit = 200, fixture = HOLDS_JR, steps = {
		look("before Esau Jr.", origBeforeEsauJr), esauJr("Esau Jr. 1"), look("after Esau Jr. 1", esauJrForm), changeType(ISAAC),
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
	} },
	-- A Flip of the Esau Jr. form, whose new Dead form is turned Isaac.
	{ name = "(P4c 2) Flip of the Esau Jr. character", tags = TAGS, limit = 200, fixture = HOLDS_JR, steps = {
		look("before Esau Jr.", origBeforeEsauJr), esauJr("Esau Jr."), look("after Esau Jr.", esauJrForm), flip("Flip of the form"),
		look("after Flip of the form", function(ctx, label)
			engineInfo(ctx, "after a Flip of the Esau Jr. form")
			ctx.dead = keyOf(Isaac.GetPlayer(0))
			expect(ctx, label .. ": a new Dead form", ctx.dead ~= ctx.orig and ctx.dead ~= ctx.form and Isaac.GetPlayer(0):GetPlayerType() == DEAD_T_LAZ, true)
			expect(ctx, label .. ": form stored", dbg().roster.isSwapped(ctx.form), true)
			origStored(ctx, label)
		end),
		give(ESAU_JR), -- so the original stays revivable (invariant 3) once the Dead form is no Tainted Lazarus
		changeType(ISAAC), look("after ChangePlayerType on the Dead form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(0) on the Esau Jr. form's Dead form")
			expect(ctx, label .. ": form merged", dbg().roster.number(ctx.form), nil)
			origStored(ctx, label)
		end),
	} },
	-- The 29->38 crossing on the Esau Jr. form of a flipped one.
	{ name = "(P4c 3) crossing on a flipped one's Esau Jr. character", tags = TAGS, limit = 200, fixture = FLIPPED, steps = {
		flip("Flip back"), give(ESAU_JR),
		look("before Esau Jr.", function(ctx, label)
			origBeforeEsauJr(ctx, label)
			ctx.dead = ownerOf(5)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.dead)
		end),
		esauJr("Esau Jr."), look("after Esau Jr.", esauJrForm), changeType(DEAD_T_LAZ),
		look("after the crossing on the form", function(ctx, label)
			engineInfo(ctx, "after ChangePlayerType(38) on the Esau Jr. form")
			expect(ctx, label .. ": player 0 is the form", keyOf(Isaac.GetPlayer(0)), ctx.form)
			expect(ctx, label .. ": Dead form stored", dbg().roster.isSwapped(ctx.dead), true)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.dead)
			origStored(ctx, label)
			expect(ctx, label .. ": left entries", leftEntries(), 0)
		end),
	} },
	{ name = "S3", tags = TAGS, limit = 200, fixture = FLIPPED, steps = {
		give(CLICKER), stage(3),
		look("before Clicker", function(ctx, label)
			ctx.stored = ownerOf(4)
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.stored)
			own(ctx, label, 1, 5, ctx.floors[2])
		end),
		clicker, look("after Clicker", afterTLazClicker),
	} },
	-- ChangePlayerType(29) on the Dead form, with the 29 form stored, merges the two and keeps Flip; the next Flip brings a fresh Dead form (run 8).
	{ name = "r1", tags = TAGS, limit = 250, fixture = FLIPPED, steps = {
		look("before", function(ctx, label)
			ctx.stored = ownerOf(4)
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.stored)
		end),
		changeType(T_LAZ), look("after ChangePlayerType", r1Merged), flip("Flip after"), look("after Flip", r1Fresh),
	} },
	-- r1 the other way: the 29 form turned 38 with the Dead form stored (unobserved; expects r1's merge).
	{ name = "r1 mirror", tags = TAGS, limit = 200, fixture = FLIPPED, steps = {
		flip("Flip back"),
		look("before", function(ctx, label)
			ctx.active, ctx.activeSeed = keyOf(Isaac.GetPlayer(0)), seedOf(Isaac.GetPlayer(0))
			ctx.stored = ownerOf(5)
			expectCount(ctx, label, 1, 4, ctx.floors[1], nil, ctx.active)
			expectCount(ctx, label, 1, 5, ctx.floors[2], nil, ctx.stored)
		end),
		changeType(DEAD_T_LAZ), look("after ChangePlayerType", mirrorMerged),
	} },
} }
