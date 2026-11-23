-- Fake players: what each holds (items, innate copies, wisps, Zodiac, 3 Dollar Bill), active slots and charges, cards.
wisps = {} -- item wisps: {SubType=id, Player=p}
local WM = {}; WM.__index = WM
function WM:ToFamiliar() return self end
function WM:Kill() for i, w in ipairs(wisps) do if w == self then table.remove(wisps, i) return end end end
function GetPtrHash(p) return p.hash or p.seed end

players, stageN, pendingStart = {}, 1, nil
stored = {} -- the form each swap item (Flip, Esau Jr.) swapped out
local seedN
-- startRun calls it for a new run: a test's seeds (and hashes, Index) depend on that test alone, not on the tests played before it.
function resetSeeds() seedN = 100 end
resetSeeds()
PM = {}; PM.__index = PM
function tlaz(t) return t == 29 or t == 38 end
local INNATE = {[2]={[46]=1}} -- innate copies by player type: Cain's Lucky Foot
function newPlayer(t, parent)
  seedN = seedN + 1
  return setmetatable({t=t, seed=seedN, items=tlaz(t) and {[711]=1} or t == 2 and {[46]=1} or {}, charge={}, battery={}, cards={}, trinkets={}, pocket=tlaz(t) and 711 or nil, zodiac=0, Variant=0, ControllerIndex=0, Parent=parent,
    Position=Vector(0, 0), Velocity=Vector(0, 0), data={}, Index=seedN, hash=1000000 + seedN}, PM) -- hash: each entity its own, as seeds can be shared
end
-- Copies `p` holds by id, as {without a clock (owned, innate), with one (wisps, Zodiac, 3 Dollar Bill)}.
function kinds(p)
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
function PM:GetData() return self.data end
local function consume(p, id)
  if (p.items[id] or 0) == 0 then return false end
  p.items[id] = p.items[id] - 1
  return true
end
-- shortcut: revives at once as the same entity in session 2's all-sources priority, each source alone unobserved, and a Strawman Keeper's Kill() leaving GetPlayer unobserved; model both from the next revive session
function PM:Kill()
  if self.t == 14 and self.Parent then for i, q in ipairs(players) do if q == self then table.remove(players, i) return end end end
  for i, c in ipairs(self.cards) do if c == 89 then table.remove(self.cards, i) return end end -- Soul of Lazarus: type kept
  if self.t == 8 then self.t = 11 return end -- Lazarus's innate revive
  if consume(self, 332) then return end -- Lazarus' Rags: type kept
  if consume(self, 161) then self.t = 4 return end -- Ankh: type 4
  if consume(self, 311) then self.t = 12 return end -- Judas' Shadow: Dark Judas
  -- shortcut: with posterRevives, Missing Poster revives last, at once, into The Lost (10), the trinket used (unobserved: Detailed Respawn's order); without it no revive, Poster kept (session 3d)
  if posterRevives and self:HasTrinket(23) then table.remove(self.trinkets, 1) self.t = 10 return end
  -- shortcut: a game over leaves player 0 dead with updates running; in game updates stop at 57 dead and the restart goes out from a render (session 3c); model it if the render path needs a dry check
  self.dead = true
end
function PM:IsDead() return self.dead == true end -- a revived player is alive at once here (Kill)
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
function PM:GetActiveItem(s) if s == 2 then return self.pocket or 0 elseif s == 1 then return self.secondary or 0 end return self.active or 0 end
function PM:SwapActiveItems()
  self.active, self.secondary, self.copy, self.copy2 = self.secondary, self.active, self.copy2, self.copy
  self.charge[0], self.charge[1], self.battery[0], self.battery[1] = self.charge[1], self.charge[0], self.battery[1], self.battery[0]
end
function PM:GetActiveCharge(s) return self.charge[s or 0] or 0 end
local function full(p, s) local id = p:GetActiveItem(s) return id == 711 and 4 or MAX[id] or 0 end -- REP+ Flip takes 4, MaxCharges says 6
function PM:SetActiveCharge(n, s) local f = full(self, s) self.charge[s or 0], self.battery[s or 0] = math.min(n, f), math.max(n - f, 0) end
function PM:FullCharge(s) self.charge[s or 0], self.battery[s or 0] = full(self, s), 0 return true end
function PM:NeedsCharge(s) return self:GetActiveCharge(s) < full(self, s) end
function PM:GetBatteryCharge(s) return self.battery[s or 0] or 0 end
function PM:GetCard(i) return self.cards[i + 1] or 0 end
function PM:GetTrinket(i) return self.trinkets[i + 1] or 0 end
function PM:AddTrinket(id) table.insert(self.trinkets, 1, id) end
function PM:HasTrinket(id) for _, t in ipairs(self.trinkets) do if t == id then return true end end return false end
function PM:AddCard(c) if self.pocket then self.cards[2] = c else table.insert(self.cards, 1, c) end end -- beside a pocket active: slot 1 (run 5); shortcut: a press never uses a slot-1 card, model it with the first card-beside-Flip press test
