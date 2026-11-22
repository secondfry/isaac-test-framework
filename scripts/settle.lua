-- Waits for ReHUD to settle: a look (dump, assertions, invariants), a bare settle wait and a timed watch.
local P = include("scripts.log").P
local wait = include("scripts.wait")
local stuckAt, TIMEOUT = wait.stuckAt, wait.TIMEOUT
local rehud = include("scripts.rehud")
local settling, storedSettling = rehud.settling, rehud.storedSettling
local fail = include("scripts.assert").fail
local probe = include("scripts.record").probe
local trackChars = include("scripts.characters").trackChars
local invariants = include("scripts.invariants")

-- Once ReHUD has settled: probe, run `check(ctx, label)` if given, then the invariants (not while ReHUD still settles at the ceiling).
local function look(label, check)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local busy = settling()
		if busy and ctx.t < TIMEOUT then stuckAt(ctx, ctx.t, label) return "again" end
		if busy then fail(ctx, label .. ": ReHUD still settling " .. busy .. " after " .. ctx.t .. " updates") end
		P("SETTLED", label, "after", ctx.t, "updates", "stored settling", storedSettling())
		ctx.t = nil
		probe(ctx, label)
		if check then check(ctx, label) end
		if not busy then invariants.invariants(ctx, label) end
	end
end

-- The settle wait of look, without its checks, capped at 120 updates: a merged flag left on a stored survivor (a known ReHUD bug,
-- obs3 cross and flip) never clears, and obs only notes it.
local function settled(ctx)
	ctx.t = (ctx.t or 0) + 1
	local busy = settling()
	if busy and ctx.t < 120 then stuckAt(ctx, ctx.t, HARNESS.obs and HARNESS.obs.step or "settle") return "again" end
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

local function lookC(label, check)
	return look(label, function(ctx, l)
		trackChars()
		invariants.charRows(ctx, l)
		if check then check(ctx, l) end
	end)
end

return { look = look, settled = settled, idle = idle, lookC = lookC }
