-- What every settled look asserts whatever the test: ReHUD's entries against the engine, and one row per character.
local P = include("scripts.log").P
local engine = include("scripts.game")
local ITEM_IDS, owned, wispsOf, isCharacter, countsText = engine.ITEM_IDS, engine.owned, engine.wispsOf, engine.isCharacter, engine.countsText
local rehud = include("scripts.rehud")
local entries, keyOf, number, letter, isSwapped, group, rows = rehud.entries, rehud.keyOf, rehud.number, rehud.letter, rehud.isSwapped, rehud.group,
	rehud.rows
local holds = include("scripts.assert").holds
local ids = include("scripts.ids")
local ESAU_JR, BIRTHRIGHT, T_LAZ, DEAD_T_LAZ = ids.ESAU_JR, ids.BIRTHRIGHT, ids.T_LAZ, ids.DEAD_T_LAZ

local game = Game()

-- A stored form comes back only by Flip (a present Tainted Lazarus of its group without Birthright) or a held Esau Jr. (docs/engine-facts.md; a Birthright return, seen in sessions 5a and 5b, passed because Tainted Lazarus Jr. held Esau Jr.): stricter than roster.lua's rule, so a form ReHUD forgot to merge or drop shows.
local function revivable(key, present)
	for k, p in pairs(present) do
		if p and group(k) == group(key) then
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
	local counts = {}
	for _, e in ipairs(entries()) do
		if present[e.owner] == nil and not isSwapped(e.owner) and not e.left then counts[#counts + 1] = entryTag(e) .. ": owner gone, neither stored nor left" end
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

-- (3) An Esau Jr. character stays stored until the run ends (ReHUD 2.8's rule): its copy may lie anywhere. Exempt only a row
-- the harness itself saw stored by Esau Jr., not ReHUD's own esauJr flag.
local function phantoms(present)
	local jrStored, out = {}, {}
	for _, c in pairs(HARNESS.chars and HARNESS.chars.list or {}) do
		if c.state == "stored" and c.storedBy == ESAU_JR then jrStored[c.key] = true end
	end
	for _, row in ipairs(rows()) do
		if row.swapped and not jrStored[row.key] and not revivable(row.key, present) then out[#out + 1] = tostring(row.key) .. " stored, nobody can swap it back" end
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

-- Every settled look: (1) entries match the engine's counts, copies with a clock clocked, (2) no duplicates, (3) stored forms revivable, (4) no left entries unless leftOk, (5) no later floor; ghosts' frozen lists skip (1)-(2).
-- shortcut: a 3 Dollar Bill grant shows only on ReHUD's 30-update scan, so a look within 30 updates of a re-grant would fail (1); wait for that scan in look if a test looks that soon.
local function check(ctx, label)
	local present, have = presentCharacters(), entriesByOwner()
	holds(ctx, label, "engine counts", engineCounts(present, have))
	holds(ctx, label, "duplicates", duplicates(present, have))
	holds(ctx, label, "phantom stored forms", phantoms(present))
	holds(ctx, label, "left entries", ctx.leftOk and {} or lefts())
	holds(ctx, label, "floors", floors(ctx))
end

-- One assertion: every remembered character not gone has its own row (a number and twin letter no other character's key holds; a number
-- is shared only by two twins, a and b), a stored one is marked stored and listed with exactly the copies it held when last live, and
-- every ReHUD row is a character's. Live ones are the invariants' engine-count check. A NUMBERS line per character.
local function characterNumbers(ctx, label)
	local problems, byNumber, holders = {}, {}, {}
	local ids, keys = {}, {}
	for id in pairs(HARNESS.chars.list) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local c = HARNESS.chars.list[id]
		local have = {}
		for _, e in ipairs(entries()) do
			if e.owner == c.key then have[e.id] = (have[e.id] or 0) + 1 end
		end
		local num, twin = number(c.key), letter(c.key)
		P("NUMBERS", ctx.name, label, "char", id, c.name, c.state, "key", c.key, "number", num, "letter", twin, "swapped", isSwapped(c.key), "type", c.type,
			"seed", c.seed, "hash", c.hash, "index", c.index, "engine", countsText(c.items), "rehud", countsText(have))
		if c.state ~= "gone" then
			keys[c.key] = true
			local row = num and num .. (twin or "")
			if num == nil then problems[#problems + 1] = c.name .. " (" .. c.state .. ") has no row"
			elseif byNumber[row] then problems[#problems + 1] = c.name .. " shares row " .. row .. " with " .. byNumber[row]
			else
				byNumber[row] = c.name
				holders[num] = holders[num] or {}
				table.insert(holders[num], c.name .. (twin or ""))
			end
			if c.state == "stored" then
				if not isSwapped(c.key) then problems[#problems + 1] = c.name .. " not marked stored" end
				local all = {}
				for k in pairs(c.items) do all[k] = true end
				for k in pairs(have) do all[k] = true end
				for k in pairs(all) do
					if (c.items[k] or 0) ~= (have[k] or 0) then problems[#problems + 1] = c.name .. " c" .. k .. ": " .. (have[k] or 0) .. " entries, held " .. (c.items[k] or 0) end
				end
			end
		end
	end
	for num, names in pairs(holders) do
		local twins = #names == 2 and byNumber[num .. "a"] and byNumber[num .. "b"]
		if #names > 1 and not twins then problems[#problems + 1] = "number " .. num .. " held by " .. table.concat(names, ", ") .. ", not twins a and b" end
	end
	for _, row in ipairs(rows()) do
		if not keys[row.key] then problems[#problems + 1] = "row " .. tostring(row.key) .. " (number " .. tostring(row.number) .. ") is no character's" end
	end
	holds(ctx, label, "characters", problems)
end

return { check = check, characterNumbers = characterNumbers }
