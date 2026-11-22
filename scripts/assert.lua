-- Assertions: each counts in ctx.checks and logs a CHECK FAIL line when it fails.
local P = include("scripts.log").P
local engine = include("scripts.game")
local playerOfType, playable = engine.playerOfType, engine.playable
local rehud = include("scripts.rehud")
local dbg, entries, keyOf, countOf, leftEntries = rehud.dbg, rehud.entries, rehud.keyOf, rehud.countOf, rehud.leftEntries
local ids = include("scripts.ids")
local T_LAZ, DEAD_LAZ = ids.T_LAZ, ids.DEAD_LAZ

local function fail(ctx, why)
	table.insert(ctx.fails, why)
	P("CHECK FAIL", ctx.name, why)
end

-- Exactly `n` ReHUD entries of item `id`, each on `floor` and owned by `owner` when given.
local function expectN(ctx, label, id, n, floor, owner)
	ctx.checks = (ctx.checks or 0) + 1
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

-- A probe with an expected answer: logged as INFO, and a check.
local function expect(ctx, label, got, want)
	ctx.checks = (ctx.checks or 0) + 1
	P("INFO", ctx.name, label, got)
	if got ~= want then fail(ctx, label .. ": " .. tostring(got) .. ", want " .. tostring(want)) end
end

local function expectCount(ctx, label, want, id, floor, temporary, owner)
	local kind = temporary == nil and "" or (temporary and " clocked" or " unclocked")
	expect(ctx, label .. ": c" .. id .. kind .. (floor and (" on " .. floor) or "") .. (owner and (" of " .. owner) or ""), countOf(id, floor, temporary, owner), want)
end

-- expectCount with player 0 as the owner.
local function own(ctx, label, want, id, floor, temporary) expectCount(ctx, label, want, id, floor, temporary, keyOf(Isaac.GetPlayer(0))) end

-- One check per invariant: it fails naming every problem found.
local function holds(ctx, label, what, problems)
	ctx.checks = (ctx.checks or 0) + 1
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
	expectOne(ctx, label, 4, nil, keyOf(playerOfType(T_LAZ)))
	expectOne(ctx, label, 5, nil, keyOf(playerOfType(DEAD_LAZ)))
end

-- No list marked left, and ReHUD counts every playable player (no swapped-out form holds a list here).
local function noneLeft(ctx, label)
	expect(ctx, label .. ": left entries", leftEntries(), 0)
	expect(ctx, label .. ": characterCount = playable players", dbg().tracker.characterCount, playable())
end

return {
	fail = fail, expectN = expectN, expectOne = expectOne, expect = expect, expectCount = expectCount, own = own, holds = holds,
	c4c5 = c4c5, oneC4 = oneC4, twoC4 = twoC4, birthrightOwners = birthrightOwners, noneLeft = noneLeft,
}
