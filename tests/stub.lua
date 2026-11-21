-- Fake Isaac API and a fake ReHUD for tests/test_harness.py. Not the real engine: just enough for main.lua's steps to see their postconditions.
ModCallbacks = {MC_POST_UPDATE=1, MC_POST_RENDER=2, MC_USE_ITEM=3, MC_INPUT_ACTION=13, MC_POST_GAME_STARTED=15, MC_POST_PLAYER_UPDATE=31}
EntityType = {ENTITY_FAMILIAR=3}; FamiliarVariant = {ITEM_WISP=237}
CollectibleType = {COLLECTIBLE_FLIP=711, COLLECTIBLE_ESAU_JR=703, COLLECTIBLE_CLICKER=482, COLLECTIBLE_BIRTHRIGHT=619}
PlayerType = {PLAYER_ISAAC=0, PLAYER_CAIN=2, PLAYER_JACOB=19, PLAYER_ESAU=20, PLAYER_LAZARUS_B=29, PLAYER_LAZARUS2_B=38, PLAYER_THESOUL_B=40}
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
wisps = {} -- item wisps: {SubType=id, Player=p}
local WM = {}; WM.__index = WM
function WM:ToFamiliar() return self end
function WM:Kill() for i, w in ipairs(wisps) do if w == self then table.remove(wisps, i) return end end end
function Isaac.FindByType() return {table.unpack(wisps)} end
function GetPtrHash(p) return p.seed end

ignoreRestart = false -- set by the test: `restart` does nothing
ignorePress = false -- set by the test: the engine polls input but ignores a forced press
noSpend = false -- set by the test: uses swap characters but spend no charge or card
wrongFloor = false -- set by the test: the fake ReHUD lists new entries on a wrong floor
tlazRoll = 21 -- set by the test: the type Clicker rolls from Tainted Lazarus
players, stageN, pendingStart = {}, 1, nil
local stored = {} -- the form each swap item (Flip, Esau Jr.) swapped out
local seedN = 100
local PM = {}; PM.__index = PM
local function tlaz(t) return t == 29 or t == 38 end
local INNATE = {[2]={[46]=1}} -- innate copies by player type: Cain's Lucky Foot
function newPlayer(t, parent)
  seedN = seedN + 1
  return setmetatable({t=t, seed=seedN, items=tlaz(t) and {[711]=1} or t == 2 and {[46]=1} or {}, charge={}, battery={}, cards={}, pocket=tlaz(t) and 711 or nil, zodiac=0, Variant=0, ControllerIndex=0, Parent=parent}, PM)
end
-- Copies `p` holds by id, as {without a clock (owned, innate), with one (wisps, Zodiac, 3 Dollar Bill)}.
local function kinds(p)
  local k = {}
  local function add(id, i) k[id] = k[id] or {0, 0}; k[id][i] = k[id][i] + 1 end
  for id, n in pairs(p.items) do for _ = 1, n do add(id, 1) end end
  for id, n in pairs(INNATE[p.t] or {}) do for _ = 1, n do add(id, 1) end end
  for _, w in ipairs(wisps) do if w.Player == p then add(w.SubType, 2) end end
  if p.zodiac ~= 0 then add(p.zodiac, 2) end
  if p.bill then add(p.bill, 2) end
  return k
end
function PM:ToPlayer() return self end
function PM:GetPlayerType() return self.t end
function PM:GetCollectibleRNG() local s = self.seed; return {GetSeed=function() return s end} end
function PM:GetCollectibleCount() local n = 0 for _, c in pairs(self.items) do n = n + c end return n end
function PM:GetCollectibleNum(id, onlyOwned)
  if onlyOwned then return self.items[id] or 0 end
  local c = kinds(self)[id]
  return c and c[1] + c[2] or 0
