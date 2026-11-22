-- Engine reads: the floor, the players and what they hold. A lookup finds an entity now; none is kept.
local ids = include("scripts.ids")
local PRIMARY, SECONDARY = ids.PRIMARY, ids.SECONDARY

local game = Game()
local itemConfig = Isaac.GetItemConfig()
local maxId = itemConfig:GetCollectibles().Size - 1

-- shortcut: copy of tracker.lua currentFloorName (the tracker stores this string as `entry.floor`); expose it on ReHUD.dbg if the copy drifts.
local function floorName()
	if StageAPI and StageAPI.Loaded and StageAPI.InOverriddenStage() then
		local name = StageAPI.GetCurrentStageDisplayName()
		if name then return name end
	end
	return game:GetLevel():GetName()
end

local function seedOf(p) return p:GetCollectibleRNG(1):GetSeed() end

-- The first player, and its GetPlayer index, for which pred(p) holds.
local function findPlayer(pred)
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if pred(p) then return p, i end
	end
end
local function playerOfType(t) return findPlayer(function(p) return p:GetPlayerType() == t end) end
local function playerBySeed(seed) return (findPlayer(function(p) return seedOf(p) == seed end)) end
-- An entity lookup, not a kept entity: a removed player's methods crash natively (AGENTS.md).
local function playerByHash(h) return (findPlayer(function(p) return GetPtrHash(p) == h end)) end

local function owned(p, id) return p:GetCollectibleNum(id, true) end

-- Copies of card `id` held; slots 0-3 cover every pocket slot, and GetCard reads 0 for an empty one.
local function cards(p, id)
	local n = 0
	for i = 0, 3 do
		if p:GetCard(i) == id then n = n + 1 end
	end
	return n
end

-- Item wisps of `p`: counts by item id, and the first wisp entity of each. Owners match by GetPtrHash only: a wisp's Player may be a
-- removed entity, and methods on one crash natively (lua-api-notes.md).
local function wispsOf(p)
	local hash, n, first = GetPtrHash(p), {}, {}
	for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP)) do
		local f = e:ToFamiliar()
		if f and f.Player and GetPtrHash(f.Player) == hash then
			n[e.SubType], first[e.SubType] = (n[e.SubType] or 0) + 1, first[e.SubType] or e
		end
	end
	return n, first
end

-- shortcut: copy of ReHUD 2.8's character rule (main.lua isCharacter): Strawman's Keeper and Soul of Jacob and Esau's Esau, both with a Parent,
-- get rows (user decisions 2026-11-22); expose it on ReHUD.dbg if the copy drifts.
local function isCharacter(p) return p.Variant == 0 and p:GetPlayerType() ~= PlayerType.PLAYER_THESOUL_B end

local function playable()
	local n = 0
	for i = 0, game:GetNumPlayers() - 1 do
		if isCharacter(Isaac.GetPlayer(i)) then n = n + 1 end
	end
	return n
end

local function seeds()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do t[#t + 1] = seedOf(Isaac.GetPlayer(i)) end
	return table.concat(t, ",")
end

-- id:owned/total for every item p holds; total is GetCollectibleNum(id, false), so wisps and the Zodiac copy count too.
local function heldItems(p)
	local t = {}
	for id = 1, maxId do
		local total = itemConfig:GetCollectible(id) and p:GetCollectibleNum(id, false) or 0
		if total > 0 then t[#t + 1] = id .. ":" .. owned(p, id) .. "/" .. total end
	end
	return table.concat(t, " ")
end

local function chargeOf(p, id, slot) return p and p:GetActiveItem(slot) == id and p:GetActiveCharge(slot) end

local function pedestals(id) return #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id) end

local function slots(p) return "primary " .. p:GetActiveItem(PRIMARY) .. " secondary " .. p:GetActiveItem(SECONDARY) end

local function itemCounts(p)
	local t = {}
	for id = 1, maxId do
		if itemConfig:GetCollectible(id) then
			local n = p:GetCollectibleNum(id, false)
			if n > 0 then t[id] = n end
		end
	end
	return t
end

local function countsText(t)
	local ids, out = {}, {}
	for id in pairs(t) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do out[#out + 1] = id .. "x" .. t[id] end
	return #out > 0 and table.concat(out, " ") or "-"
end

local function helper(t)
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		if p:GetPlayerType() == t and p.Parent then return p end
	end
end

return {
	itemConfig = itemConfig, maxId = maxId, floorName = floorName, seedOf = seedOf, findPlayer = findPlayer, playerOfType = playerOfType,
	playerBySeed = playerBySeed, playerByHash = playerByHash, owned = owned, cards = cards, wispsOf = wispsOf, isCharacter = isCharacter,
	playable = playable, seeds = seeds, heldItems = heldItems, chargeOf = chargeOf, pedestals = pedestals, slots = slots,
	itemCounts = itemCounts, countsText = countsText, helper = helper,
}
