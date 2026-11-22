-- Waits for ReHUD to settle: a look (state, assertions, invariants), a bare settle wait and a timed watch.
local P = include("scripts.log").P
local TIMEOUT = include("scripts.wait").TIMEOUT
local stuck = include("scripts.runner").stuck
local rehud = include("scripts.rehud")
local settling, storedSettling = rehud.settling, rehud.storedSettling
local fail = include("scripts.assert").fail
local logState = include("scripts.record").logState
local track = include("scripts.characters").track
local invariants = include("scripts.invariants")

-- Once ReHUD has settled: the state, `verify(ctx, label)` if given, then the invariants (not while ReHUD still settles at the ceiling).
local function look(label, verify)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local busy = settling()
		if busy and ctx.t < TIMEOUT then stuck(ctx, ctx.t, label) return "again" end
		if busy then fail(ctx, label .. ": ReHUD still settling " .. busy .. " after " .. ctx.t .. " updates") end
		P("SETTLED", label, "after", ctx.t, "updates", "stored settling", storedSettling())
		ctx.t = nil
		logState(ctx, label)
		if verify then verify(ctx, label) end
		if not busy then invariants.check(ctx, label) end
	end
end

-- The settle wait of look, without its assertions, capped at 120 updates: a merged flag left on a stored survivor (a known ReHUD bug,
-- obs3 cross and flip) never clears, and obs only notes it.
local function settled(ctx)
	ctx.t = (ctx.t or 0) + 1
	local busy = settling()
	local trace = HARNESS.record.trace
	if busy and ctx.t < 120 then stuck(ctx, ctx.t, trace and trace.step or "settle") return "again" end
	P("INFO", ctx.name, "settle wait ended after", ctx.t, "updates", busy and ("still settling " .. busy) or "settled")
	ctx.t = nil
end

-- Watches `n` updates without acting and logs each change of what ReHUD still settles, so the log shows how long a returned survivor settles.
local function idle(n)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local busy = settling() or "nothing"
		if busy ~= ctx.busy then ctx.busy = busy; P("INFO", ctx.name, "idle update", ctx.t, "settling", busy) end
		if ctx.t < n then return "again" end
		ctx.t, ctx.busy = nil, nil
	end
end

-- A look that also asserts the character numbers.
local function lookC(label, verify)
	return look(label, function(ctx, l)
		track()
		invariants.characterNumbers(ctx, l)
		if verify then verify(ctx, l) end
	end)
end

return { look = look, settled = settled, idle = idle, lookC = lookC }
