-- The characters of a run as the harness sees them, each by its entity (GetPtrHash), with the items it held when last live.
local P = include("scripts.log").P
local engine = include("scripts.game")
local seedOf, ofType, isCharacter, itemCounts, countsText = engine.seedOf, engine.ofType, engine.isCharacter, engine.itemCounts,
	engine.countsText
local keyOf = include("scripts.rehud").keyOf
local expect = include("scripts.assert").expect
local ids = include("scripts.ids")
local FLIP, ESAU_JR = ids.FLIP, ids.ESAU_JR

local game = Game()

-- The harness tells characters apart by their entity (GetPtrHash), so two characters on one seed stay two, and remembers each one's
-- items from its last live update: a stored character is invisible to Lua (lua-api-notes.md), so those are what ReHUD must still list.

-- A character is its entity (GetPtrHash): a stored one comes back with it (lua-api-notes.md), and a gone one never comes back, so a
-- reused hash on a gone one is a new character.
-- shortcut: GetPtrHash renews on Continue (lua-api-notes.md), so every character after a Continue is new; key it otherwise if a test
-- with assertions needs a character across a Continue.
local function charOf(p)
	local C = HARNESS.chars
	local c = C and C.byHash[GetPtrHash(p)]
	return c and c.state ~= "gone" and c or nil
end

-- Every update of a run: names each new character, refreshes the live ones and marks one that left play as stored (gone during an
-- Esau Jr. or Flip swap, storedBy that item) or gone (merged, summoned Esau gone, removed).
local function track()
	local C, name, swapItem = HARNESS.chars, HARNESS.session.ctx.name, HARNESS.press.swapItem
	if not C or game:GetNumPlayers() == 0 then return end
	local seen = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if isCharacter(p) then
			local c = charOf(p)
			if not c then
				C.n = C.n + 1
				c = { id = C.n, name = "#" .. C.n }
				C.list[C.n], C.byHash[GetPtrHash(p)] = c, c
				P("INFO", name, "CHAR", c.id, "first seen at index", i, "type", p:GetPlayerType(), "seed", seedOf(p), "hash", GetPtrHash(p), "parent", p.Parent ~= nil)
			elseif c.state ~= "live" then
				P("INFO", name, "CHAR", c.id, c.name, "back in play at index", i, "type", p:GetPlayerType(), "seed", seedOf(p), "hash", GetPtrHash(p))
			end
			seen[c.id] = true
			c.state, c.key, c.type, c.seed, c.hash, c.index, c.items = "live", keyOf(p), p:GetPlayerType(), seedOf(p), GetPtrHash(p), i, itemCounts(p)
		end
	end
	for id, c in pairs(C.list) do
		if c.state == "live" and not seen[id] then
			c.state = (swapItem == ESAU_JR or swapItem == FLIP) and "stored" or "gone"
			c.storedBy = c.state == "stored" and swapItem or nil
			P("INFO", name, "CHAR", id, c.name, "left play:", c.state, swapItem and ("during a c" .. swapItem .. " swap") or "outside a swap", "last items", countsText(c.items))
		end
	end
end

-- A new run starts with no characters seen; a Continue keeps them.
local function onGameStart(isContinued)
	if not isContinued then HARNESS.chars = { list = {}, byHash = {}, n = 0 } end
end

-- A stored character whose items the engine moved onto the live one: merged, so gone.
local function merged(c) c.state = "gone" end

local function byName(n)
	for _, c in pairs(HARNESS.chars.list) do
		if c.name == n then return c end
	end
end

-- Names the character at GetPlayer index 0, or the first of type `t` when given.
local function named(n, t)
	return function(ctx)
		track()
		local p = t and ofType(t) or Isaac.GetPlayer(0)
		local c = p and charOf(p)
		if not c then error("no character to name " .. n) end
		c.name = n
		P("INFO", ctx.name, "CHAR", c.id, "is", n, "type", c.type, "seed", c.seed, "key", c.key, "hash", c.hash, "items", countsText(c.items))
	end
end

-- An engine fact from lua-api-notes.md (who a press brings): its FAIL names the engine.
local function who(n)
	return function(ctx)
		track()
		local c = charOf(Isaac.GetPlayer(0))
		expect(ctx, "engine, not ReHUD: player 0 is " .. n, c and c.name, n)
	end
end
-- Unobserved who: logged only.
local function whoInfo(what)
	return function(ctx)
		track()
		local c = charOf(Isaac.GetPlayer(0))
		P("INFO", ctx.name, "after " .. what .. " (unobserved) player 0 is", c and c.name, "type", Isaac.GetPlayer(0):GetPlayerType(), "seed", seedOf(Isaac.GetPlayer(0)))
	end
end

return { track = track, onGameStart = onGameStart, merged = merged, byName = byName, named = named, who = who, whoInfo = whoInfo }
