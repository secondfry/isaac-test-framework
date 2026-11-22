-- Plays the scenarios one step per update, picked by the mode in the mod data, and logs each one's RESULT.
local P = include("scripts.log").P

-- Lua state survives `restart` and exit/continue, so the state lives in a global; a reload of this file keeps it.
-- shortcut: one pass per launch, and a native crash restarts the suite from the first scenario; add a rerun trigger, or SaveData resume, when either gets in the way.
HARNESS = HARNESS or { started = false, running = false, gen = 0, si = 1, pi = 1, fired = 0, pressed = 0, ctx = { floors = {}, fails = {}, notes = {} }, status = "waiting for a run" }

-- main.lua's wiring, rebuilt on every load: the scenarios in play order, and what each finished scenario resets.
local SCENARIOS, teardowns = {}, {}
local function add(list)
	for _, s in ipairs(list) do SCENARIOS[#SCENARIOS + 1] = s end
end
local function onTeardown(f) teardowns[#teardowns + 1] = f end

local function strictObs(name) return name:sub(1, 5) == "obsx " or name:sub(1, 5) == "obsy " end

-- The RESULT verdict: the error or failed checks, else PASS with the check count (INFO without checks); notes either way.
local function verdictOf(ctx, err)
	local v
	if err then v = "FAIL " .. err
	elseif #ctx.fails > 0 then v = "FAIL " .. table.concat(ctx.fails, "; ")
	else v = ctx.checks and ("PASS " .. ctx.checks .. " checks") or "INFO data only" end
	return v .. (#ctx.notes > 0 and ("; unobserved: " .. table.concat(ctx.notes, ", ")) or "") .. (ctx.lateContinue and "; late Continue mid-scenario" or "")
end

local function finish(err)
	local H = HARNESS
	P("RESULT", SCENARIOS[H.si].name, verdictOf(H.ctx, err))
	for _, f in ipairs(teardowns) do f(H) end -- a timed-out press must not reach the next scenario
	H.lateContinue = H.expectStart == "continue" or nil -- the user may still Continue after the step gave up, during the next scenario
	H.si, H.pi, H.expectStart = H.si + 1, 1, nil
	H.ctx = { floors = {}, fails = {}, notes = {} }
end

-- `only a,b`: a scenario whose name starts with any of the comma-separated prefixes.
local function picked(only, name)
	for prefix in only:gmatch("[^,]+") do
		if name:sub(1, #prefix) == prefix then return true end
	end
end

-- Why this mode skips `sc`, or nil.
local function skipReason(H, sc)
	if H.only then return not picked(H.only, sc.name) and ("not " .. H.only) or nil end
	if sc.onlyPicked then return "run only when picked by only" end
	if sc.kind == "large" and not sc.new and H.mode ~= "regression" then return "large and not new" end
end

-- Counts the scenario's updates against its ceiling, true once it is over: a checked scenario (budget) FAILs, an obs one (obsBudget)
-- ends INFO.
local function overBudget(H, sc)
	local cap = sc.obsBudget or sc.budget
	if not cap then return end
	H.ctx.updates = (H.ctx.updates or 0) + 1
	if H.ctx.updates < cap then return end
	H.pending = nil
	if sc.budget then finish("scenario ceiling " .. cap .. " updates") return true end
	P("INFO", sc.name, "scenario ceiling", cap, "updates")
	finish()
	return true
end

-- One update of play; `...` run first on every update while the suite runs.
local function tick(...)
	local H = HARNESS
	if not H.running then return end
	for _, f in ipairs({ ... }) do f() end
	local sc = SCENARIOS[H.si]
	if not sc then
		H.running, H.status = false, "DONE: exit to the menu, then tell Claude" -- exiting flushes log.txt (run 1)
		P("HARNESS DONE")
		return
	end
	local skip = H.pi == 1 and skipReason(H, sc)
	if skip then
		P("RESULT", sc.name, "SKIP " .. skip .. " (" .. H.mode .. " mode)")
		H.si = H.si + 1
		return
	end
	if sc.obsBudget and H.ctx.obsInterrupted then return finish() end
	if overBudget(H, sc) then return end
	if H.pending then return end
	local step = sc.steps[H.pi]
	if not step then return finish() end
	if not H.ctx.name then P("SCENARIO START", sc.name) end -- tools/run_report.py pairs it with a RESULT
	H.ctx.name, H.ctx.leftOk = sc.name, sc.leftOk
	local label = H.ctx.label
	H.ask = label and (label:find("Continue") or label:find("^YOU:")) and label or nil -- the user's own step gets its own line, so it is not lost at the end of a long status
	H.status = sc.name .. " step " .. H.pi .. "/" .. #sc.steps .. ((label and not H.ask) and (": " .. label) or "")
	local ok, res = pcall(step, H.ctx)
	if not ok then return finish("error in step " .. H.pi .. ": " .. tostring(res)) end
	if res ~= "again" then H.pi = H.pi + 1 end
end

-- An MC_POST_UPDATE handler running `f`: an error ends the scenario it hit, not the suite.
local function guard(f)
	return function()
		local ok, err = pcall(f)
		if not ok then
			P("HARNESS ERROR", err)
			if HARNESS.si <= #SCENARIOS then pcall(finish, "harness error: " .. tostring(err)) end
		end
	end
end

local function render()
	local H = HARNESS
	Isaac.RenderText("HARNESS: " .. H.status, 60, 30, 1, 1, 0, 1)
	if H.ask and H.running then Isaac.RenderText(H.ask, 60, 44, 1, 1, 0, 1) end
end

local function onGameStart(isContinued)
	local H = HARNESS
	H.gen, H.continued = H.gen + 1, isContinued
	P("GAME START", H.gen, "continued", isContinued)
	if not H.started then
		if isContinued then P("HARNESS idle: start a new run to test") return end
		-- The mode file is data\rehud_test_harness\save<slot>.dat in the game folder (metadata.xml <directory>), written before launch:
		-- "regression" runs every scenario; "only <prefix>" just the scenarios whose name starts with it, whatever their kind; anything else, or none, runs the small ones and the new large ones.
		local raw = H.mod:LoadData()
		H.modLine = raw:match("^[^\r\n]*") -- the first line only: a STUCK line left below it never changes the mode
		local text = H.modLine:match("^%s*(.-)%s*$")
		H.only = text:match("^only (.+)$")
		H.started, H.running, H.mode = true, true, text == "regression" and "regression" or H.only and ("only " .. H.only) or "default"
		P("HARNESS START", #SCENARIOS, "scenarios,", H.mode, "mode, mod data of '" .. H.mod.Name .. "' read", string.format("%q", raw))
		return
	end
	if H.running and not H.expectStart then
		if not (isContinued and H.lateContinue) then return finish("unexpected game start (hold-R, new run or continue)") end
		P("INFO", H.ctx.name or SCENARIOS[H.si].name, "late Continue, ignored")
		H.lateContinue, H.ctx.lateContinue = nil, true
	end
	H.expectStart = nil
end

return {
	add = add, onTeardown = onTeardown, strictObs = strictObs, tick = tick, guard = guard, render = render, onGameStart = onGameStart,
}
