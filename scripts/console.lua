-- Console commands: queued as steps, run from MC_POST_RENDER by flush.
local P = include("scripts.log").P
local action = include("scripts.wait").action
local engine = include("scripts.game")
local floorName, owned = engine.floorName, engine.owned

local game = Game()

-- giveitem/remove by console on player 0: one copy more or less, and `players` players when given (Birthright on Tainted Lazarus: 2, removed: 1).
local function changeOwned(verb, id, delta, players)
	return action(verb .. " c" .. id, function()
		HARNESS.pending = verb .. " c" .. id
		return owned(Isaac.GetPlayer(0), id)
	end, function(_, n)
		if owned(Isaac.GetPlayer(0), id) ~= n + delta then return false, "owned copies did not change by " .. delta end
		if players and game:GetNumPlayers() ~= players then return false, game:GetNumPlayers() .. " players, want " .. players end
		return true
	end)
end
local function give(id, players) return changeOwned("giveitem", id, 1, players) end
local function remove(id, players) return changeOwned("remove", id, -1, players) end

-- Records the new floor as ctx.floors[n]; an unchanged name would make every floor check meaningless.
local function stage(n)
	return action("stage " .. n, function()
		HARNESS.pending = "stage " .. n
		return floorName()
	end, function(ctx, old)
		if game:GetLevel():GetStage() ~= n then return false, "stage is " .. game:GetLevel():GetStage() end
		if floorName() == old then return false, "floor name unchanged: floor checks inconclusive" end
		ctx.floors[n] = floorName()
		P("FLOOR", n, ctx.floors[n])
		return true
	end)
end

-- A new (not continued) game with player 0 of type `t`; records floor 1.
local function restart(t)
	return action("restart " .. t, function()
		local H = HARNESS
		H.pending, H.expectStart = "restart " .. t, true
		return H.gen
	end, function(ctx, gen)
		local H = HARNESS
		if H.gen == gen or game:GetNumPlayers() == 0 then return false, "no new game" end
		if H.continued then error("restart " .. t .. " continued a run") end
		local got = Isaac.GetPlayer(0):GetPlayerType()
		if got ~= t then return false, "player 0 is type " .. got .. " (character locked?)" end
		ctx.floors[1] = floorName()
		P("FLOOR", 1, ctx.floors[1])
		return true
	end)
end

-- Console giveitem to whoever the engine gives it (the Keeper once a Strawman Keeper existed, in-game 2026-11-22); logs who got it.
local function giveAnyone(id)
	local function counts()
		local t = {}
		for i = 0, game:GetNumPlayers() - 1 do t[i] = owned(Isaac.GetPlayer(i), id) end
		return t
	end
	return action("giveitem c" .. id .. " (anyone)", function()
		HARNESS.pending = "giveitem c" .. id
		return counts()
	end, function(ctx, b)
		for i, n in pairs(counts()) do
			if n > (b[i] or 0) then
				P("INFO", ctx.name, "giveitem c" .. id .. " went to index", i, "type", Isaac.GetPlayer(i):GetPlayerType())
				return true
			end
		end
		return false, "no player's owned c" .. id .. " rose"
	end)
end

-- Console commands are queued for MC_POST_RENDER, not run in the middle of other mods' MC_POST_UPDATE.
local function flush()
	local H = HARNESS
	if H.pending then
		local c = H.pending
		H.pending = nil
		P("CMD", c)
		Isaac.ExecuteCommand(c)
	end
end

return { give = give, remove = remove, stage = stage, restart = restart, giveAnyone = giveAnyone, flush = flush }
