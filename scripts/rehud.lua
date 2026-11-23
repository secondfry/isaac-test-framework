-- The ReHUD.dbg adapter: the only file that reaches into ReHUD (its tracker, roster and GetData tag); others read the entries and rows it returns.
local seedOf = include("scripts.game").seedOf

local game = Game()

-- False in a vanilla session: the trace and the settle waits then skip ReHUD, and the runner SKIPs rehud tests but the snapshot ones.
local function present()
	local d = ReHUD and ReHUD.dbg
	return (d and d.tracker and d.roster) ~= nil
end

local function dbg()
	if not present() then error("ReHUD.dbg missing: install ReHUD cf965b0 or later") end
	return ReHUD.dbg
end

local function entries() return dbg().tracker.entries end
local function characterCount() return dbg().tracker.characterCount end
-- The roster by key: a character's number (nil when it has none), whether it is stored, still settling, its group; every row.
local function number(key) return dbg().roster.number(key) end
-- Its twin letter: "a" or "b" for the two characters of a duo sharing one number, nil for any other.
local function letter(key)
	local roster = dbg().roster
	if not roster.letter then error("ReHUD.dbg.roster.letter missing: install ReHUD a97424c or later") end
	return roster.letter(key)
end
local function isSwapped(key) return dbg().roster.isSwapped(key) end
local function isSettling(key) return dbg().roster.isSettling(key) end
local function group(key) return dbg().roster.group(key) end
local function rows() return dbg().roster.serialize() end

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

-- What ReHUD is still settling, or nil, by each player's roster key (keyOf); nil without ReHUD.
local function settling()
	if not present() then return end
	for _, e in ipairs(entries()) do
		if e.merged then return "a merge" end
	end
	for i = 0, game:GetNumPlayers() - 1 do
		if isSettling(keyOf(Isaac.GetPlayer(i))) then return "a new character" end
	end
end

-- Stored forms still settling: the wait skips them, as ReHUD freezes their settle until they return (roster.lua), so this says whether
-- a step tested ReHUD's stored-mid-settle path or its settled one.
local function storedSettling()
	if not present() then return "" end
	local seen, t = {}, {}
	for _, e in ipairs(entries()) do
		if not seen[e.owner] and isSwapped(e.owner) and isSettling(e.owner) then seen[e.owner] = true; t[#t + 1] = e.owner end
	end
	return table.concat(t, ",")
end

return {
	present = present, entries = entries, characterCount = characterCount, number = number, letter = letter, isSwapped = isSwapped, isSettling = isSettling,
	group = group, rows = rows, keyOf = keyOf, tagText = tagText, countEntries = countEntries, leftEntries = leftEntries,
	ownerOf = ownerOf, settling = settling, storedSettling = storedSettling,
}
