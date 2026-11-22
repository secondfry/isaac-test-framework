-- Fake console: seed, restart, giveitem, remove and stage.
function Isaac.ExecuteCommand(c)
  -- shortcut: `seed <code>` restarts on that seed after 1 update keeping player 0's type, seen on Isaac only (session 1); whether it keeps another type is session 2's recon
  local code = c:match("^seed (.+)$")
  if code then startSeed, seeded, pendingStart = code, true, players[1].t return end
  local a, b = c:match("^(%S+) c?(%d+)$")
  b = tonumber(b)
  if a == "restart" then if not ignoreRestart then pendingStart = b == lockedType and 0 or b end
  elseif a == "giveitem" then
    local to = players[1]
    for _, p in ipairs(players) do if p.t == 14 and p.Parent then to = p end end -- to the Keeper once one exists (in-game 2026-11-22)
    to:AddCollectible(b)
  elseif a == "remove" then
    players[1].items[b] = math.max(0, (players[1].items[b] or 1) - 1)
    if b == 619 and players[2] then stored[711], players[2] = players[2], nil end
  elseif a == "stage" then
    stageN = b
    for _, p in ipairs(players) do if (p.items[392] or 0) > 0 then p.zodiac = 300 + b end end -- `stage` re-rolls the Zodiac item
  end
end
