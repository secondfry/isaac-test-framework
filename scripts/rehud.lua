-- The ReHUD.dbg adapter: the only file that reads ReHUD's own fields.
local seedOf = include("scripts.game").seedOf

local game = Game()

local function dbg()
	local d = ReHUD and ReHUD.dbg
	if not (d and d.tracker and d.roster) then error("ReHUD.dbg missing: install ReHUD cf965b0 or later") end
	return d
end

local function entries() return dbg().tracker.entries end

-- The GetData tag roster.lua playerKey writes (characters sharing a seed get seed + n * 2^32), or nil.
local function tag(p)
	local d = p:GetData()
	return type(d) == "table" and d.ReHUD_key or nil
end
-- ReHUD's key for a live player: its tag, else the seed.
local function keyOf(p)
	local t = tag(p)
	return t and t.key or seedOf(p)
end
local function tagText(p)
	local t = tag(p)
	return t and tostring(t.key) or "none"
end

-- ReHUD entries for which pred(e) holds.
local function countEntries(pred)
	local n = 0
	for _, e in ipairs(entries()) do
		if pred(e) then n = n + 1 end
	end
	return n
end
local function leftEntries() return countEntries(function(e) return e.left end) end

-- The owner of the last entry of item `id`, or nil.
local function ownerOf(id)
	local owner
	for _, e in ipairs(entries()) do
		if e.id == id then owner = e.owner end
	end
	return owner
end

-- What ReHUD is still settling, or nil, by each player's roster key (keyOf).
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

return {
	dbg = dbg, entries = entries, tag = tag, keyOf = keyOf, tagText = tagText, countEntries = countEntries, leftEntries = leftEntries,
	ownerOf = ownerOf, settling = settling, storedSettling = storedSettling,
}
