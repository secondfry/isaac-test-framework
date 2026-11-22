-- What every settled look asserts whatever the test: ReHUD's entries against the engine, and one row per character.
local P = include("scripts.log").P
local engine = include("scripts.game")
local ITEM_IDS, owned, wispsOf, isCharacter, countsText = engine.ITEM_IDS, engine.owned, engine.wispsOf, engine.isCharacter, engine.countsText
local rehud = include("scripts.rehud")
local dbg, entries, keyOf = rehud.dbg, rehud.entries, rehud.keyOf
local holds = include("scripts.assert").holds
local ids = include("scripts.ids")
local ESAU_JR, BIRTHRIGHT, T_LAZ, DEAD_T_LAZ = ids.ESAU_JR, ids.BIRTHRIGHT, ids.T_LAZ, ids.DEAD_T_LAZ

local game = Game()

-- A stored form can come back only through the engine's two swap items (lua-api-notes.md): Flip, by a present Tainted Lazarus of its
-- group without Birthright (with it both forms play), or Esau Jr., held by a present member. Stricter than ReHUD's own rule (roster.lua
-- keeps a form swapped while any member of its group plays, merging it only into its Flip partner turned another type), so a form ReHUD forgot to
-- merge or drop shows here.
local function revivable(r, key, present)
	for k, p in pairs(present) do
		if p and r.group(k) == r.group(key) then
			local t = p:GetPlayerType()
			if (t == T_LAZ or t == DEAD_T_LAZ) and owned(p, BIRTHRIGHT) == 0 then return true end
			for slot = 0, 2 do -- primary, secondary, pocket
				if p:GetActiveItem(slot) == ESAU_JR then return true end
			end
		end
	end
end

local function entryTag(e) return "c" .. e.id .. " of " .. tostring(e.owner) end

-- Each present character by key: the player, or false for a ghost.
local function presentCharacters()
	local present = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if isCharacter(p) then present[keyOf(p)] = not p:IsCoopGhost() and p end
	end
	return present
end

-- ReHUD's entries by owner and item: { all, clocked }.
local function entriesByOwner()
	local have = {}
	for _, e in ipairs(entries()) do
		have[e.owner] = have[e.owner] or {}
		local h = have[e.owner][e.id] or { all = 0, clocked = 0 }
		have[e.owner][e.id] = h
		h.all, h.clocked = h.all + 1, h.clocked + (e.temporary and 1 or 0)
	end
	return have
end

-- Calls f(key, id, h, engine, clocks) for every item id of every present non-ghost character: its entries `h`, the engine's count
-- and its wisp and Zodiac copies.
local function eachHeld(present, have, f)
	for key, p in pairs(present) do
		if p then
			local w, z = wispsOf(p), p:GetZodiacEffect()
			for _, id in ipairs(ITEM_IDS) do
				f(key, id, (have[key] or {})[id] or { all = 0, clocked = 0 }, p:GetCollectibleNum(id, false), (w[id] or 0) + (z == id and 1 or 0))
			end
		end
	end
end
local function heldTag(key, id, h, engineCount) return "c" .. id .. " of " .. key .. ": " .. h.all .. " entries, engine " .. engineCount end

