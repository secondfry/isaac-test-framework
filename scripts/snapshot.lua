-- Snapshot tests: a fixture's setup and a settle wait, the trace, then numbered steps, each one's game state logged (SNAP) after it.
local settled = include("scripts.settle").settled
local exitAndContinue = include("scripts.manual").exitAndContinue

-- A strict test's step limit and test limit in updates, setup and settle waits included: twelve 445-update tests fit three minutes
-- (docs/tags.md What each line plays, tests/test_runner.py worst cases).
local STEP_LIMIT, TEST_LIMIT = 120, 445

-- A snapshot test's step: tags later TRACE lines with `label`, unique within its test; a manual step keeps its prompt. A strict step
-- has a limit, `limit` or STEP_LIMIT.
local function step(label, s, strict, when, limit)
	local manualStep = type(s) == "table" and s
	return { label = label, run = manualStep and manualStep.run or s, manual = manualStep and manualStep.manual or nil, when = when,
		limit = strict and (limit or STEP_LIMIT) or nil }
end

local function always() return true end

-- A snapshot test's Exit & Continue step: any players after it are data, and it gives up after 600 updates of play.
local continued = { "exit and Continue", exitAndContinue(true), nil, 600 }

-- A snapshot test: `fixture`, then numbered { label, step, when, limit } steps and a settle; a missed step is skipped, or with opts.strict ends the test so later presses never run on the wrong setup.
local function test(name, tags, fixture, steps, opts)
	local strict = opts and opts.strict
	local setup, all = {}, {}
	for i, s in ipairs(fixture.setup) do setup[i] = strict and step("setup " .. i, s, true) or s end
	setup[#setup + 1] = strict and step("setup settle", settled, true) or settled
	local list = { table.unpack(steps) } -- a copy: the caller's table may be shared
	list[#list + 1] = { "settle", settled }
	for _, s in ipairs(list) do
		for _, pair in ipairs(type(s[1]) == "string" and { s } or s) do
			all[#all + 1] = step((#all + 1) .. " " .. pair[1], pair[2], strict, pair[3], pair[4])
		end
	end
	return { name = name, tags = tags, fixture = { name = fixture.name, setup = setup, done = fixture.done or always }, steps = all,
		snapshot = true, traceUpdates = true, onStepError = strict and "end" or "skip", limit = strict and (opts.limit or TEST_LIMIT) or nil }
end

-- One strict recon test per character, "<character>: <name>", tagged vanilla too as it reads no ReHUD; `continues`: 1000 updates, 600 of them the user's Exit & Continue.
local function perCharacter(tests, spec, name, characters, fixture, steps, continues)
	local tags = { "recon", "vanilla", spec, continues and "exit-continue" or nil }
	for _, c in ipairs(characters) do
		tests[#tests + 1] = test(c.name .. ": " .. name, tags, fixture(c), steps(c), { strict = true, limit = continues and 1000 or nil })
	end
end

return { test = test, perCharacter = perCharacter, continued = continued }
