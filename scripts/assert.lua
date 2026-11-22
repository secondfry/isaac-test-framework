-- Assertions: each counts in ctx.assertions and logs an ASSERT FAIL line when it fails; and preconditions, which are none.
local P = include("scripts.log").P
local since = include("scripts.callbacks").since
local engine = include("scripts.game")
local ofType, characterCount = engine.ofType, engine.characterCount
local rehud = include("scripts.rehud")
local entries, keyOf, countEntries, leftEntries, rehudCount = rehud.entries, rehud.keyOf, rehud.countEntries, rehud.leftEntries,
	rehud.characterCount
local ids = include("scripts.ids")
local T_LAZ, DEAD_T_LAZ = ids.T_LAZ, ids.DEAD_T_LAZ

local function fail(ctx, why)
	table.insert(ctx.fails, why)
	P("ASSERT FAIL", ctx.name, why)
end

-- What a step needs before it acts (a type, a held slot, a room, a player): not so, the test FAILs "precondition: <why>", and a soft
-- step of a recon test never happens.
local function pre(ok, why)
	if not ok then error("precondition: " .. why, 0) end
end

-- Exactly `n` ReHUD entries of item `id`, each on `floor` and owned by `owner` when given.
local function expectN(ctx, label, id, n, floor, owner)
	ctx.assertions = (ctx.assertions or 0) + 1
	local found = {}
	for _, e in ipairs(entries()) do
		if e.id == id then table.insert(found, e) end
	end
	if #found ~= n then return fail(ctx, label .. ": c" .. id .. " has " .. #found .. " entries, want " .. n) end
	for _, e in ipairs(found) do
		if floor and e.floor ~= floor then fail(ctx, label .. ": c" .. id .. " on '" .. tostring(e.floor) .. "', want '" .. floor .. "'") end
		if owner and e.owner ~= owner then fail(ctx, label .. ": c" .. id .. " owner " .. tostring(e.owner) .. ", want " .. owner) end
	end
end
local function expectOne(ctx, label, id, floor, owner) expectN(ctx, label, id, 1, floor, owner) end

-- A read with an expected answer: logged as INFO, and an assertion.
local function expect(ctx, label, got, want)
	ctx.assertions = (ctx.assertions or 0) + 1
	P("INFO", ctx.name, label, got)
	if got ~= want then fail(ctx, label .. ": " .. tostring(got) .. ", want " .. tostring(want)) end
end

-- `want` ReHUD entries of item `id` matching every given field (nil: any); `temporary` true is a copy with a clock.
local function expectCount(ctx, label, want, id, floor, temporary, owner)
	local kind = temporary == nil and "" or (temporary and " clocked" or " unclocked")
	local n = countEntries(function(e)
		return e.id == id and (floor == nil or e.floor == floor) and (temporary == nil or e.temporary == temporary) and (owner == nil or e.owner == owner)
	end)
	expect(ctx, label .. ": c" .. id .. kind .. (floor and (" on " .. floor) or "") .. (owner and (" of " .. owner) or ""), n, want)
end

-- expectCount with player 0 as the owner.
local function own(ctx, label, want, id, floor, temporary) expectCount(ctx, label, want, id, floor, temporary, keyOf(Isaac.GetPlayer(0))) end

-- One assertion per invariant: it fails naming every problem found.
local function holds(ctx, label, what, problems)
	ctx.assertions = (ctx.assertions or 0) + 1
	if problems[1] then fail(ctx, label .. ": invariant " .. what .. ": " .. table.concat(problems, "; ")) end
end

local function c4c5(ctx, label)
	expectOne(ctx, label, 4, ctx.floors[1])
	expectOne(ctx, label, 5, ctx.floors[2])
end
local function oneC4(ctx, label) expectOne(ctx, label, 4, ctx.floors[1]) end
local function twoC4(ctx, label) expectN(ctx, label, 4, 2, ctx.floors[1], keyOf(Isaac.GetPlayer(0))) end

local function birthrightOwners(ctx, label)
	c4c5(ctx, label)
	expectOne(ctx, label, 4, nil, keyOf(ofType(T_LAZ)))
	expectOne(ctx, label, 5, nil, keyOf(ofType(DEAD_T_LAZ)))
end

-- Callback `id` fired `want` times with `arg` since the step's press began (ctx.mark); want 0: it never fired.
local function fired(ctx, label, id, arg, want)
	expect(ctx, label .. ": callback " .. id .. " with " .. tostring(arg) .. " fired", since(ctx.mark, id, arg), want)
end

-- No list marked left, and ReHUD counts every character in play (no stored one holds a list here).
local function noneLeft(ctx, label)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
	expect(ctx, label .. ": characterCount = playable players", rehudCount(), characterCount())
end

return {
	fail = fail, pre = pre, fired = fired, expectN = expectN, expectOne = expectOne, expect = expect, expectCount = expectCount, own = own, holds = holds,
	c4c5 = c4c5, oneC4 = oneC4, twoC4 = twoC4, birthrightOwners = birthrightOwners, noneLeft = noneLeft,
}
