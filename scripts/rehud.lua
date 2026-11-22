-- The ReHUD.dbg adapter: the only file that reads ReHUD's own fields.
local seedOf = include("scripts.game").seedOf

local game = Game()

local function dbg()
	local d = ReHUD and ReHUD.dbg
	if not (d and d.tracker and d.roster) then error("ReHUD.dbg missing: install ReHUD eeae5c0 or later") end
	return d
end

local function entries() return dbg().tracker.entries end

-- ReHUD's key for a live player: the GetData tag roster.lua playerKey writes (characters sharing a seed get seed + n * 2^32), else the seed.
local function keyOf(p)
	local d = p:GetData()
	local tag = type(d) == "table" and d.ReHUD_key
	return tag and tag.key or seedOf(p)
end
local function tagText(p)
	local d = p:GetData()
	local tag = type(d) == "table" and d.ReHUD_key
	return tag and tostring(tag.key) or "none"
end

-- ReHUD entries of item `id` matching every given field (nil: any); `temporary` true is a copy with a clock.
local function countOf(id, floor, temporary, owner)
	local n = 0
	for _, e in ipairs(entries()) do
		if e.id == id and (floor == nil or e.floor == floor) and (temporary == nil or e.temporary == temporary) and (owner == nil or e.owner == owner) then n = n + 1 end
	end
	return n
end

local function leftEntries()
	local n = 0
	for _, e in ipairs(entries()) do
		if e.left then n = n + 1 end
	end
	return n
end

-- What ReHUD is still settling, or nil. The roster key is the Sad Onion RNG seed (roster.lua playerKey), which is seedOf.
local function settling()
	for _, e in ipairs(entries()) do
		if e.merged then return "a merge" end
	end
	local roster = dbg().roster
	for i = 0, game:GetNumPlayers() - 1 do
		if roster.isSettling(keyOf(Isaac.GetPlayer(i))) then return "a new character" end
	end
end

-- Stored forms still settling: the wait skips them, as ReHUD freezes their settle until they return (roster.lua), so this says whether
-- a step tested ReHUD's stored-mid-settle path or its settled one.
local function storedSettling()
	local r, seen, t = dbg().roster, {}, {}
	for _, e in ipairs(entries()) do
		if not seen[e.owner] and r.isSwapped(e.owner) and r.isSettling(e.owner) then seen[e.owner] = true; t[#t + 1] = e.owner end
	end
	return table.concat(t, ",")
end

local function ownerCount(key)
	local n = 0
	for _, e in ipairs(entries()) do
		if e.owner == key then n = n + 1 end
	end
	return n
end

return {
	dbg = dbg, entries = entries, keyOf = keyOf, tagText = tagText, countOf = countOf, leftEntries = leftEntries, settling = settling,
	storedSettling = storedSettling, ownerCount = ownerCount,
}
