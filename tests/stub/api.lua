-- Fake Isaac API for tests/test_harness.py: enums, callbacks, the mod object, the log and the game. Not the real engine: just enough
-- for the harness's steps to see their postconditions. The other tests/stub files add players, characters, input, the console and ReHUD.
ModCallbacks = {MC_POST_UPDATE=1, MC_POST_RENDER=2, MC_USE_ITEM=3, MC_INPUT_ACTION=13, MC_POST_GAME_STARTED=15, MC_PRE_USE_ITEM=23, MC_POST_PLAYER_UPDATE=31}
CallbackPriority = {EARLY=-100, LATE=100}
EntityType = {ENTITY_PLAYER=1, ENTITY_FAMILIAR=3, ENTITY_PICKUP=5}; FamiliarVariant = {ITEM_WISP=237}; PickupVariant = {PICKUP_COLLECTIBLE=100}
CollectibleType = {COLLECTIBLE_FLIP=711, COLLECTIBLE_ESAU_JR=703, COLLECTIBLE_CLICKER=482, COLLECTIBLE_BIRTHRIGHT=619, COLLECTIBLE_D6=105, COLLECTIBLE_YUM_HEART=45, COLLECTIBLE_SCHOOLBAG=534, COLLECTIBLE_STRAW_MAN=667,
  COLLECTIBLE_ANKH=161, COLLECTIBLE_JUDAS_SHADOW=311, COLLECTIBLE_LAZARUS_RAGS=332}
TrinketType = {TRINKET_MISSING_POSTER=23}
PlayerType = {PLAYER_ISAAC=0, PLAYER_ISAAC_B=21, PLAYER_CAIN=2, PLAYER_KEEPER=14, PLAYER_LAZARUS=8, PLAYER_EDEN=9, PLAYER_LAZARUS2=11, PLAYER_THEFORGOTTEN=16, PLAYER_THESOUL=17, PLAYER_JACOB=19, PLAYER_ESAU=20,
  PLAYER_LAZARUS_B=29, PLAYER_LAZARUS2_B=38, PLAYER_THEFORGOTTEN_B=35, PLAYER_JACOB_B=37, PLAYER_THESOUL_B=40}
ActiveSlot = {SLOT_PRIMARY=0, SLOT_SECONDARY=1, SLOT_POCKET=2}
Card = {CARD_SOUL_LAZARUS=89, CARD_SOUL_FORGOTTEN=95, CARD_SOUL_JACOB=97}
InputHook = {IS_ACTION_PRESSED=0, IS_ACTION_TRIGGERED=1, GET_ACTION_VALUE=2}
ButtonAction = {ACTION_ITEM=9, ACTION_PILLCARD=10, ACTION_DROP=11}
local VM = {}; VM.__index = VM
function Vector(x, y) return setmetatable({X=x, Y=y}, VM) end
VM.__add = function(a, b) return Vector(a.X + b.X, a.Y + b.Y) end
VM.__sub = function(a, b) return Vector(a.X - b.X, a.Y - b.Y) end
Direction = {NO_DIRECTION=-1}
function VM:Distance(o) return math.sqrt((self.X - o.X) ^ 2 + (self.Y - o.Y) ^ 2) end
CBS = {}
modData = "" -- set by the test: what mod:LoadData() returns
function addPriorityCallback(_, id, priority, f, arg)
  local callbacks = CBS[id] or {}
  CBS[id] = callbacks
  local i = #callbacks + 1
  while i > 1 and callbacks[i - 1].priority > priority do i = i - 1 end
  table.insert(callbacks, i, {f=f, arg=arg, priority=priority})
end
function RegisterMod(name)
  return {Name=name, AddPriorityCallback=addPriorityCallback,
    AddCallback=function(m, id, f, arg) addPriorityCallback(m, id, 0, f, arg) end, LoadData=function() return modData end}
end
LOG = {}
print = function() end
Isaac = {}
function Isaac.DebugString(s) LOG[#LOG+1] = s end
function Isaac.RenderText() end
SAVED = nil -- the last Isaac.SaveModData text
function Isaac.SaveModData(_, s) SAVED = s end
MAX = {[482]=6, [703]=1, [711]=6}
function Isaac.GetItemConfig() return {GetCollectibles=function() return {Size=733} end, GetCollectible=function(_, id) return id <= 732 and {MaxCharges=MAX[id] or 0} or nil end} end

ignoreRestart = false -- set by the test: `restart` does nothing
ignorePress = false -- set by the test: the engine polls input but ignores a forced press
ignoreDrop = false -- set by the test: the engine ignores a forced drop press, so drop presses take their fallback
lockedType = nil -- set by the test: `restart` of this type starts Isaac instead
-- shortcut: a locked type's restart starts Isaac (unobserved: the recon characters are all unlocked, session 2); model it if a test needs a locked character
restartRolls = false -- set by the test: a restart rolls a new seed even after a seed command
noSpend = false -- set by the test: uses swap characters but spend no charge or card
jrSameSeed = false -- set by the test: Esau Jr. makes a new entity with the presser's seed and type, c4 re-rolled to c53 (obsy b run 1, after a Continue);
-- a number n: only the next n Esau Jr. presses do
wrongFloor = false -- set by the test: the fake ReHUD lists new entries on a wrong floor
tlazRoll = 35 -- set by the test: the type Clicker rolls from Tainted Lazarus (35 in 11 of 11 in game, with the Soul; 29 from 38 in run 8)
-- Negative modes for the invariants, set by the test: the fake ReHUD never lists c4 (missCopy), lists each c4 twice (dupCopy), keeps the
-- stored form unmerged when a Tainted Lazarus turns another character (keepStored), marks a vanished owner's list left instead of merging
-- it (leaveNotMerge), lists new entries under the next floor (laterFloor), keys characters by seed only, no tag (untagged), lists a row
-- of no character, stored as an Esau Jr. one (phantomRow).
missCopy, dupCopy, keepStored, leaveNotMerge, laterFloor, untagged, phantomRow = false, false, false, false, false, false, false

frame = 0
G = {GetNumPlayers=function() return #players end, GetFrameCount=function() return frame end,
  GetSeeds=function() return {GetStartSeedString=function() return startSeed end} end, GetLevel=function() return {GetCurrentRoomIndex=function() return 84 end, GetName=function() return "Floor"..stageN end, GetStage=function() return stageN end} end}
function Game() return G end
function Isaac.GetPlayer(i) return players[i+1] end

function fire(id, ...)
  for _, c in ipairs(CBS[id] or {}) do
    if c.arg == nil or c.arg == (...) then
      local r = c.f(nil, ...)
      if id == 23 and r ~= nil then return r end
    end
  end
end
-- The run's start seed; `seeded` once a `seed` command set it, `seedStart` while its own game start is pending (tests/stub/console.lua).
startSeed, seeded, seedStart, seedRolls = nil, false, false, 0
function startRun(t, cont)
  if not cont then
    -- a restart keeps a seed a `seed` command set (sessions 1-2: every type, after Continues) and rolls one otherwise (session 1)
    if seedStart then seedStart = false
    elseif not seeded or restartRolls then seedRolls = seedRolls + 1; startSeed = "STUB " .. seedRolls end
    -- shortcut: unobserved whether the engine's GetFrameCount restarts with a run; it does here, so TIMING frames depend on the test alone, model it from the next session's restart INFO frame
    resetSeeds(); frame = 0
    players = {newPlayer(t)}; if t == 19 then players[2] = newPlayer(20) end
    stageN = 1; stored, wisps, pickups = {}, {}, {}; resetFakeReHUD()
  end
  fire(15, cont)
end
