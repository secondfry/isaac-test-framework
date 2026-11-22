-- Shared starting step lists: a fresh run holding Esau Jr., and Tainted Lazarus's Flip and Esau Jr. characters named.
local console = include("scripts.console")
local restart, give = console.restart, console.give
local press = include("scripts.press")
local flip, esauJr = press.flip, press.esauJr
local seedOf = include("scripts.game").seedOf
local expect = include("scripts.assert").expect
local characters = include("scripts.characters")
local named, who, charNamed = characters.named, characters.who, characters.charNamed
local lookC = include("scripts.settle").lookC
local ids = include("scripts.ids")
local ESAU_JR, T_LAZ = ids.ESAU_JR, ids.T_LAZ

local function jrSetup(playerType) return { restart(playerType), give(4), give(ESAU_JR) } end
local function tlazJr() return jrSetup(T_LAZ) end

-- Tainted Lazarus L, Flip to a new Dead form D, back, Esau Jr. to L's form LJ (on D's seed), and LJ's Flip to D (in-game 2026-11-22).
local function tlazFlips()
	return { restart(T_LAZ), give(4), give(ESAU_JR), named("L"), flip("Flip L -> D"), named("D"), give(5), flip("Flip D -> L"), who("L"),
		lookC("L and D"), esauJr("Esau Jr. L -> LJ"), named("LJ"), give(6),
		function(ctx) expect(ctx, "engine, not ReHUD: LJ on D's item seed", seedOf(Isaac.GetPlayer(0)), charNamed("D").seed) end,
		lookC("LJ"), flip("Flip LJ -> D"), who("D"), lookC("D back") }
end

return { jrSetup = jrSetup, tlazJr = tlazJr, tlazFlips = tlazFlips }
