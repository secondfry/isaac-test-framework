-- Plays the tests one step per update, picked by the mode in the mod data, and logs each one's RESULT.
local P = include("scripts.log").P

-- Lua state survives `restart` and exit/continue, so the state lives in a global; a reload of this file keeps it.
-- shortcut: one pass per launch, and a native crash restarts the suite from the first scenario; add a rerun trigger, or SaveData resume, when either gets in the way.
HARNESS = HARNESS or { started = false, running = false, gen = 0, testIndex = 1, stepIndex = 1, fired = 0, pressed = 0, ctx = { floors = {}, fails = {}, notes = {} }, status = "waiting for a run" }

-- main.lua's wiring, rebuilt on every load: the tests in play order, and what each finished test resets.
local tests, teardowns = {}, {}

-- A step list may nest step lists (a fixture's steps): flattened into a new list, the caller's tables untouched.
local function flatten(list, out)
	out = out or {}
	for _, s in ipairs(list) do
		if type(s) == "table" then flatten(s, out) else out[#out + 1] = s end
	end
	return out
end
local function add(list)
	for _, s in ipairs(list) do
		local test = {}
		for k, v in pairs(s) do test[k] = v end
		test.steps = flatten(s.steps)
		tests[#tests + 1] = test
	end
end
local function onTeardown(f) teardowns[#teardowns + 1] = f end

local function strictObs(name) return name:sub(1, 5) == "obsx " or name:sub(1, 5) == "obsy " end

-- The RESULT verdict: the error or failed assertions, else PASS with their count (INFO without any); notes either way.
local function verdictOf(ctx, err)
	local v
	if err then v = "FAIL " .. err
	elseif #ctx.fails > 0 then v = "FAIL " .. table.concat(ctx.fails, "; ")
	else v = ctx.assertions and ("PASS " .. ctx.assertions .. " checks") or "INFO data only" end
	return v .. (#ctx.notes > 0 and ("; unobserved: " .. table.concat(ctx.notes, ", ")) or "") .. (ctx.lateContinue and "; late Continue mid-scenario" or "")
end

local function finish(err)
	local H = HARNESS
	P("RESULT", tests[H.testIndex].name, verdictOf(H.ctx, err))
	for _, f in ipairs(teardowns) do f(H) end -- a timed-out press must not reach the next test
	H.lateContinue = H.expectStart == "continue" or nil -- the user may still Continue after the step gave up, during the next test
	H.testIndex, H.stepIndex, H.expectStart = H.testIndex + 1, 1, nil
	H.ctx = { floors = {}, fails = {}, notes = {} }
end

-- `only a,b`: a test whose name starts with any of the comma-separated prefixes.
local function picked(only, name)
	for prefix in only:gmatch("[^,]+") do
		if name:sub(1, #prefix) == prefix then return true end
	end
end

-- Why this mode skips `test`, or nil.
local function skipReason(H, test)
	if H.only then return not picked(H.only, test.name) and ("not " .. H.only) or nil end
	if test.onlyPicked then return "run only when picked by only" end
	if test.kind == "large" and not test.new and H.mode ~= "regression" then return "large and not new" end
end

-- Counts the test's updates against its ceiling, true once it is over: a test with assertions (budget) FAILs, an obs one (obsBudget)
-- ends INFO.
local function overBudget(H, test)
	local cap = test.obsBudget or test.budget
	if not cap then return end
	H.ctx.updates = (H.ctx.updates or 0) + 1
	if H.ctx.updates < cap then return end
	H.pending = nil
	if test.budget then finish("scenario ceiling " .. cap .. " updates") return true end
	P("INFO", test.name, "scenario ceiling", cap, "updates")
	finish()
	return true
end

-- One update of play; `...` run first on every update while the session runs.
local function tick(...)
	local H = HARNESS
	if not H.running then return end
	for _, f in ipairs({ ... }) do f() end
	local test = tests[H.testIndex]
	if not test then
		H.running, H.status = false, "DONE: exit to the menu, then tell Claude" -- exiting flushes log.txt (run 1)
		P("HARNESS DONE")
		return
	end
	local skip = H.stepIndex == 1 and skipReason(H, test)
	if skip then
		P("RESULT", test.name, "SKIP " .. skip .. " (" .. H.mode .. " mode)")
		H.testIndex = H.testIndex + 1
		return
	end
	if test.obsBudget and H.ctx.obsInterrupted then return finish() end
	if overBudget(H, test) then return end
	if H.pending then return end
	local step = test.steps[H.stepIndex]
	if not step then return finish() end
	if not H.ctx.name then P("SCENARIO START", test.name) end -- tools/run_report.py pairs it with a RESULT
	H.ctx.name, H.ctx.leftOk = test.name, test.leftOk
	local label = H.ctx.label
	H.ask = label and (label:find("Continue") or label:find("^YOU:")) and label or nil -- the user's own step gets its own line, so it is not lost at the end of a long status
	H.status = test.name .. " step " .. H.stepIndex .. "/" .. #test.steps .. ((label and not H.ask) and (": " .. label) or "")
	local ok, res = pcall(step, H.ctx)
	if not ok then return finish("error in step " .. H.stepIndex .. ": " .. tostring(res)) end
	if res ~= "again" then H.stepIndex = H.stepIndex + 1 end
end

-- An MC_POST_UPDATE handler running `f`: an error ends the test it hit, not the session.
local function guard(f)
	return function()
		local ok, err = pcall(f)
		if not ok then
			P("HARNESS ERROR", err)
			if HARNESS.testIndex <= #tests then pcall(finish, "harness error: " .. tostring(err)) end
		end
	end
end

local function render()
	local H = HARNESS
	Isaac.RenderText("HARNESS: " .. H.status, 60, 30, 1, 1, 0, 1)
	if H.ask and H.running then Isaac.RenderText(H.ask, 60, 44, 1, 1, 0, 1) end
end

-- The mode file is data\rehud_test_harness\save<slot>.dat in the game folder (metadata.xml <directory>), written before launch:
-- "regression" runs every test; "only <prefix>" just the tests whose name starts with it, whatever their kind; anything else, or none,
-- runs the small ones and the new large ones. Sets H.modLine, H.only and H.mode.
local function readMode(H, raw)
	H.modLine = raw:match("^[^\r\n]*") -- the first line only: a STUCK line left below it never changes the mode
	local text = H.modLine:match("^%s*(.-)%s*$")
	H.only = text:match("^only (.+)$")
	H.mode = text == "regression" and "regression" or H.only and ("only " .. H.only) or "default"
end

local function onGameStart(isContinued)
	local H = HARNESS
	H.gen, H.continued = H.gen + 1, isContinued
	P("GAME START", H.gen, "continued", isContinued)
	if not H.started then
		if isContinued then P("HARNESS idle: start a new run to test") return end
		local raw = H.mod:LoadData()
		readMode(H, raw)
		H.started, H.running = true, true
		P("HARNESS START", #tests, "scenarios,", H.mode, "mode, mod data of '" .. H.mod.Name .. "' read", string.format("%q", raw))
		return
	end
	if H.running and not H.expectStart then
		if not (isContinued and H.lateContinue) then return finish("unexpected game start (hold-R, new run or continue)") end
		P("INFO", H.ctx.name or tests[H.testIndex].name, "late Continue, ignored")
		H.lateContinue, H.ctx.lateContinue = nil, true
	end
	H.expectStart = nil
end

return {
	add = add, onTeardown = onTeardown, strictObs = strictObs, tick = tick, guard = guard, render = render, onGameStart = onGameStart,
}
