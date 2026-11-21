-- Fake Isaac API and a fake ReHUD for tests/test_harness.py. Not the real engine: just enough for main.lua's steps to see their postconditions.
ModCallbacks = {MC_POST_UPDATE=1, MC_POST_RENDER=2, MC_POST_GAME_STARTED=15}
EntityType = {ENTITY_FAMILIAR=3}; FamiliarVariant = {ITEM_WISP=237}
CollectibleType = {COLLECTIBLE_FLIP=711, COLLECTIBLE_ESAU_JR=703, COLLECTIBLE_CLICKER=482, COLLECTIBLE_BIRTHRIGHT=619}
PlayerType = {PLAYER_ISAAC=0, PLAYER_JACOB=19, PLAYER_ESAU=20, PLAYER_LAZARUS_B=29}
ActiveSlot = {SLOT_PRIMARY=0, SLOT_POCKET=2}
Card = {CARD_SOUL_JACOB=97}
CBS = {}
function RegisterMod() return {AddCallback=function(_, id, f) CBS[id] = CBS[id] or {}; table.insert(CBS[id], f) end} end
LOG = {}
print = function() end
Isaac = {}
function Isaac.DebugString(s) LOG[#LOG+1] = s end
function Isaac.RenderText() end
function Isaac.GetItemConfig() return {GetCollectibles=function() return {Size=733} end, GetCollectible=function(_, id) return id <= 732 and {} or nil end} end
function Isaac.FindByType() return {} end
function GetPtrHash(p) return p.seed end

ignoreRestart = false -- set by the test: `restart` does nothing
players, stageN, pendingStart = {}, 1, nil
local stored = {} -- the form each swap item (Flip, Esau Jr.) swapped out
local seedN = 100
local PM = {}; PM.__index = PM
function newPlayer(t, parent) seedN = seedN + 1; return setmetatable({t=t, seed=seedN, items={}, Variant=0, ControllerIndex=0, Parent=parent}, PM) end
function PM:GetPlayerType() return self.t end
function PM:GetCollectibleRNG() local s = self.seed; return {GetSeed=function() return s end} end
function PM:GetCollectibleCount() local n = 0 for _, c in pairs(self.items) do n = n + c end return n end
function PM:GetCollectibleNum(id) return self.items[id] or 0 end
function PM:IsCoopGhost() return false end
function PM:GetActiveItem() return self.active or 0 end
function PM:AddCollectible(id)
  self.items[id] = (self.items[id] or 0) + 1
  if id == 482 or id == 703 then self.active = id end
  if id == 619 and (self.t == 29 or self.t == 38) then players[2] = stored[711] or newPlayer(self.t == 29 and 38 or 29); stored[711] = nil end
end
local function merge(into, from) for id, n in pairs(from.items) do into.items[id] = (into.items[id] or 0) + n end end
function PM:ChangePlayerType(t)
  if stored[711] then merge(self, stored[711]); stored[711] = nil end
  self.t = t
end
function PM:UseCard() players[#players+1] = newPlayer(20, self) end
function PM:UseActiveItem(id)
  if id == 711 and players[2] and (players[2].t == 29 or players[2].t == 38) then players[1], players[2] = players[2], players[1]
  elseif id == 711 or id == 703 then
    local other = stored[id] or newPlayer(id == 711 and (self.t == 29 and 38 or 29) or self.t)
    if id == 703 then other.active = 703 end
    stored[id], players[1] = players[1], other
  elseif id == 482 then
    if self.t == 19 then merge(self, players[2]); players[2] = nil; self.t = 5 else self.t = 19; players[2] = newPlayer(20) end
  end
end
G = {GetNumPlayers=function() return #players end, GetLevel=function() return {GetName=function() return "Floor"..stageN end, GetStage=function() return stageN end} end}
function Game() return G end
function Isaac.GetPlayer(i) return players[i+1] end
function Isaac.ExecuteCommand(c)
  local a, b = c:match("^(%S+) c?(%d+)$")
  b = tonumber(b)
  if a == "restart" then if not ignoreRestart then pendingStart = b end
  elseif a == "giveitem" then players[1]:AddCollectible(b)
  elseif a == "remove" then
    players[1].items[b] = math.max(0, (players[1].items[b] or 1) - 1)
    if b == 619 and players[2] then stored[711], players[2] = players[2], nil end
  elseif a == "stage" then stageN = b end
end

-- Fake ReHUD: one entry per copy held by any player or stored form, listed under the floor it first appeared on, owner its first holder;
-- a new seed settles for 20 updates.
local entries, settle = {}, {}
ReHUD = {dbg={tracker={entries=entries}, roster={isSettling=function(key) return (settle[key] or 0) > 0 end}}}
function fakeTrack()
  local count, holder = {}, {}
  local all = {}
  for _, p in ipairs(players) do all[#all+1] = p end
  for _, p in pairs(stored) do all[#all+1] = p end
  for _, p in ipairs(all) do
    if settle[p.seed] == nil then settle[p.seed] = 20 elseif settle[p.seed] > 0 then settle[p.seed] = settle[p.seed] - 1 end
    for id, n in pairs(p.items) do count[id] = (count[id] or 0) + n; holder[id] = holder[id] or p.seed end
  end
  local have = {}
  for i = #entries, 1, -1 do
    local e = entries[i]
    have[e.id] = (have[e.id] or 0) + 1
    if have[e.id] > (count[e.id] or 0) then table.remove(entries, i) else e.owner = holder[e.id] end
  end
  for id, n in pairs(count) do
    for _ = (have[id] or 0) + 1, n do entries[#entries+1] = {id=id, number=0, owner=holder[id], floor="Floor"..stageN, temporary=false} end
  end
end
function fire(id, ...) for _, f in ipairs(CBS[id] or {}) do f(nil, ...) end end
function startRun(t, cont)
  if not cont then
    players = {newPlayer(t)}; if t == 19 then players[2] = newPlayer(20) end
    stageN = 1; for k in pairs(stored) do stored[k] = nil end; for i = #entries, 1, -1 do entries[i] = nil end
  end
  fire(15, cont)
end
