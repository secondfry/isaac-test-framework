-- Fake characters: pedestals, items that add or swap characters (Strawman, Birthright, Flip, Esau Jr., Clicker), ChangePlayerType and
-- the fake user's walk.
pickups = {} -- spawned pedestals: {Type, Variant, SubType, Position}
function Isaac.FindByType(t, v, s)
  if t == 3 then return {table.unpack(wisps)} end
  local r = {}
  for _, e in ipairs(pickups) do if e.Type == t and ((v or -1) < 0 or e.Variant == v) and ((s or -1) < 0 or e.SubType == s) then r[#r+1] = e end end
  return r
end
function Isaac.Spawn(t, v, s, pos)
  local e = {Type=t, Variant=v, SubType=s, Position=Vector(pos.X, pos.Y), Wait=20}; e.ToPickup = function() return e end; pickups[#pickups+1] = e
  return e
end

-- Flip partners, both ways: the two forms of one Tainted Lazarus. Returns `b`.
local function pair(a, b) a.partner, b.partner = b, a return b end
function PM:AddCollectible(id)
  self.items[id] = (self.items[id] or 0) + 1
  if id == 45 or id == 105 or id == 482 or id == 703 then -- an active: the held one moves to a free Schoolbag slot, else is lost
    local kept = self.items[534] and self.active and not self.secondary
    if kept then self.secondary, self.copy2 = self.active, self.copy
    elseif self.active then self.items[self.active] = nil end
    self.active, self.copy = id, id == 703 and {} or nil
    if not kept then self.items[id] = 1 end -- each Esau Jr. copy records the character it last swapped out
  end
  if id == 667 then players[#players+1] = newPlayer(14, self) end -- Strawman's Keeper
  if id == 392 then self.zodiac = 300 + stageN end -- Zodiac grants on its own floor (S1b in game: within 1 update)
  if id == 619 and tlaz(self.t) then
    players[2] = pair(self, stored[711] or newPlayer(self.t == 29 and 38 or 29))
    stored[711] = nil
    if birthrightDeadFirst and players[2].t == 38 then
      players[2].items[619] = self.items[619]
      players[1], players[2] = players[2], players[1]
    end
  end
end
local function merge(into, from) for id, n in pairs(from.items) do into.items[id] = (into.items[id] or 0) + n end end
function PM:ChangePlayerType(t)
  local from = stored[711]
  if from and from.partner ~= self then from = nil end -- the stub's guess (P4c): only the presser's own Flip partner merges, not an Esau Jr. original's
  if keepStored and not tlaz(t) then from = nil end
  if from then merge(self, from); stored[711] = nil end
  self.t = t
  if not tlaz(t) then self.pocket, self.items[711] = nil, nil -- the engine removes Flip (run 5)
  elseif from then -- Flip kept once, a fresh other form stored (run 8), unseen by ReHUD until it plays
    self.items[711], stored[711] = 1, pair(self, newPlayer(t == 29 and 38 or 29)); stored[711].unseen = true
  end
end

-- Flip, Esau Jr. and Clicker on player `p`. A stored form's charge travels with the item: the new form arrives with what the presser
-- had left (run 6: one sample per item).
function swapForm(p, id)
  if id == 711 and players[2] and tlaz(players[2].t) then players[1], players[2] = players[2], players[1]
  elseif id == 703 and jrSameSeed then
    if math.type(jrSameSeed) == "integer" then jrSameSeed = jrSameSeed > 1 and jrSameSeed - 1 end
    local q = setmetatable({}, PM)
    for k, v in pairs(p) do q[k] = v end
    q.hash, q.items, q.data = (p.hash or p.seed) + 100000, {}, {}
    for k, v in pairs(p.items) do q.items[k == 4 and 53 or k] = v end
    for k, r in ipairs(players) do if r == p then players[k] = q end end
  elseif id == 703 and not (p.copy and p.copy.held) and tlaz(p.t) and p.partner and (players[1] == p.partner or players[2] == p.partner) then
    -- A Birthright twin's fresh copy (obsyb1-2): a form on the twin's seed, the presser and the twin stored together (players 2 -> 1).
    local twin, form = p.partner, newPlayer(p.t)
    form.seed, form.jrForm, form.active, form.items[703], form.copy = twin.seed, true, 703, 1, p.copy or {}
    form.copy.held, form.copy.twin, form.charge[0] = p, twin, p.charge[0]
    stored[p], stored[twin], players = p, twin, {form}
  elseif id == 703 and p.copy and p.copy.twin then
    -- Pressing back returns both (1 -> 2), the presser first.
    local copy = p.copy
    local back, twin = copy.held, copy.twin
    back.active, back.copy, back.items[703], back.charge[0], copy.held, copy.twin = 703, copy, back.items[703] or 1, p.charge[0], p, nil
    stored[back], stored[twin], stored[p] = nil, nil, p
    players = {back, twin}
  elseif id == 711 or id == 703 then
    local copy = id == 703 and (p.copy or {})
    local fresh = not (copy and copy.held) and not (not copy and stored[id])
    local other, s = (copy and copy.held) or (not copy and stored[id]) or newPlayer(id == 711 and (p.t == 29 and 38 or 29) or p.t), id == 711 and 2 or 0
    if copy and fresh then
      other.jrForm = true
      -- Tainted Lazarus's new Esau Jr. form takes its stored Dead form's seed (console 2026-11-22); otherwise a character's later fresh
      -- copies make forms on the seed of the first form it made, typed as the presser (obsx run2-6 "original loses Esau Jr." press #1)
      if p.t == 29 and stored[711] and stored[711].t == 38 then other.seed = stored[711].seed
      elseif p.firstForm then other.seed = p.firstForm end
      p.firstForm = p.firstForm or other.seed
    end
    -- A Flip of an Esau Jr. form with no stored Dead form keeps the form's seed (obsx run2/run6 "obs esaujr flip")
    if not copy and fresh and p.jrForm then other.seed = p.seed end
    if copy then other.active, other.copy, other.items[703], copy.held = 703, copy, other.items[703] or 1, p else pair(p, other) end
    other.charge[s], other.battery[s] = p.charge[s], p.battery[s]
    local i = 1
    for k, q in ipairs(players) do if q == p then i = k end end
    if not copy then stored[id] = players[i] end
    stored[p] = copy and p or nil -- Esau Jr. characters, stored by themselves
    stored[other] = nil
    players[i] = other
  elseif id == 482 then
    -- shortcut: no item split to the new Esau and no 50% removal (both seen in game), model it from G's INNER lines.
    if p.t == 19 then merge(p, players[2]); players[2] = nil; p.t = 5
    elseif tlaz(p.t) then
      p:ChangePlayerType(tlazRoll) -- like ChangePlayerType: into 35 (11 of 11 in game), into 29 from 38 (run 8)
      if tlazRoll == 35 then players[#players+1] = newPlayer(40) end -- Tainted Forgotten's Soul: its own seed, no items
    else p.t = 19; players[2] = newPlayer(20) end
  end
end

-- A card's effect, used from the pocket or by UseCard: Soul of Jacob and Esau adds an Esau (type 20) with a Parent (run 2).
-- shortcut: every other card does nothing; Soul of the Forgotten's effect (plan open point 4) awaits the characters-recon session.
function PM:UseCard(c)
  if c == 97 then players[#players+1] = newPlayer(20, self) end
end

-- Simulate a scripted Clicker effect without touching the active slot or its charge.
function PM:UseActiveItem(id, flags)
  assert(id == 482 and flags == 0)
  if not fire(23, id, nil, self, flags, -1, 0) then
    if not ignoreClickerEffect then swapForm(self, id) end
    fire(3, id, nil, self, flags, -1, 0)
  end
end

-- The fake user's hand step (tests/test_harness.py answers a YOU: line with it): walks player 0 by Velocity onto the pedestal holding
-- `id`, stepping off first when it stands on one.
function fakeUserWalk(id)
  local p, e = players[1], Isaac.FindByType(5, 100, id)[1]
  p.Velocity = Vector(0, 0)
  if not e then return end
  for _, q in ipairs(pickups) do
    if p.Position:Distance(q.Position) < 20 then p.Velocity = Vector(0, 40) return end
  end
  p.Velocity = e.Position - p.Position
end
