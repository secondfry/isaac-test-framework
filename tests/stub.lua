-- Fake Isaac API and a fake ReHUD for tests/test_harness.py. Not the real engine: just enough for main.lua's steps to see their postconditions.
ModCallbacks = {MC_POST_UPDATE=1, MC_POST_RENDER=2, MC_USE_ITEM=3, MC_INPUT_ACTION=13, MC_POST_GAME_STARTED=15, MC_POST_PLAYER_UPDATE=31}
EntityType = {ENTITY_FAMILIAR=3}; FamiliarVariant = {ITEM_WISP=237}
CollectibleType = {COLLECTIBLE_FLIP=711, COLLECTIBLE_ESAU_JR=703, COLLECTIBLE_CLICKER=482, COLLECTIBLE_BIRTHRIGHT=619}
PlayerType = {PLAYER_ISAAC=0, PLAYER_JACOB=19, PLAYER_ESAU=20, PLAYER_LAZARUS_B=29, PLAYER_LAZARUS2_B=38}
ActiveSlot = {SLOT_PRIMARY=0, SLOT_POCKET=2}
Card = {CARD_SOUL_JACOB=97}
InputHook = {IS_ACTION_PRESSED=0, IS_ACTION_TRIGGERED=1, GET_ACTION_VALUE=2}
ButtonAction = {ACTION_ITEM=9, ACTION_PILLCARD=10}
CBS = {}
modData = "" -- set by the test: what mod:LoadData() returns
function RegisterMod(name)
  return {Name=name, AddCallback=function(_, id, f, arg) CBS[id] = CBS[id] or {}; table.insert(CBS[id], {f=f, arg=arg}) end, LoadData=function() return modData end}
