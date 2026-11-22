-- Fake input: one game update's polls of the harness's forced presses, the uses they trigger, pedestal walks and 3 Dollar Bill grants.

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
  if id == 482 and ignoreFirstVetoPress and HARNESS.cancelClicker and HARNESS.cancelClicker.arms == 1 then return end
  local cancelled = fire(23, id, nil, p, 0, slot, 0)
  if not cancelled then fire(3, id, nil, p, 0, slot, 0) end
  if not noSpend then p.charge[slot] = 0 end
  if not cancelled then swaps[#swaps+1] = {p, id} end
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
  frame = frame + 1
  local from = {}
  for _, p in ipairs(players) do from[p] = p.Position; p.Position = p.Position + p.Velocity end
  for _, p in ipairs(players) do fire(31, p) end
  for _, s in ipairs(swaps) do swapForm(s[1], s[2]) end
  -- An active pedestal swaps with the held active when walked onto: by Velocity from off it, as a teleport never touched in game
  -- (lua-api-notes.md). shortcut: a pedestal reached, not a hitbox crossed; model collision if a scenario walks past a pedestal.
  for _, p in ipairs(players) do
    for _, e in ipairs(pickups) do
      if from[p] and p.Position:Distance(e.Position) < 20 and from[p]:Distance(e.Position) >= 20 and p.active then
        local held, got = p.active, e.SubType
        p.items[held] = nil
        p.active, p.items[got], e.SubType, p.copy, e.copy = got, 1, held, e.copy, p.copy
      end
    end
  end
  -- 3 Dollar Bill: one granted item, changing every 170 updates (in game)
  for _, p in ipairs(players) do
    if (p.items[191] or 0) > 0 then p.billT = (p.billT or -1) + 1; p.bill = 10 + math.floor(p.billT / 170) % 3 end
  end
end
