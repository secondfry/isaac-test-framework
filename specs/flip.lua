-- Recon: Flip and Missing No. on characters other than Tainted Lazarus (the user: "Is there a way for other characters to obtain Flip?
-- Missing No.?"). No session has shown any of it, so these only record: the lineup, items and actives after each step (SNAP), every
-- player's seed and GetPtrHash (WATCH), CHAR and VERDICT lines.
local console = include("scripts.console")
local give, stage, freshStart = console.give, console.stage, console.fresh
local press = include("scripts.press").press
local record = include("scripts.record")
local verdict, watchLineup = record.verdict, record.watchLineup
local info = include("scripts.steps").info
local flipV = include("scripts.esau_jr_steps").flipV
local jrPair = include("scripts.esau_jr_steps").jrPair
local fixtures = include("scripts.fixtures")
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local FLIP, MISSING_NO, SCHOOLBAG, YUM_HEART, ISAAC, JACOB, PRIMARY, POCKET, PEDESTAL = ids.FLIP, ids.MISSING_NO, ids.SCHOOLBAG,
	ids.YUM_HEART, ids.ISAAC, ids.JACOB, ids.PRIMARY, ids.POCKET, ids.PEDESTAL

local TAGS = { "flip", "vanilla" }
local function watched(t) t.onUpdate = watchLineup(10) return t end
local function test(name, fixture, steps) return watched(snapshotTest(name, TAGS, fixture, steps, { strict = true })) end

-- Which slot giveitem puts Flip in on these characters is unobserved: each press runs only if Flip is in its slot. A press that spends
-- the charge and brings no new character ends the test with that as its note.
local function holdsFlip(slot) return function() return Isaac.GetPlayer(0):GetActiveItem(slot) == FLIP end end
local function flipPresses(label)
	return { { label .. " from the primary slot", verdict(label, press(label, FLIP, PRIMARY), 0, true), holdsFlip(PRIMARY) },
		{ label .. " from the pocket slot", flipV(label), holdsFlip(POCKET) } }
end

local function pedestalItems(_) local t = {} for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PEDESTAL)) do t[#t + 1] = e.SubType end return table.concat(t, " ") end
-- A c1 pedestal 120 px left of player 0, away from where it stands, so Flip has an item to act on.
local function spawnPedestal()
	local p = Isaac.GetPlayer(0)
	Isaac.Spawn(EntityType.ENTITY_PICKUP, PEDESTAL, 1, p.Position + Vector(-120, 0), Vector(0, 0), nil)
end

local fresh = fixtures.freshRun(ISAAC)
return { name = "flip", tests = {
	test("Isaac given Flip uses it", fresh, { { "give Flip", give(FLIP) }, flipPresses("Flip by Isaac") }),
	test("Isaac given Flip uses it beside an item pedestal", fresh, { { "give Flip", give(FLIP) }, { "spawn a c1 pedestal", spawnPedestal },
		{ "pedestals before", info("pedestal items", pedestalItems) }, flipPresses("Flip by Isaac"),
		{ "pedestals after", info("pedestal items", pedestalItems) } }),
	-- The Schoolbag keeps the Esau Jr. copy holding Isaac, so Flip is the only way back tried. Does Flip bring back the stored Isaac?
	test("Isaac Jr. given Flip uses it", fixtures.holdingJr("Isaac", ISAAC), { jrPair("Esau Jr.: Isaac -> Isaac Jr."),
		{ "give Schoolbag", give(SCHOOLBAG) }, { "give Flip", give(FLIP) }, flipPresses("Flip by Isaac Jr.") }),
	test("Jacob given Flip uses it", fixtures.jacobAndEsau({ freshStart(JACOB) }), { { "give Flip", give(FLIP) }, flipPresses("Flip by Jacob") }),
	-- Does Missing No.'s reroll change the actives (Flip, Yum Heart in the Schoolbag)? Floors change by the `stage` command, not a
	-- descent; if nothing rerolls, a real descent is the next thing to try.
	test("Missing No. with Flip across floors", fresh, { { "give Schoolbag", give(SCHOOLBAG) }, { "give Yum Heart", give(YUM_HEART) },
		{ "give Flip", give(FLIP) }, { "give Missing No.", give(MISSING_NO) }, { "stage 2", stage(2) }, { "stage 3", stage(3) },
		{ "stage 4", stage(4) } }),
} }
