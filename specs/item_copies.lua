-- One icon per copy: owned, innate, wisps, the Zodiac and 3 Dollar Bill copies (plan S4).
local P = include("scripts.log").P
local console = include("scripts.console")
local fresh, give, remove, stage = console.fresh, console.give, console.remove, console.stage
local changeType = include("scripts.steps").changeType
local copies = include("scripts.copies")
local wisp, killWisp, engineWisps, zodiacOn, grant3DB, listed = copies.wisp, copies.killWisp, copies.engineWisps, copies.zodiacOn,
	copies.grant3DB, copies.listed
local assertions = include("scripts.assert")
local expectCount, own = assertions.expectCount, assertions.own
local look = include("scripts.settle").look
local ids = include("scripts.ids")
local ISAAC, CAIN = ids.ISAAC, ids.CAIN

local TAGS = { "item_copies", "rehud" }

-- A fresh run of type `t`, built per test.
-- shortcut: restart only, no fixed seed yet; console.fresh gains the seed command once session 1 has shown its order (plan S7).
local function freshRun(t)
	return { name = "fresh run of type " .. t, setup = { fresh(t) },
		done = function() return Isaac.GetPlayer(0):GetPlayerType() == t, "player 0 is not type " .. t end }
end

return { name = "item_copies", tests = {
	-- One entry per copy, by kind (clocked: wisps), floors kept; a lost copy takes the oldest entry of its kind.
	{ name = "one icon per owned, innate and wisp copy, the oldest lost first", tags = TAGS, fixture = freshRun(CAIN), steps = {
		look("start", function(ctx, label)
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
	-- Settled before the grant, so the Zodiac copy is not learned as innate.
	{ name = "Zodiac copy is clocked", tags = TAGS, fixture = freshRun(ISAAC), steps = {
		look("start"), give(392), zodiacOn("on the floor given", 30), stage(2), zodiacOn("on stage 2"),
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
	} },
	-- Settled before the first grant, so no grant is learned as innate.
	{ name = "3 Dollar Bill copies are clocked", tags = TAGS, fixture = freshRun(ISAAC), steps = {
		look("before 3 Dollar Bill"), give(191), grant3DB, listed,
		look("3 Dollar Bill", function(ctx, label) expectCount(ctx, label, 0, ctx.grant, nil, false) end),
		grant3DB, listed, look("next 3 Dollar Bill grant", function(ctx, label)
			if Isaac.GetPlayer(0):GetCollectibleNum(ctx.grantOld, false) > 0 then return table.insert(ctx.notes, "3 Dollar Bill still grants c" .. ctx.grantOld) end
			expectCount(ctx, label, 0, ctx.grantOld, nil, true)
		end),
	} },
	-- ChangePlayerType re-settles: the new type's innate c46 is learned, the wisp and the Zodiac copy stay clocked.
	{ name = "base character change learns the innate copy, clocked copies stay", tags = TAGS, fixture = freshRun(ISAAC), steps = {
		look("start"), give(392), stage(2), zodiacOn("on stage 2"), wisp(46),
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
} }
