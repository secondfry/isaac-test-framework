-- Plays the tests one step per update, picked by the tags in the mod data, and logs each one's RESULT.
local P = include("scripts.log").P

-- Lua state survives `restart` and exit/continue, so the session lives in HARNESS.session, written only here; a reload keeps it.
-- shortcut: one pass per launch, and a native crash restarts the session from the first test; add a rerun trigger, or SaveData resume, when either gets in the way.
local function newCtx() return { floors = {}, fails = {}, notes = {} } end
HARNESS.session = HARNESS.session or { started = false, running = false, gen = 0, testIndex = 1, stepIndex = 1, ctx = newCtx(), status = "waiting for a run" }

local FIXTURE_LIMIT = 120 -- updates a fixture's done(ctx) may take

-- main.lua's wiring, rebuilt on every load: the tests in play order, and the handlers of each runner event.
local tests = {}
local handlers = { teardown = {}, busy = {}, stepBegins = {}, giveUp = {}, snap = {}, traceStarts = {} }
local function on(event, f) table.insert(assert(handlers[event], event), f) end
local function fire(event, ...) for _, f in ipairs(handlers[event]) do f(...) end end

-- The mod data's one writer: the tags line, the Exit & Continue marker, then the STUCK line, last as tools\stuck-shots.ps1 reads only the last line.
local function saveData()
	local S = HARNESS.session
	local t = { S.line }
	t[#t + 1] = S.waitLine
	t[#t + 1] = S.stuckLine
	Isaac.SaveModData(S.mod, table.concat(t, "\n"))
end
-- A step waits for the user's Exit & Continue: a new `WAIT exit-continue <n>` line, which tools\auto-continue.ps1 answers.
local function markWait()
	local S = HARNESS.session
	S.waits = (S.waits or 0) + 1
	S.waitLine = "WAIT exit-continue " .. S.waits
	saveData()
end
local function clearWait()
	local S = HARNESS.session
	if not S.waitLine then return end
	S.waitLine = nil
	saveData()
end

-- A step list may nest step lists (a fixture's steps); a table with `run` is one step. Flattened into a new list, the caller's tables untouched.
local function flatten(list, out)
	out = out or {}
	for _, s in ipairs(list) do
		if type(s) == "table" and not s.run then flatten(s, out) else out[#out + 1] = s end
	end
	return out
end

-- Polls done(ctx) up to FIXTURE_LIMIT (then a precondition FAIL); once done the next step runs this update, so a fixture costs no update, except a traceUpdates test, whose trace starts first.
local function fixtureReady(fixture, test)
	return function(ctx)
		ctx.t = (ctx.t or 0) + 1
		local ok, why = fixture.done(ctx)
		if ok then
			ctx.t = nil
			P("INFO", ctx.name, "start seed", Game():GetSeeds():GetStartSeedString())
			if not test.traceUpdates then return "now" end
			fire("traceStarts", test)
			return
		end
		if ctx.t >= FIXTURE_LIMIT then error("precondition: " .. tostring(why or fixture.name), 0) end
		return "again"
	end
end

local function tagged(test, tag)
	for _, t in ipairs(test.tags or {}) do
		if t == tag then return true end
	end
end

-- Each test of `spec` as its own copy, "<spec> > <test>", fixture first; Exit & Continue tests play last, in order, so the user's exits come back to back (plan D7).
local lastCount = 0
local function add(spec)
	for _, t in ipairs(spec.tests) do
		local test, f = {}, t.fixture
		for k, v in pairs(t) do test[k] = v end
		test.spec, test.name = spec.name, spec.name .. " > " .. t.name
		test.steps = flatten({ f and { f.setup or {}, fixtureReady(f, test) } or {}, t.steps })
		local last = tagged(test, "exit-continue")
		table.insert(tests, last and #tests + 1 or #tests - lastCount + 1, test)
		if last then lastCount = lastCount + 1 end
	end
end

-- Why the session's tags skip `test`, or nil. No tags: every test but the exit-continue ones not tagged new; `all`: every test; else
-- the tests with a named tag. An opt-in test runs only when one of its own tags other than opt-in is named.
local function skipReason(S, test)
	local optIn = tagged(test, "opt-in")
	if #S.tags == 0 then
		if optIn then return "opt-in" end
		if tagged(test, "exit-continue") and not tagged(test, "new") then return "exit-continue and not new" end
		return
	end
	for _, tag in ipairs(S.tags) do
		if (tag ~= "opt-in" and tagged(test, tag)) or (tag == "all" and not optIn) then return end
	end
	return optIn and "opt-in" or "not tagged"
end

-- The RESULT verdict: the error or failed assertions, else PASS with their count (RECORDED for a snapshot test without any); notes either way.
local function verdictOf(test, ctx, err)
	local v
	if err then v = "FAIL " .. err
	elseif #ctx.fails > 0 then v = "FAIL " .. table.concat(ctx.fails, "; ")
	elseif ctx.assertions or not test.snapshot then v = "PASS " .. (ctx.assertions or 0) .. " assertions"
	else v = "RECORDED" end
	return v .. (#ctx.notes > 0 and ("; unreached: " .. table.concat(ctx.notes, ", ")) or "") .. (ctx.lateContinue and "; late Continue mid-test" or "")
end

-- Ends the current test: its RESULT, then its teardown exactly once, the fixture's first, each one on its own.
local function finish(err)
	local S = HARNESS.session
	local test = tests[S.testIndex]
	P("RESULT", test.name, verdictOf(test, S.ctx, err))
	local function down(f)
		local ok, e = pcall(f, S.ctx)
		if not ok then P("TEARDOWN FAIL", test.name, e) end
	end
	if test.fixture and test.fixture.teardown then down(test.fixture.teardown) end
	for _, f in ipairs(handlers.teardown) do down(f) end -- a timed-out press must not reach the next test
	S.lateContinue = S.expectStart == "continue" or nil -- the user may still Continue after the step gave up, during the next test
	clearWait()
	S.testIndex, S.stepIndex, S.expectStart, S.manual = S.testIndex + 1, 1, nil, nil
	S.ctx = newCtx()
end

-- Step `i` of `test` as a RESULT note names it: its label; an unlabelled one is a fixture's setup or done check.
local function stepName(test, i)
	if i > #test.steps then return "after the last step" end
	local s = test.steps[i]
	return type(s) == "table" and s.label or "fixture check"
end

-- Counts the test's updates against its limit, true once it is over: a snapshot test ends as recorded, any other FAILs.
local function overLimit(S, test)
	if not test.limit then return end
	S.ctx.updates = (S.ctx.updates or 0) + 1
	if S.ctx.updates < test.limit then return end
	if not test.snapshot then finish("test limit " .. test.limit .. " updates") return true end
	P("INFO", test.name, "test limit", test.limit, "updates")
	table.insert(S.ctx.notes, "test limit " .. test.limit .. " updates in " .. stepName(test, S.stepIndex))
	finish()
	return true
end

-- A step error no onStepError policy softens: the test FAILs with `why` (a run off the fixed seed makes every later value meaningless).
local ABORT = "abort: "
local function abort(why) error(ABORT .. why, 0) end
local function aborted(res) return tostring(res):sub(1, #ABORT) == ABORT end

-- One step's update: (ok, result) as pcall gives them. A table step of a test with an onStepError policy is soft: when its error, or
-- its limit passed, comes, it logs "never happened" and the test moves on ("skip") or ends ("end").
local function runStep(test, step, ctx)
	if type(step) ~= "table" then return pcall(step, ctx) end
	if not test.onStepError then return pcall(step.run, ctx) end
	if not ctx.t and step.when and not step.when(ctx) then return true end
	fire("stepBegins", step.label)
	local ok, res = pcall(step.run, ctx)
	if ok and res == "again" and step.limit and not ctx.held and ctx.t and ctx.t >= step.limit then
		ok, res = false, "step limit " .. step.limit .. " updates" .. (ctx.why and (": " .. ctx.why) or "")
	end
	if ok then
		if res ~= "again" and test.snapshot then fire("snap", ctx, step.label, true) end
		return true, res
	end
	if aborted(res) then return false, res end
	P("INFO", ctx.name, step.label, "never happened:", res)
	table.insert(ctx.notes, step.label .. " never happened")
	ctx.interrupted = test.onStepError == "end"
	clearWait()
	fire("giveUp", ctx)
	if test.snapshot then fire("snap", ctx, step.label, false) end
	return true
end

-- Plays the test's current step for this update: its result, "now" when the next step runs in this update too.
local function playStep(S, test, ctx)
	local step = test.steps[S.stepIndex]
	if not step then return finish() end
	if not ctx.started then -- tools/report.py pairs it with a RESULT
		ctx.started = true
		P("TEST START", test.name, "| tags " .. table.concat(test.tags or {}, ","))
	end
	ctx.leftOk, ctx.onStepError = test.leftOk, test.onStepError
	-- Only a started manual step prompts; its label gets its own line, so it is not lost at the end of a long status.
	S.manual = type(step) == "table" and ctx.label and step.manual or nil
	S.status = test.name .. " step " .. S.stepIndex .. "/" .. #test.steps .. ((ctx.label and not S.manual) and (": " .. ctx.label) or "")
	local ok, res = runStep(test, step, ctx)
	if not ok then
		if tostring(res):find("^precondition: ") then return finish(res) end
		if aborted(res) then return finish(res:sub(#ABORT + 1)) end
		return finish("error in step " .. S.stepIndex .. ": " .. tostring(res))
	end
	if res ~= "again" then S.stepIndex = S.stepIndex + 1 end
	return res
end

-- One update of play; `...` run first on every update a test plays, under its name.
local function tick(...)
	local S = HARNESS.session
	if not S.running then return end
	-- Skipped tests take no update of their own, so a tag's worst case is its tests' limits alone.
	local test = tests[S.testIndex]
	local skip = test and S.stepIndex == 1 and skipReason(S, test)
	while skip do
		P("RESULT", test.name, "SKIP " .. skip .. " (tags '" .. S.line .. "')")
		S.testIndex = S.testIndex + 1
		test = tests[S.testIndex]
		skip = test and skipReason(S, test)
	end
	if not test then
		S.running, S.status = false, "DONE: exit to the menu, then tell Claude" -- exiting flushes log.txt (run 1)
		P("HARNESS DONE")
		return
	end
	local ctx = S.ctx
	ctx.name = test.name -- from the test's first update: the session's first run is first seen there
	for _, f in ipairs({ ... }) do f() end
	if test.onUpdate then test.onUpdate(ctx) end
	if test.onStepError == "end" and ctx.interrupted then
		local n = #test.steps
		if S.stepIndex < n then table.insert(ctx.notes, "steps " .. stepName(test, S.stepIndex) .. " to " .. stepName(test, n) .. " skipped")
		elseif S.stepIndex == n then table.insert(ctx.notes, "step " .. stepName(test, n) .. " skipped") end
		return finish()
	end
	if overLimit(S, test) then return end
	for _, busy in ipairs(handlers.busy) do
		if busy() then return end
	end
	while playStep(S, test, ctx) == "now" do end
end

-- An MC_POST_UPDATE handler running `f`: an error ends the test it hit, not the session.
local function guard(f)
	return function()
		local ok, err = pcall(f)
		if not ok then
			P("HARNESS ERROR", err)
			if HARNESS.session.testIndex <= #tests then pcall(finish, "harness error: " .. tostring(err)) end
		end
	end
end

local function render()
	local S = HARNESS.session
	Isaac.RenderText("HARNESS: " .. S.status, 60, 30, 1, 1, 0, 1)
	if S.manual and S.running then Isaac.RenderText(tostring(S.ctx.label), 60, 44, 1, 1, 0, 1) end
end

-- The tags are line 1 of data\rehud_test_harness\save<slot>.dat in the game folder (metadata.xml <directory>), written before launch:
-- `tags a,b`, and `--update-snapshots` to let the reader replace snapshots. The harness's lines below it (WAIT, STUCK) never change them.
local function readTags(S, raw)
	S.line = raw:match("^[^\r\n]*"):match("^%s*(.-)%s*$")
	local text = S.line:gsub("%-%-update%-snapshots", ""):match("^%s*(.-)%s*$") -- the flag may come first
	S.updateSnapshots, S.tags = text ~= S.line, {}
	for tag in (text:match("^tags%s+(.*)$") or ""):gmatch("[^,%s]+") do S.tags[#S.tags + 1] = tag end
end

-- At 60 updates a wait is stuck: log it once and write the STUCK line, the mod data's last, for tools\stuck-shots.ps1 to screenshot. A manual
-- step waits for the user, so it is never stuck.
-- shortcut: each wait passes its own count, as nested waits (a look inside a Clicker loop) have their own labels; count in tick if none nests.
local function stuck(ctx, t, label)
	local S = HARNESS.session
	if t ~= 60 or S.manual then return end
	S.stuck = (S.stuck or 0) + 1
	P("STUCK", ctx.name, label, t)
	S.stuckLine = "STUCK " .. S.stuck .. " " .. tostring(ctx.name) .. " | " .. tostring(label)
	saveData()
end

local function setMod(mod) HARNESS.session.mod = mod end
-- The next game start a step waits for: "new" (restart) or "continue" (the user's Exit & Continue).
local function expectStart(kind) HARNESS.session.expectStart = kind end

local function onGameStart(isContinued)
	local S = HARNESS.session
	S.gen, S.continued = S.gen + 1, isContinued
	P("GAME START", S.gen, "continued", isContinued)
	if isContinued then clearWait() end
	if not S.started then
		if isContinued then P("HARNESS idle: start a new run to test") return end
		local raw = S.mod:LoadData()
		readTags(S, raw)
		saveData() -- drops the last session's WAIT and STUCK lines, so no tool acts on a stale one
		S.started, S.running = true, true
		P("HARNESS START", #tests, "tests, tags '" .. S.line .. "', update snapshots", S.updateSnapshots and "yes," or "no,",
			"mod data '" .. raw:gsub("\r", "\\r"):gsub("\n", "\\n") .. "'")
		return
	end
	if S.running and not S.expectStart then
		if not (isContinued and S.lateContinue) then return finish("unexpected game start (hold-R, new run or continue)") end
		P("INFO", S.ctx.name or tests[S.testIndex].name, "late Continue, ignored")
		S.lateContinue, S.ctx.lateContinue = nil, true
	end
	S.expectStart = nil
end

-- tests: the play list, which tests/dry.py reads (names, tags, limits) so no Python file lists the specs' tests again.
return {
	add = add, on = on, tick = tick, guard = guard, render = render, onGameStart = onGameStart, stuck = stuck, setMod = setMod,
	expectStart = expectStart, abort = abort, markWait = markWait, tests = tests,
}
