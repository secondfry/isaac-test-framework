-- Console commands: queued as steps in HARNESS.console, run from MC_POST_RENDER by flush.
local P = include("scripts.log").P
local act = include("scripts.wait").act
local runner = include("scripts.runner")
local expectStart, abort = runner.expectStart, runner.abort
local engine = include("scripts.game")
local floorName, owned = engine.floorName, engine.owned

local game = Game()
HARNESS.console = HARNESS.console or {}

local function queue(c) HARNESS.console.pending = c end
-- True while a queued command has not run: the runner waits for it.
local function busy() return HARNESS.console.pending ~= nil end
-- A finished test's command never runs in the next one.
local function reset() HARNESS.console.pending = nil end

-- giveitem/remove by console on player 0: one copy more or less, and `players` players when given (Birthright on Tainted Lazarus: 2, removed: 1).
local function changeOwned(verb, id, delta, players)
	return act(verb .. " c" .. id, function()
		queue(verb .. " c" .. id)
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
	return act("stage " .. n, function()
		queue("stage " .. n)
		return floorName()
	end, function(ctx, old)
		if game:GetLevel():GetStage() ~= n then return false, "stage is " .. game:GetLevel():GetStage() end
		if floorName() == old then return false, "floor name unchanged: floor checks inconclusive" end
		ctx.floors[n] = floorName()
		P("FLOOR", n, ctx.floors[n])
		return true
	end)
end

-- Every test's start seed: `seed` with it restarts onto it from any run, and restarts kept it for types 0, 16, 19, 21, 29, 35 and 37 and through 28 Exit & Continues (sessions 1-2).
local FIXED_SEED = "9SZM 3P3S"

-- Queues `command`, a new game; the generation the step waits to pass.
local function startNew(command)
	queue(command)
	expectStart("new")
	return HARNESS.session.gen
end

-- A new game by `restart t` on FIXED_SEED (a `seed` command first when off it), each start's seed logged; player 0 of type `t` when `typed`; records floor 1.
local function newGame(t, typed)
	return act("restart " .. t, function()
		local seeding = game:GetSeeds():GetStartSeedString() ~= FIXED_SEED
		return { seeding = seeding, gen = startNew(seeding and ("seed " .. FIXED_SEED) or ("restart " .. t)) }
	end, function(ctx, b)
		local S = HARNESS.session
		if S.gen == b.gen or game:GetNumPlayers() == 0 then return false, "no new game" end
		if S.continued then error("restart " .. t .. " continued a run") end
		local code, got = game:GetSeeds():GetStartSeedString(), Isaac.GetPlayer(0):GetPlayerType()
		if b.seeding then
			P("INFO", ctx.name, "seed command: start seed", code, "type", got, "after", ctx.t, "updates")
			b.seeding, b.gen = false, startNew("restart " .. t)
			return false, "on the fixed seed, no new game yet"
		end
		if not b.checked then -- the typed check below repeats every update
			b.checked = true
			P("INFO", ctx.name, "restart", t, "start seed", code, "type", got, "frame", game:GetFrameCount())
			if code ~= FIXED_SEED then abort("restart " .. t .. " left the fixed seed: start seed " .. code) end
		end
		if typed and got ~= t then return false, "player 0 is type " .. got .. " (character locked?)" end
		ctx.floors[1] = floorName()
		P("FLOOR", 1, ctx.floors[1])
		return true
	end)
end
local function fresh(t) return newGame(t, true) end
-- Any character: a fixture's done check then reports a locked one (fixtures.character).
local function restart(t) return newGame(t, false) end

-- Recon: the `seed` command with the run's own start seed, then up to 50 updates for a game start, logging whether one came (session 1: after 1 update).
local function seed()
	return act("seed command", function(ctx)
		local code = game:GetSeeds():GetStartSeedString()
		P("INFO", ctx.name, "seed command with the start seed", code)
		return startNew("seed " .. code)
	end, function(ctx, gen)
		local S = HARNESS.session
		if S.gen ~= gen and game:GetNumPlayers() > 0 then
			P("INFO", ctx.name, "seed command: game start after", ctx.t, "updates, continued", S.continued)
			return true
		end
		if ctx.t < 50 then return false, "no game start" end
		expectStart(nil)
		P("INFO", ctx.name, "seed command: no game start in", ctx.t, "updates")
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
	return act("giveitem c" .. id .. " (anyone)", function()
		queue("giveitem c" .. id)
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
	local c = HARNESS.console.pending
	if not c then return end
	reset()
	P("CMD", c)
	Isaac.ExecuteCommand(c)
end

return { give = give, remove = remove, stage = stage, fresh = fresh, restart = restart, seed = seed, giveAnyone = giveAnyone, flush = flush, busy = busy, reset = reset }
