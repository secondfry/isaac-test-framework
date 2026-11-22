-- Snapshot tests: a fixture's setup and a settle wait, the trace, then numbered steps, each one's game state logged (SNAP) after it.
local settled = include("scripts.settle").settled

-- A strict test's step limit and test limit in updates, setup and settle waits included: twelve 445-update tests fit three minutes
-- (README budgets, tests/test_runner.py worst cases).
local STEP_LIMIT, TEST_LIMIT = 120, 445

-- A snapshot test's step: tags later TRACE lines with `label`, unique within its test; a manual step keeps its prompt. A strict step
-- has a limit, `limit` or STEP_LIMIT.
local function step(label, s, strict, when, limit)
	local manualStep = type(s) == "table" and s
	return { label = label, run = manualStep and manualStep.run or s, manual = manualStep and manualStep.manual or nil, when = when,
		limit = strict and (limit or STEP_LIMIT) or nil }
end

local function always() return true end

-- A snapshot test from `fixture` ({ name, setup, done }, setup a flat step list, done optional), then `steps` as { label, step, when,
-- limit } pairs (or lists of them), numbered, then a last settle wait. A missed step is logged and skipped; `opts.strict`: it ends the
-- test, so later presses cannot run on the wrong setup, and the test stops at `opts.limit` or TEST_LIMIT updates.
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

-- Appends to `tests` one strict recon test per character of `characters` (fixtures.RECON_CHARACTERS), "<character>: <name>", from
-- `fixture(c)` with `steps(c)`, tagged recon, vanilla (they read no ReHUD) and `spec`; `continues`: it asks for an Exit & Continue
-- (1000 updates, 600 of them for the user's).
local function perCharacter(tests, spec, name, characters, fixture, steps, continues)
	local tags = { "recon", "vanilla", spec, continues and "exit-continue" or nil }
	for _, c in ipairs(characters) do
		tests[#tests + 1] = test(c.name .. ": " .. name, tags, fixture(c), steps(c), { strict = true, limit = continues and 1000 or nil })
	end
end

return { test = test, perCharacter = perCharacter }