-- (1): entries of an owner gone without being stored or left, then missing, stale and unclocked copies.
local function engineCounts(present, have)
	local r, counts = dbg().roster, {}
	for _, e in ipairs(entries()) do
		if present[e.owner] == nil and not r.isSwapped(e.owner) and not e.left then counts[#counts + 1] = entryTag(e) .. ": owner gone, neither stored nor left" end
	end
	eachHeld(present, have, function(key, id, h, engineCount, clocks)
		local tag = heldTag(key, id, h, engineCount)
		if h.all < engineCount then counts[#counts + 1] = tag .. ", missing"
		elseif h.all > engineCount and engineCount == 0 then counts[#counts + 1] = tag .. ", stale" end
		if h.clocked < clocks then counts[#counts + 1] = tag .. ", " .. h.clocked .. " clocked for " .. clocks .. " wisp/Zodiac copies" end
	end)
	return counts
end

-- (2)
local function duplicates(present, have)
	local dups = {}
	eachHeld(present, have, function(key, id, h, engineCount)
		if h.all > engineCount and engineCount > 0 then dups[#dups + 1] = heldTag(key, id, h, engineCount) .. ", duplicate" end
	end)
	return dups
end

-- (3) An Esau Jr. character stays stored until the run ends (user decision 2026-11-22): its copy may lie anywhere. Exempt only a row
-- the harness itself saw stored by Esau Jr., not ReHUD's own esauJr flag.
local function phantoms(present)
	local r, jrStored, out = dbg().roster, {}, {}
	for _, c in pairs(HARNESS.chars and HARNESS.chars.list or {}) do
		if c.state == "stored" and c.storedBy == ESAU_JR then jrStored[c.key] = true end
	end
	for _, row in ipairs(r.serialize()) do
		if row.swapped and not jrStored[row.key] and not revivable(r, row.key, present) then out[#out + 1] = tostring(row.key) .. " stored, nobody can swap it back" end
	end
	return out
end

-- (4)
local function lefts()
	local out = {}
	for _, e in ipairs(entries()) do
		if e.left then out[#out + 1] = entryTag(e) end
	end
	return out
end

-- (5)
local function floors(ctx)
	local rank, stageNow, out = {}, game:GetLevel():GetStage(), {}
	for k = 1, stageNow do
		if ctx.floors[k] then rank[ctx.floors[k]] = k end
	end
	for _, e in ipairs(entries()) do
		if not rank[e.floor] then out[#out + 1] = entryTag(e) .. " on '" .. tostring(e.floor) .. "', not a floor up to stage " .. stageNow end
	end
	return out
end

-- Invariants every settled look asserts, whatever the test: (1) for each present character and item, ReHUD's entries match the
-- engine's GetCollectibleNum(id, false) (ReHUD lists every copy: owned and innate without a clock, each wisp and the Zodiac copy with
-- one), at least the wisps and Zodiac copy clocked, and no entry of an owner gone without being stored or left; (2) no duplicates past
-- that count; (3) every stored form revivable; (4) no left entries unless the test sets `leftOk`; (5) no entry on a floor later
-- than the current one. A ghost's list is frozen, so ghosts are left out of (1) and (2).
-- shortcut: a 3 Dollar Bill grant shows only on ReHUD's 30-update scan, so a look within 30 updates of a re-grant would fail (1); every
-- look after a grant follows `listed`, far inside the ~170-update interval. Wait for that scan in look if a test looks later.
local function check(ctx, label)
	local present, have = presentCharacters(), entriesByOwner()
	holds(ctx, label, "engine counts", engineCounts(present, have))
	holds(ctx, label, "duplicates", duplicates(present, have))
	holds(ctx, label, "phantom stored forms", phantoms(present))
	holds(ctx, label, "left entries", ctx.leftOk and {} or lefts())
	holds(ctx, label, "floors", floors(ctx))
end

-- One assertion: every remembered character not gone has its own row (a number no other character's key holds), a stored one is marked
-- stored and listed with exactly the copies it held when last live, and every ReHUD row is a character's. Live ones are the invariants'
-- engine-count check. A NUMBERS line per character.
local function characterNumbers(ctx, label)
	local r, problems, byNumber = dbg().roster, {}, {}
	local ids, keys = {}, {}
	for id in pairs(HARNESS.chars.list) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local c = HARNESS.chars.list[id]
		local have = {}
		for _, e in ipairs(entries()) do
			if e.owner == c.key then have[e.id] = (have[e.id] or 0) + 1 end
		end
		local num = r.number(c.key)
		P("NUMBERS", ctx.name, label, "char", id, c.name, c.state, "key", c.key, "number", num, "swapped", r.isSwapped(c.key), "type", c.type, "seed", c.seed,
			"hash", c.hash, "index", c.index, "engine", countsText(c.items), "rehud", countsText(have))
		if c.state ~= "gone" then
			keys[c.key] = true
			if num == nil then problems[#problems + 1] = c.name .. " (" .. c.state .. ") has no row"
			elseif byNumber[num] then problems[#problems + 1] = c.name .. " shares row " .. num .. " with " .. byNumber[num]
			else byNumber[num] = c.name end
			if c.state == "stored" then
				if not r.isSwapped(c.key) then problems[#problems + 1] = c.name .. " not marked stored" end
				local all = {}
				for k in pairs(c.items) do all[k] = true end
				for k in pairs(have) do all[k] = true end
				for k in pairs(all) do
					if (c.items[k] or 0) ~= (have[k] or 0) then problems[#problems + 1] = c.name .. " c" .. k .. ": " .. (have[k] or 0) .. " entries, held " .. (c.items[k] or 0) end
				end
			end
		end
	end
	for _, row in ipairs(r.serialize()) do
		if not keys[row.key] then problems[#problems + 1] = "row " .. tostring(row.key) .. " (number " .. tostring(row.number) .. ") is no character's" end
	end
	holds(ctx, label, "characters", problems)
end

return { check = check, characterNumbers = characterNumbers }
