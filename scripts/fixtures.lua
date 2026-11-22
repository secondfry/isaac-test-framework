-- Shared starting step lists: a fresh run holding Esau Jr., a flipped Tainted Lazarus, and Tainted Lazarus's Flip and Esau Jr.
-- characters named.
local console = include("scripts.console")
local fresh, give, stage = console.fresh, console.give, console.stage
local press = include("scripts.press")
local flip, esauJr = press.flip, press.esauJr
local seedOf = include("scripts.game").seedOf
local expect = include("scripts.assert").expect
local characters = include("scripts.characters")
local named, who, byName = characters.named, characters.who, characters.byName
local lookC = include("scripts.settle").lookC
local ids = include("scripts.ids")
local ESAU_JR, T_LAZ = ids.ESAU_JR, ids.T_LAZ

local function jrSetup(playerType) return { fresh(playerType), give(4), give(ESAU_JR) } end
local function tlazJr() return jrSetup(T_LAZ) end

-- Tainted Lazarus with c4 from floor 1, flipped on floor 2 to its Dead form, which takes c5.
local function tlazFlipped() return { fresh(T_LAZ), give(4), stage(2), flip("Flip"), give(5) } end

-- Tainted Lazarus L, Flip to a new Dead form D, back, Esau Jr. to L's form LJ (on D's seed), and LJ's Flip to D (in-game 2026-11-22).
local function tlazFlips()
	return { fresh(T_LAZ), give(4), give(ESAU_JR), named("L"), flip("Flip L -> D"), named("D"), give(5), flip("Flip D -> L"), who("L"),
		lookC("L and D"), esauJr("Esau Jr. L -> LJ"), named("LJ"), give(6),
		function(ctx) expect(ctx, "engine, not ReHUD: LJ on D's item seed", seedOf(Isaac.GetPlayer(0)), byName("D").seed) end,
		lookC("LJ"), flip("Flip LJ -> D"), who("D"), lookC("D back") }
end

return { jrSetup = jrSetup, tlazJr = tlazJr, tlazFlipped = tlazFlipped, tlazFlips = tlazFlips }