end
function PM:GetZodiacEffect() return self.zodiac end
function PM:AddItemWisp(id) wisps[#wisps+1] = setmetatable({SubType=id, Player=self}, WM) end
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
  local from = stored[711]
  if from then merge(self, from); stored[711] = nil end
  self.t = t
  if not tlaz(t) then self.pocket, self.items[711] = nil, nil -- the engine removes Flip (run 5)
  elseif from then -- Flip kept once, a fresh other form stored (run 8), unseen by ReHUD until it plays
    self.items[711], stored[711] = 1, newPlayer(t == 29 and 38 or 29); stored[711].unseen = true
  end
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
    if p.t == 19 then merge(p, players[2]); players[2] = nil; p.t = 5
    elseif tlaz(p.t) then p:ChangePlayerType(tlazRoll) -- like ChangePlayerType: into 21 (in-game 2026-11-21), into 29 from 38 (run 8)
    else p.t = 19; players[2] = newPlayer(20) end
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
  -- 3 Dollar Bill: one granted item, changing every 180 updates (about 6 s, wiki)
  for _, p in ipairs(players) do
    if (p.items[191] or 0) > 0 then p.billT = (p.billT or -1) + 1; p.bill = 10 + math.floor(p.billT / 180) % 3 end
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
  elseif a == "stage" then
    stageN = b
    for _, p in ipairs(players) do if (p.items[392] or 0) > 0 then p.zodiac = 300 + b end end -- the stub's guess: Zodiac grants from the next floor, a new item each
  end
end

-- Fake ReHUD: one entry per copy and kind held by a character (no Parent, not the Tainted Soul) or stored form, listed under the floor it
-- first appeared on; a vanished owner's entries go to player 0 (a merge) and its number is forgotten. Numbers are first seen; a new
-- seed settles for 20 updates, frozen while stored (roster.lua).
local entries, settle, numbers, nextNumber = {}, {}, {}, 0
local tracker = {entries=entries, characterCount=0}
local function isStored(key) for _, p in pairs(stored) do if p.seed == key then return true end end return false end
ReHUD = {dbg={tracker=tracker, roster={isSettling=function(key) return (settle[key] or 0) > 0 end, isSwapped=isStored, number=function(key) return numbers[key] end}}}
function fakeTrack()
  local all, held = {}, {}
  for _, p in ipairs(players) do
    if not p.Parent and p.t ~= 40 then
      all[#all+1] = p
      p.unseen = nil
      if settle[p.seed] == nil then settle[p.seed] = 20 elseif settle[p.seed] > 0 then settle[p.seed] = settle[p.seed] - 1 end
    end
  end
  for _, p in pairs(stored) do if not p.unseen then all[#all+1] = p end end
  for _, p in ipairs(all) do
    if not numbers[p.seed] then numbers[p.seed], nextNumber = nextNumber, nextNumber + 1 end
    held[p.seed] = kinds(p)
  end
  for key in pairs(numbers) do if not held[key] then numbers[key] = nil end end
  local have = {}
  local function slot(owner, id, kind) return owner .. ":" .. id .. ":" .. kind end
  for i = #entries, 1, -1 do -- newest first, so the oldest of a kind goes
    local e = entries[i]
    if not held[e.owner] then e.owner = players[1].seed end
    local kind = e.temporary and 2 or 1
    local s = slot(e.owner, e.id, kind)
    have[s] = (have[s] or 0) + 1
    local c = held[e.owner][e.id]
    if have[s] > (c and c[kind] or 0) then table.remove(entries, i) else e.number = numbers[e.owner] end
  end
  for _, p in ipairs(all) do
    for id, c in pairs(held[p.seed]) do
      for kind = 1, 2 do
        for _ = (have[slot(p.seed, id, kind)] or 0) + 1, c[kind] do
          entries[#entries+1] = {id=id, number=numbers[p.seed], owner=p.seed, floor=wrongFloor and "Wrong" or "Floor"..stageN, temporary=kind == 2}
        end
      end
    end
  end
  tracker.characterCount = #all
end
function fire(id, ...) for _, c in ipairs(CBS[id] or {}) do c.f(nil, ...) end end
function startRun(t, cont)
  if not cont then
    players = {newPlayer(t)}; if t == 19 then players[2] = newPlayer(20) end
    stageN = 1; stored, wisps, numbers, nextNumber = {}, {}, {}, 0; for i = #entries, 1, -1 do entries[i] = nil end
  end
  fire(15, cont)
end
