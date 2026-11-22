-- Steps that act once and then wait for their effect, with the update ceilings they wait under.
local P = include("scripts.log").P

-- shortcut: ceilings count updates only, so a paused game or menu stalls the run with no fail; add a wall-clock ceiling if that bites.
local TIMEOUT, CONTINUE_TIMEOUT = 600, 9000 -- ceilings in updates, not waits: 20 s; 5 min of play for the user's exit and Continue

-- A step is function(ctx) returning "again" to run itself next update, anything else to move on.

-- At 60 updates a wait is stuck: log it once and append a STUCK line under the mode line for tools\stuck-shots.ps1 to screenshot.
-- shortcut: each wait calls it; the runner takes it over with the runner contract (plan S3a).
local function stuckAt(ctx, t, label)
	if t ~= 60 or tostring(label):find("^YOU:") then return end -- the user's own step waits for the user
	local H = HARNESS
	H.stuck = (H.stuck or 0) + 1
	P("STUCK", ctx.name, label, t)
	Isaac.SaveModData(H.mod, (H.modLine or "") .. "\nSTUCK " .. H.stuck .. " " .. tostring(ctx.name) .. " | " .. tostring(label))
end

-- A step's wait state, cleared when it ends or is given up.
local function resetStep(ctx) ctx.t, ctx.held, ctx.before, ctx.label, ctx.why = nil, nil, nil, nil, nil end

-- `start(ctx)` runs once and its result is kept as `ctx.before`; then `done(ctx, ctx.before)` is polled every update until it returns
-- true, or the step errors naming `label` at the ceiling. One more update follows, so ReHUD's MC_POST_UPDATE has seen the effect
-- whatever the mod load order (not guaranteed, AGENTS.md).
local function act(label, start, done, ceiling)
	return function(ctx)
		if not ctx.t then
			ctx.t, ctx.label = 0, label
			P("ACTION", label, "by type", Isaac.GetPlayer(0):GetPlayerType())
			ctx.before = start(ctx)
			return "again"
		end
		ctx.t = ctx.t + 1
		if ctx.held then
			P("DONE", label, "after", ctx.t - 1, "updates")
			resetStep(ctx)
			return
		end
		local ok, why = done(ctx, ctx.before)
		if ok then ctx.held = true return "again" end
		ctx.why = why -- an obs step ceiling names it
		if (ceiling or TIMEOUT) <= TIMEOUT then stuckAt(ctx, ctx.t, label) end -- a longer ceiling waits for the user's Continue
		if ctx.t >=(ceiling or TIMEOUT) then error(label .. ": " .. (why or "no effect") .. " after " .. ctx.t .. " updates") end
		return "again"
	end
end

-- Waits up to 60 updates for `cond()`, doing nothing.
local function condition(label, cond)
	return act(label, function() end, function() return cond(), label .. " not yet" end, 60)
end

return { TIMEOUT = TIMEOUT, CONTINUE_TIMEOUT = CONTINUE_TIMEOUT, stuckAt = stuckAt, resetStep = resetStep, act = act, condition = condition }
