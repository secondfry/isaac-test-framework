-- What every settled look asserts whatever the scenario: ReHUD's entries against the engine, and one row per character.
local P = include("scripts.log").P
local engine = include("scripts.game")
local itemConfig, maxId, owned, wispsOf, isCharacter, countsText = engine.itemConfig, engine.maxId, engine.owned, engine.wispsOf, engine.isCharacter,
	engine.countsText
local rehud = include("scripts.rehud")
local dbg, entries, keyOf = rehud.dbg, rehud.entries, rehud.keyOf
local holds = include("scripts.assert").holds
local ids = include("scripts.ids")
local ESAU_JR, BIRTHRIGHT, T_LAZ, DEAD_LAZ = ids.ESAU_JR, ids.BIRTHRIGHT, ids.T_LAZ, ids.DEAD_LAZ

local game = Game()

-- A stored form can come back only through the engine's two swap items (lua-api-notes.md): Flip, by a present Tainted Lazarus of its
-- group without Birthright (with it both forms play), or Esau Jr., held by a present member. Stricter than ReHUD's own rule (roster.lua
-- keeps a form swapped while any member of its group plays, merging it only into its Flip partner turned another type), so a form ReHUD forgot to
-- merge or drop shows here.
local function revivable(r, key, present)
	for k, p in pairs(present) do
		if p and r.group(k) == r.group(key) then
			local t = p:GetPlayerType()
			if (t == T_LAZ or t == DEAD_LAZ) and owned(p, BIRTHRIGHT) == 0 then return true end
			for slot = 0, 2 do -- primary, secondary, pocket
				if p:GetActiveItem(slot) == ESAU_JR then return true end
			end
		end
	end
end

-- Invariants every settled look checks, whatever the scenario: (1) for each present character and item, ReHUD's entries match the
-- engine's GetCollectibleNum(id, false) (ReHUD lists every copy: owned and innate without a clock, each wisp and the Zodiac copy with
-- one), at least the wisps and Zodiac copy clocked, and no entry of an owner gone without being stored or left; (2) no duplicates past
-- that count; (3) every stored form revivable; (4) no left entries unless the scenario sets `leftOk`; (5) no entry on a floor later
-- than the current one. A ghost's list is frozen, so ghosts are left out of (1) and (2).
-- shortcut: a 3 Dollar Bill grant shows only on ReHUD's 30-update scan, so a look within 30 updates of a re-grant would fail (1); every
-- look after a grant follows `listed`, far inside the ~170-update interval. Wait for that scan in look if a scenario looks later.
local function invariants(ctx, label)
	local r, present, have = dbg().roster, {}, {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if isCharacter(p) then present[keyOf(p)] = not p:IsCoopGhost() and p end
	end
	local rank, stageNow = {}, game:GetLevel():GetStage()
	for k = 1, stageNow do
		if ctx.floors[k] then rank[ctx.floors[k]] = k end
	end
	local counts, dups, phantoms, lefts, floors = {}, {}, {}, {}, {}
	for _, e in ipairs(entries()) do
		local tag = "c" .. e.id .. " of " .. tostring(e.owner)
		have[e.owner] = have[e.owner] or {}
		local h = have[e.owner][e.id] or { all = 0, clocked = 0 }
		have[e.owner][e.id] = h
		h.all, h.clocked = h.all + 1, h.clocked + (e.temporary and 1 or 0)
		if present[e.owner] == nil and not r.isSwapped(e.owner) and not e.left then counts[#counts + 1] = tag .. ": owner gone, neither stored nor left" end
		if e.left then lefts[#lefts + 1] = tag end
		if not rank[e.floor] then floors[#floors + 1] = tag .. " on '" .. tostring(e.floor) .. "', not a floor up to stage " .. stageNow end
	end
	for key, p in pairs(present) do
		if p then
			local w, z = wispsOf(p), p:GetZodiacEffect()
			for id = 1, maxId do
				if itemConfig:GetCollectible(id) then
					local engineCount = p:GetCollectibleNum(id, false)
					local h = (have[key] or {})[id] or { all = 0, clocked = 0 }
					local tag = "c" .. id .. " of " .. key .. ": " .. h.all .. " entries, engine " .. engineCount
					if h.all < engineCount then counts[#counts + 1] = tag .. ", missing"
					elseif h.all > engineCount and engineCount == 0 then counts[#counts + 1] = tag .. ", stale"
					elseif h.all > engineCount then dups[#dups + 1] = tag .. ", duplicate" end
					local clocks = (w[id] or 0) + (z == id and 1 or 0)
					if h.clocked < clocks then counts[#counts + 1] = tag .. ", " .. h.clocked .. " clocked for " .. clocks .. " wisp/Zodiac copies" end
				end
			end
		end
	end
	-- An Esau Jr. character stays stored until the run ends (user decision 2026-11-22): its copy may lie anywhere. Exempt only a row the
	-- harness itself saw stored by Esau Jr., not ReHUD's own esauJr flag.
	local jrStored = {}
	for _, c in pairs(HARNESS.chars and HARNESS.chars.list or {}) do
		if c.state == "stored" and c.storedBy == ESAU_JR then jrStored[c.key] = true end
	end
	for _, row in ipairs(r.serialize()) do
		if row.swapped and not jrStored[row.key] and not revivable(r, row.key, present) then phantoms[#phantoms + 1] = tostring(row.key) .. " stored, nobody can swap it back" end
	end
	holds(ctx, label, "engine counts", counts)
	holds(ctx, label, "duplicates", dups)
	holds(ctx, label, "phantom stored forms", phantoms)
	holds(ctx, label, "left entries", ctx.leftOk and {} or lefts)
	holds(ctx, label, "floors", floors)
end

-- One check: every remembered character not gone has its own row (a number no other character's key holds), a stored one is marked
-- stored and listed with exactly the copies it held when last live, and every ReHUD row is a character's. Live ones are the invariants'
-- engine-count check. A ROWS line per character.
local function charRows(ctx, label)
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
		P("ROWS", ctx.name, label, "char", id, c.name, c.state, "key", c.key, "number", num, "swapped", r.isSwapped(c.key), "type", c.type, "seed", c.seed,
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

return { invariants = invariants, charRows = charRows }
