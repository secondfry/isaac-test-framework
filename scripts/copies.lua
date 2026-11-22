-- Copies with a clock: item wisps, the Zodiac copy and 3 Dollar Bill grants.
local P = include("scripts.log").P
local wait = include("scripts.wait")
local action, TIMEOUT = wait.action, wait.TIMEOUT
local engine = include("scripts.game")
local itemConfig, maxId, floorName, owned, wispsOf = engine.itemConfig, engine.maxId, engine.floorName, engine.owned, engine.wispsOf
local countOf = include("scripts.rehud").countOf
local expect = include("scripts.assert").expect

-- One item wisp more or fewer on player 0 (`act` adds or kills one), seen in its wisp count and in GetCollectibleNum(id, false) both.
-- The DONE line's update count answers how soon a killed wisp leaves the engine count (Q4).
local function changeWisps(label, id, delta, act)
	local function counts()
		local p = Isaac.GetPlayer(0)
		return wispsOf(p)[id] or 0, p:GetCollectibleNum(id, false)
	end
	return action(label .. " c" .. id, function()
		local w, n = counts()
		act(Isaac.GetPlayer(0))
		return { w = w, n = n }
	end, function(_, b)
		local w, n = counts()
		return w == b.w + delta and n == b.n + delta, "wisps " .. b.w .. " -> " .. w .. ", GetCollectibleNum(false) " .. b.n .. " -> " .. n
	end)
end
local function wisp(id) return changeWisps("AddItemWisp", id, 1, function(p) p:AddItemWisp(id, p.Position) end) end
local function killWisp(id)
	return changeWisps("Kill wisp", id, -1, function(p)
		local e = select(2, wispsOf(p))[id]
		if not e then error("no c" .. id .. " wisp of player 0 to kill") end
		e:Kill()
	end)
end

-- An engine fact the next checks rest on: its FAIL names the engine, not ReHUD.
local function engineWisps(label, id, want)
	return function(ctx) expect(ctx, "engine, not ReHUD: c" .. id .. " wisps of player 0 " .. label, wispsOf(Isaac.GetPlayer(0))[id] or 0, want) end
end

-- Polls player 0's Zodiac item; a new id sets ctx.zodiac and the floor it appeared on, the last one stays as ctx.zodiacOld.
-- With `ceiling`, nothing by then is the answer, logged (Q1: does giveitem c392 grant on its own floor), not a fail.
-- shortcut: takes the first nonzero read after `stage`, so a re-roll landing later is read as "rolled the same item"; poll longer if Q1/Q2 answers look odd.
local function zodiacOn(label, ceiling)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local z = Isaac.GetPlayer(0):GetZodiacEffect()
		if z == 0 and ctx.t < (ceiling or TIMEOUT) then return "again" end
		P("INFO", ctx.name, "Zodiac item " .. label, z, "after", ctx.t, "updates")
		ctx.t = nil
		if z == 0 then
			if ceiling then return end
			error("Zodiac granted nothing " .. label .. " (engine, not ReHUD)")
		end
		ctx.zodiacOld = ctx.zodiac
		if z ~= ctx.zodiac then ctx.zodiac, ctx.zodiacFloor = z, floorName() end
	end
end

-- 3 Dollar Bill's grant on player 0: an id held but not owned, not a wisp and not the Zodiac item, other than the last grant
-- (kept as ctx.grantOld). Logs every such id, so one-at-a-time shows, and the DONE line the interval (Q6).
-- shortcut: an owned id cannot be told from the owned copy, so a grant of one is missed (part of Q6 unanswered); compare counts with a pre-grant snapshot if that matters.
local grant3DB = action("3 Dollar Bill grant", function(ctx) ctx.grantOld = ctx.grant end, function(ctx)
	local p = Isaac.GetPlayer(0)
	local w, z, found = wispsOf(p), p:GetZodiacEffect(), {}
	for id = 1, maxId do
		if itemConfig:GetCollectible(id) and id ~= z and id ~= ctx.grantOld and not w[id] and owned(p, id) == 0 and p:GetCollectibleNum(id, false) > 0 then found[#found + 1] = id end
	end
	if not found[1] then return false, "no new grant" end
	ctx.grant = found[1]
	P("INFO", ctx.name, "3 Dollar Bill grants c" .. table.concat(found, " c"))
	return true
end, 600)
-- ReHUD finds a 3 Dollar Bill grant only on its periodic scan (tracker.lua SCAN_INTERVAL 30).
local listed = action("3 Dollar Bill grant listed", function() end, function(ctx)
	local n = countOf(ctx.grant, nil, true)
	return n == 1, "c" .. ctx.grant .. " has " .. n .. " clocked entries, want 1"
end, 60)

return { wisp = wisp, killWisp = killWisp, engineWisps = engineWisps, zodiacOn = zodiacOn, grant3DB = grant3DB, listed = listed }
