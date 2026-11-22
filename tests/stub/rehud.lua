-- Fake ReHUD: one entry per copy and kind held by a character (not the Tainted Soul) or stored form, listed under the floor it
-- first appeared on; a vanished owner's entries go to player 0 (a merge), a summoned Esau's go, and its number is forgotten. Numbers are
-- first seen; a new key settles for 20 updates, frozen while stored (roster.lua). Keys as roster.lua playerKey: a GetData tag, the seed
-- for a seed's first character, seed + n * 2^32 for later ones.
local entries, settle, numbers, nextNumber, tagged, summoned = {}, {}, {}, 0, {}, {}
local tracker = {entries=entries, characterCount=0}
local function keyOf(p)
  if untagged then return p.seed end
  if p.data.ReHUD_key then return p.data.ReHUD_key.key end
  local key = p.seed
  while tagged[key] do key = key + (1 << 32) end
  tagged[key], p.data.ReHUD_key = true, {key=key}
  return key
end
local function isStored(key) for _, p in pairs(stored) do if keyOf(p) == key then return true end end return false end
-- An Esau Jr. character (stored under itself): roster.lua's esauJr link, which keeps it listed until the run ends.
local function esauJrOf(key) for k, p in pairs(stored) do if type(k) == "table" and keyOf(p) == key then return true end end end
ReHUD = {dbg={tracker=tracker, roster={isSettling=function(key) return (settle[key] or 0) > 0 end, isSwapped=isStored, number=function(key) return numbers[key] end,
  group=function(key) return numbers[key] and 0 end, -- one human: every character shares ControllerIndex 0
  serialize=function()
    local rows = {}
    for key in pairs(numbers) do rows[#rows+1] = {key=key, swapped=isStored(key), esauJr=esauJrOf(key)} end
    if phantomRow then rows[#rows+1] = {key=-1, number=99, swapped=true, esauJr=true} end
    return rows
  end}}}
function fakeTrack()
  local all, held = {}, {}
  for _, p in ipairs(players) do
    if p.t ~= 40 then
      local key = keyOf(p)
      all[#all+1] = p
      p.unseen = nil
      if p.Parent and p.t == 20 then summoned[key] = true end
      if settle[key] == nil then settle[key] = 20 elseif settle[key] > 0 then settle[key] = settle[key] - 1 end
    end
  end
  for _, p in pairs(stored) do if not p.unseen then all[#all+1] = p end end
  for _, p in ipairs(all) do
    local key = keyOf(p)
    if not numbers[key] then numbers[key], nextNumber = nextNumber, nextNumber + 1 end
    local k = kinds(p)
    if dupCopy and k[4] then k[4] = {k[4][1] * 2, k[4][2] * 2} elseif missCopy then k[4] = nil end
    held[key] = k
  end
  for key in pairs(numbers) do if not held[key] and not leaveNotMerge then numbers[key] = nil end end
  local have = {}
  local function slot(owner, id, kind) return owner .. ":" .. id .. ":" .. kind end
  for i = #entries, 1, -1 do -- newest first, so the oldest of a kind goes
    local e = entries[i]
    if not held[e.owner] and leaveNotMerge then e.left = true end
    if not e.left and not held[e.owner] and summoned[e.owner] then table.remove(entries, i) goto nextEntry end
    if not e.left then
      if not held[e.owner] then e.owner = keyOf(players[1]) end
      local kind = e.temporary and 2 or 1
      local s = slot(e.owner, e.id, kind)
      have[s] = (have[s] or 0) + 1
      local c = held[e.owner][e.id]
      if have[s] > (c and c[kind] or 0) then table.remove(entries, i) else e.number = numbers[e.owner] end
    end
    ::nextEntry::
  end
  for _, p in ipairs(all) do
    local key = keyOf(p)
    for id, c in pairs(held[key]) do
      for kind = 1, 2 do
        for _ = (have[slot(key, id, kind)] or 0) + 1, c[kind] do
          entries[#entries+1] = {id=id, number=numbers[key], owner=key, floor=wrongFloor and "Wrong" or "Floor"..(laterFloor and stageN + 1 or stageN), temporary=kind == 2}
        end
      end
    end
  end
  tracker.characterCount = #all
end
addPriorityCallback(nil, ModCallbacks.MC_POST_UPDATE, 0, fakeTrack)

-- A new run: no entries, numbers or keys (startRun calls it).
function resetFakeReHUD()
  numbers, nextNumber, tagged, summoned = {}, 0, {}, {}; for i = #entries, 1, -1 do entries[i] = nil end
end
