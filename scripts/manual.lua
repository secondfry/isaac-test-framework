-- Manual steps: what the user does by hand (Exit & Continue, walking onto a pedestal), each waiting for its effect. Each is a step
-- table whose `manual` the runner shows the user once the step has started, and the dry test's fake user reads.
local P = include("scripts.log").P
local wait = include("scripts.wait")
local act, CONTINUE_TIMEOUT = wait.act, wait.CONTINUE_TIMEOUT
local runner = include("scripts.runner")
local expectStart, markWait = runner.expectStart, runner.markWait
local engine = include("scripts.game")
local seeds, owned, pedestals, slots = engine.seeds, engine.owned, engine.pedestals, engine.slots
local ids = include("scripts.ids")
local ESAU_JR, YUM_HEART, PRIMARY, PEDESTAL = ids.ESAU_JR, ids.YUM_HEART, ids.PRIMARY, ids.PEDESTAL

-- The user exits to the menu and continues: a continued game with the same players (seeds) as before the exit; `soft` takes any
-- players and logs them (obsy: what a continue does to a stored form is the question).
local function exitAndContinue(soft)
	return { manual = { kind = "continue" }, run = act("exit to the menu and Continue now", function()
		expectStart("continue")
		markWait()
		return { gen = HARNESS.session.gen, seeds = seeds() }
	end, function(ctx, b)
		local S = HARNESS.session
		if S.gen == b.gen then
			if ctx.t % 300 == 0 then P("ACTION exit to the menu and Continue now") end
			return false, "no Continue"
		end
		if not S.continued then error("a new run started, not a Continue") end
		if soft then P("INFO", ctx.name, "after Continue: player seeds", seeds(), "before the exit", b.seeds) return true end
		return seeds() == b.seeds, "players " .. seeds() .. ", want " .. b.seeds
	end, CONTINUE_TIMEOUT) }
end

-- The user walks onto the pedestal of item `target` by hand, as a teleport never touched in game (docs/engine-facts.md) and a
-- scripted walk is not wanted; `start` once, then up to 450 updates for `done(p)`.
local function walk(label, target, start, done)
	return { manual = { kind = "walk", target = target }, run = act(label, start, function(ctx)
		local p = Isaac.GetPlayer(0)
		if not done(p) then return false, "c703 owned " .. owned(p, ESAU_JR) .. ", c703 pedestals " .. pedestals(ESAU_JR) end
		P("INFO", ctx.name, label, "after", ctx.t, "updates |", slots(p), "c703 pedestals", pedestals(ESAU_JR), "c45 pedestals", pedestals(YUM_HEART))
		return true
	end, 450) }
end
local dropByHand = walk("YOU: walk onto the yum-heart pedestal", YUM_HEART, function()
	local p = Isaac.GetPlayer(0)
	if p:GetActiveItem(PRIMARY) ~= ESAU_JR then error("Esau Jr. not in the primary slot") end
	Isaac.Spawn(EntityType.ENTITY_PICKUP, PEDESTAL, YUM_HEART, p.Position + Vector(80, 0), Vector(0, 0), nil)
end, function(p) return owned(p, ESAU_JR) == 0 and pedestals(ESAU_JR) > 0 end)
local pickByHand = walk("YOU: step off, then walk back onto the Esau Jr. pedestal", ESAU_JR, function() end, function(p) return owned(p, ESAU_JR) > 0 end)

return { exitAndContinue = exitAndContinue, dropByHand = dropByHand, pickByHand = pickByHand }
