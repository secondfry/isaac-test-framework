-- Shared fixtures: each a starting setup from a fresh run, with the done check the runner polls before the test's steps.
local console = include("scripts.console")
local fresh, restart, give, stage = console.fresh, console.restart, console.give, console.stage
local press = include("scripts.press")
local flip, esauJr = press.flip, press.esauJr
local engine = include("scripts.game")
local seedOf, owned, ofType = engine.seedOf, engine.owned, engine.ofType
local expect = include("scripts.assert").expect
local characters = include("scripts.characters")
local named, who, byName = characters.named, characters.who, characters.byName
local lookC = include("scripts.settle").lookC
local ids = include("scripts.ids")
local ESAU_JR, BIRTHRIGHT, T_LAZ, DEAD_T_LAZ, JACOB, ESAU = ids.ESAU_JR, ids.BIRTHRIGHT, ids.T_LAZ, ids.DEAD_T_LAZ, ids.JACOB, ids.ESAU

-- A fixture: `setup`, done once player 0 is of type `t` and `extra(p)` (ok, why) holds for it.
local function fixture(name, setup, t, extra)
	return { name = name, setup = setup, done = function()
		local p = Isaac.GetPlayer(0)
		if p:GetPlayerType() ~= t then return false, "player 0 is type " .. p:GetPlayerType() .. ", want " .. t end
		if extra then return extra(p) end
		return true
	end }
end
local function owns(id) return function(p) return owned(p, id) > 0, "player 0 owns no c" .. id end end
local ownsJr, ownsC4 = owns(ESAU_JR), owns(4)

-- A fresh run of type `t` on the fixed seed (console.fresh).
local function freshRun(t) return fixture("fresh run of type " .. t, { fresh(t) }, t) end
-- `character` (type `t`) with c4 from floor 1 and an unpressed Esau Jr.
local function holdingJr(character, t) return fixture(character .. " holding Esau Jr.", { fresh(t), give(4), give(ESAU_JR) }, t, ownsJr) end
-- Jacob beside Esau after `setup`.
local function jacobAndEsau(setup)
	return fixture("Jacob and Esau", setup, JACOB, function() return ofType(ESAU) ~= nil, "no Esau beside Jacob" end)
end

-- The characters the per-character recon tests start as, Tainted Isaac and Tainted Jacob included: all unlocked on the save played
-- in session 2; `character` still reports a locked one. `who`: the press for Tainted Forgotten, as which button and entity use his active is unknown.
local RECON_CHARACTERS = {
	{ type = ids.ISAAC, name = "Isaac" }, { type = ids.T_ISAAC, name = "Tainted Isaac" }, { type = JACOB, name = "Jacob and Esau" },
	{ type = ids.FORGOTTEN, name = "The Forgotten" }, { type = ids.T_FORGOTTEN, name = "Tainted Forgotten", who = { index = 0, any = true } },
	{ type = T_LAZ, name = "Tainted Lazarus" }, { type = ids.T_JACOB, name = "Tainted Jacob" },
}
-- Recon character `c` started by restart, then `setup` (a flat step list); a restart that brings another character fails the test as a
-- precondition naming `c`, as a locked one may (unobserved).
local function character(c, setup, extra)
	local f = fixture(c.name .. " started", { restart(c.type), table.unpack(setup or {}) }, c.type, extra)
	local done = f.done
	f.done = function(ctx)
		local ok, why = done(ctx)
		return ok, not ok and (c.name .. " (type " .. c.type .. ") cannot be started, locked on this save? " .. tostring(why)) or nil
	end
	return f
end

-- Tainted Lazarus L, Flip to a new Dead form D, back, Esau Jr. to L's form LJ (on D's seed), and LJ's Flip to D (in-game 2026-11-22).
local TLAZ_FLIPS = fixture("Tainted Lazarus's Flip and Esau Jr. characters", { fresh(T_LAZ), give(4), give(ESAU_JR), named("L"),
	flip("Flip L -> D"), named("D"), give(5), flip("Flip D -> L"), who("L"), lookC("L and D"), esauJr("Esau Jr. L -> LJ"), named("LJ"), give(6),
	function(ctx) expect(ctx, "engine, not ReHUD: LJ on D's item seed", seedOf(Isaac.GetPlayer(0)), byName("D").seed) end,
	lookC("LJ"), flip("Flip LJ -> D"), who("D"), lookC("D back") }, DEAD_T_LAZ)

return {
	fixture = fixture, owns = owns, freshRun = freshRun, holdingJr = holdingJr, jacobAndEsau = jacobAndEsau, TLAZ_FLIPS = TLAZ_FLIPS,
	RECON_CHARACTERS = RECON_CHARACTERS, character = character,
	TLAZ_JR = holdingJr("Tainted Lazarus", T_LAZ),
	TLAZ_JR_FLOOR_2 = fixture("Tainted Lazarus holding Esau Jr. on floor 2", { fresh(T_LAZ), give(4), give(ESAU_JR), stage(2) }, T_LAZ, ownsJr),
	-- Tainted Lazarus with c4 from floor 1, flipped on floor 2 to its Dead form, which takes c5.
	FLIPPED = fixture("Tainted Lazarus flipped", { fresh(T_LAZ), give(4), stage(2), flip("Flip"), give(5) }, DEAD_T_LAZ),
	TLAZ_C4 = fixture("Tainted Lazarus holding c4", { fresh(T_LAZ), give(4) }, T_LAZ, ownsC4),
	TLAZ_C4_FLOOR_2 = fixture("Tainted Lazarus holding c4 on floor 2", { fresh(T_LAZ), give(4), stage(2) }, T_LAZ, ownsC4),
	TLAZ_JR_TWINS = fixture("Tainted Lazarus holding Esau Jr. and Birthright twins", { fresh(T_LAZ), give(4), give(ESAU_JR), give(BIRTHRIGHT, 2) },
		T_LAZ, ownsJr),
}