end
LOG = {}
print = function() end
Isaac = {}
function Isaac.DebugString(s) LOG[#LOG+1] = s end
function Isaac.RenderText() end
local MAX = {[482]=6, [703]=1, [711]=6}
function Isaac.GetItemConfig() return {GetCollectibles=function() return {Size=733} end, GetCollectible=function(_, id) return id <= 732 and {MaxCharges=MAX[id] or 0} or nil end} end
function Isaac.FindByType() return {} end
function GetPtrHash(p) return p.seed end

ignoreRestart = false -- set by the test: `restart` does nothing
ignorePress = false -- set by the test: the engine polls input but ignores a forced press
noSpend = false -- set by the test: uses swap characters but spend no charge or card
wrongFloor = false -- set by the test: the fake ReHUD lists new entries on a wrong floor
players, stageN, pendingStart = {}, 1, nil
local stored = {} -- the form each swap item (Flip, Esau Jr.) swapped out
local seedN = 100
local PM = {}; PM.__index = PM
local function tlaz(t) return t == 29 or t == 38 end
function newPlayer(t, parent)
  seedN = seedN + 1
  return setmetatable({t=t, seed=seedN, items=tlaz(t) and {[711]=1} or {}, charge={}, battery={}, cards={}, pocket=tlaz(t) and 711 or nil, Variant=0, ControllerIndex=0, Parent=parent}, PM)
end
function PM:ToPlayer() return self end
function PM:GetPlayerType() return self.t end
function PM:GetCollectibleRNG() local s = self.seed; return {GetSeed=function() return s end} end
function PM:GetCollectibleCount() local n = 0 for _, c in pairs(self.items) do n = n + c end return n end
function PM:GetCollectibleNum(id) return self.items[id] or 0 end
function PM:IsCoopGhost() return false end
function PM:GetActiveItem(s) if s == 2 then return self.pocket or 0 end return self.active or 0 end
function PM:GetActiveCharge(s) return self.charge[s or 0] or 0 end
local function full(p, s) local id = p:GetActiveItem(s) return id == 711 and 4 or MAX[id] or 0 end -- REP+ Flip takes 4, MaxCharges says 6
function PM:SetActiveCharge(n, s) local f = full(self, s) self.charge[s or 0], self.battery[s or 0] = math.min(n, f), math.max(n - f, 0) end
function PM:FullCharge(s) self.charge[s or 0], self.battery[s or 0] = full(self, s), 0 return true end
function PM:NeedsCharge(s) return self:GetActiveCharge(s) < full(self, s) end
function PM:GetBatteryCharge(s) return self.battery[s or 0] or 0 end
function PM:GetCard(i) return self.cards[i + 1] or 0 end
function PM:AddCard(c) if self.pocket then self.cards[2] = c else table.insert(self.cards, 1, c) end end -- beside a pocket active: slot 1 (run 5); shortcut: a press never uses a slot-1 card, model it with the first card-beside-Flip scenario
function PM:AddCollectible(id)
  self.items[id] = (self.items[id] or 0) + 1
  if id == 482 or id == 703 then self.active = id end
  if id == 619 and tlaz(self.t) then players[2] = stored[711] or newPlayer(self.t == 29 and 38 or 29); stored[711] = nil end
end
local function merge(into, from) for id, n in pairs(from.items) do into.items[id] = (into.items[id] or 0) + n end end
function PM:ChangePlayerType(t)
  if stored[711] then merge(self, stored[711]); stored[711] = nil end
  self.t = t
  if not tlaz(t) then self.pocket, self.items[711] = nil, nil end -- the engine removes Flip (run 5)
end

-- Flip, Esau Jr. and Clicker on player `p`. A stored form's charge travels with the item: the new form arrives with what the presser
-- had left (run 6: one sample per item).
local function swapForm(p, id)
  if id == 711 and players[2] and tlaz(players[2].t) then players[1], players[2] = players[2], players[1]
  elseif id == 711 or id == 703 then
    local other, s = stored[id] or newPlayer(id == 711 and (p.t == 29 and 38 or 29) or p.t), id == 711 and 2 or 0
    if id == 703 then other.active = 703 end
    other.charge[s], other.battery[s] = p.charge[s], p.battery[s]
    stored[id], players[1] = players[1], other
  elseif id == 482 then
    if p.t == 19 then merge(p, players[2]); players[2] = nil; p.t = 5 else p.t = 19; players[2] = newPlayer(20) end
  end
end

-- The use behind a press of `button` by `p`: a held card first for PILLCARD, then the pocket active; an active needs a full charge.
-- MC_USE_ITEM runs before the discharge (IsaacDocs); the form swap is queued in `swaps`, as the engine stores the presser only after
-- its MC_POST_PLAYER_UPDATE (run 6).
local function use(p, button, swaps)
  if button == 10 and p.cards[1] then
    local c = p.cards[1]
    if not noSpend then table.remove(p.cards, 1) end
    if c == 97 then players[#players+1] = newPlayer(20, p) end
    return
  end
  local slot = button == 10 and 2 or 0
  local id = p:GetActiveItem(slot)
  if id == 0 or p:NeedsCharge(slot) then return end
  fire(3, id, nil, p, 0, slot, 0)
  if not noSpend then p.charge[slot] = 0 end
  swaps[#swaps+1] = {p, id}
end

local function input(e, hook, button)
  for _, c in ipairs(CBS[13] or {}) do
    if c.arg == nil or c.arg == hook then
      local r = c.f(nil, e, hook, button)
      if r ~= nil then return r end
    end
  end
end
-- One game update's input. PILLCARD with Flip in the pocket: triggered, pressed, triggered, Flip reading the second triggered; with only
-- cards: no pressed poll (runs 4-5), a card reading the first triggered. ITEM: one triggered poll. The stub's guess: a card is not used
-- when the second triggered is true too (run 3's flood used no card).
function engineInput()
  local swaps = {}
  for _, p in ipairs({table.unpack(players)}) do
    if input(p, 1, 9) == true and not ignorePress then use(p, 9, swaps) end
    local t1 = input(p, 1, 10) == true
    if p.pocket then input(p, 0, 10) end
    local t2 = input(p, 1, 10) == true
    if not ignorePress then
      if p.cards[1] then
        if t1 and not t2 then use(p, 10, swaps) end
      elseif t2 then use(p, 10, swaps) end
    end
  end
  for _, p in ipairs(players) do fire(31, p) end
  for _, s in ipairs(swaps) do swapForm(s[1], s[2]) end
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

-- Fake ReHUD: one entry per copy held by any character (no Parent) or stored form, listed under the floor it first appeared on, owner
-- its first holder; a new seed settles for 20 updates, frozen while stored (roster.lua).
local entries, settle = {}, {}
local function isStored(key) for _, p in pairs(stored) do if p.seed == key then return true end end return false end
ReHUD = {dbg={tracker={entries=entries}, roster={isSettling=function(key) return (settle[key] or 0) > 0 end, isSwapped=isStored}}}
function fakeTrack()
  local count, holder, all = {}, {}, {}
  for _, p in ipairs(players) do
    if not p.Parent then
      all[#all+1] = p
      if settle[p.seed] == nil then settle[p.seed] = 20 elseif settle[p.seed] > 0 then settle[p.seed] = settle[p.seed] - 1 end
    end
  end
  for _, p in pairs(stored) do all[#all+1] = p end
  for _, p in ipairs(all) do
    for id, n in pairs(p.items) do count[id] = (count[id] or 0) + n; holder[id] = holder[id] or p.seed end
  end
  local have = {}
  for i = #entries, 1, -1 do
    local e = entries[i]
    have[e.id] = (have[e.id] or 0) + 1
    if have[e.id] > (count[e.id] or 0) then table.remove(entries, i) else e.owner = holder[e.id] end
  end
  for id, n in pairs(count) do
    for _ = (have[id] or 0) + 1, n do entries[#entries+1] = {id=id, number=0, owner=holder[id], floor=wrongFloor and "Wrong" or "Floor"..stageN, temporary=false} end
  end
end
function fire(id, ...) for _, c in ipairs(CBS[id] or {}) do c.f(nil, ...) end end
function startRun(t, cont)
  if not cont then
    players = {newPlayer(t)}; if t == 19 then players[2] = newPlayer(20) end
    stageN = 1; for k in pairs(stored) do stored[k] = nil end; for i = #entries, 1, -1 do entries[i] = nil end
  end
  fire(15, cont)
end
