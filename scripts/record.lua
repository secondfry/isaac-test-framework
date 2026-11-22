-- What the logs record about the engine and ReHUD: the state after a step, the per-update TRACE, snapshot SNAP lines, press verdicts
-- and timing, ids and Inner Eye lines. HARNESS.record holds the trace and the timing watches.
local P = include("scripts.log").P
local engine = include("scripts.game")
local ITEM_IDS, floorName, seedOf, owned, wispsOf, heldItems, pedestals, slots, findPlayer = engine.ITEM_IDS, engine.floorName, engine.seedOf,
	engine.owned, engine.wispsOf, engine.heldItems, engine.pedestals, engine.slots, engine.findPlayer
local rehud = include("scripts.rehud")
local dbg, entries, tagText, storedSettling, keyOf = rehud.dbg, rehud.entries, rehud.tagText, rehud.storedSettling, rehud.keyOf
local info = include("scripts.steps").info
local enums = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT, PRIMARY, SECONDARY = enums.FLIP, enums.ESAU_JR, enums.CLICKER, enums.BIRTHRIGHT, enums.PRIMARY,
	enums.SECONDARY

local game = Game()
HARNESS.record = HARNESS.record or {}

-- A read that may throw (a method the engine lacks, a removed twin): its value, or the error, as text.
local function try(f)
	local ok, v = pcall(f)
	return ok and tostring(v) or ("error " .. tostring(v))
end

-- The whole state after a step: the floor, each player and its items, each ReHUD entry.
local function logState(ctx, label)
	P("STEP", ctx.name, label, "floor", floorName(), "stage", game:GetLevel():GetStage())
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		P("PLAYER", i, "type", p:GetPlayerType(), "ctrl", p.ControllerIndex, "variant", p.Variant, "parent", p.Parent ~= nil,
			"ghost", p:IsCoopGhost(), "seed", seedOf(p), "count", p:GetCollectibleCount())
		local wispOf = wispsOf(p)
		for _, id in ipairs(ITEM_IDS) do
			local all = p:GetCollectibleNum(id, false)
			if all > 0 then
				local own, w = owned(p, id), wispOf[id] or 0
				P("ITEM", i, "c" .. id, "owned", own, "wisp", w, "other", all - own - w)
			end
		end
	end
	for n, e in ipairs(entries()) do
		P("ENTRY", n, "c" .. e.id, "number", e.number, "owner", e.owner, "floor", e.floor, "temporary", e.temporary, "left", e.left, "merged", e.merged)
	end
end

-- The trace: what the engine and ReHUD do and in what order. While a trace runs, update logs the whole state on every update where it
-- changed: one TRACE line per player, roster row and tracker entry.
local OBS_IDS = { 2, 4, 5, ESAU_JR, FLIP, CLICKER, BIRTHRIGHT }
local function obsLines()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p, n = Isaac.GetPlayer(i), {}
		for _, id in ipairs(OBS_IDS) do n[#n + 1] = "c" .. id .. " " .. p:GetCollectibleNum(id, false) end
		t[#t + 1] = "PLAYER " .. i .. " type " .. p:GetPlayerType() .. " seed " .. seedOf(p) .. " hash " .. GetPtrHash(p) .. " ctrl " .. p.ControllerIndex
			.. " parent " .. tostring(p.Parent ~= nil) .. " " .. table.concat(n, " ") .. " primary " .. p:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
			.. " secondary " .. p:GetActiveItem(ActiveSlot.SLOT_SECONDARY) .. " pocket " .. p:GetActiveItem(ActiveSlot.SLOT_POCKET)
		t[#t + 1] = "PLAYERX " .. i .. " variant " .. p.Variant .. " ghost " .. tostring(p:IsCoopGhost()) .. " Index " .. p.Index .. " tag " .. tagText(p)
			.. " charge primary " .. p:GetActiveCharge(ActiveSlot.SLOT_PRIMARY) .. "+" .. p:GetBatteryCharge(ActiveSlot.SLOT_PRIMARY)
			.. " pocket " .. p:GetActiveCharge(ActiveSlot.SLOT_POCKET) .. "+" .. p:GetBatteryCharge(ActiveSlot.SLOT_POCKET) .. " items " .. heldItems(p)
	end
	t[#t + 1] = "COUNT players " .. game:GetNumPlayers() .. " c703 pedestals " .. pedestals(ESAU_JR)
	local rows = dbg().roster.serialize()
	table.sort(rows, function(a, b) return (a.number or -1) < (b.number or -1) end)
	for _, r in ipairs(rows) do
		t[#t + 1] = "ROSTER key " .. tostring(r.key) .. " number " .. tostring(r.number) .. " swapped " .. tostring(r.swapped) .. " partner " .. tostring(r.partner) .. " left " .. tostring(r.left) .. " type " .. tostring(r.type) .. " group " .. tostring(r.group)
	end
	for n, e in ipairs(entries()) do t[#t + 1] = "ENTRY " .. n .. " c" .. e.id .. " owner " .. tostring(e.owner) .. " floor " .. tostring(e.floor) .. " merged " .. tostring(e.merged) .. " temporary " .. tostring(e.temporary) end
	return t
end

local function update()
	local o = HARNESS.record.trace
	if not o then return end
	o.u = o.u + 1
	local lines = obsLines()
	local s = table.concat(lines, "\n")
	if s == o.last then return end
	o.last = s
	for _, l in ipairs(lines) do P("TRACE u" .. o.u, "after " .. o.step .. ":", l) end
end

local function start() HARNESS.record.trace = { u = 0, step = "start" } end
-- A trace in a test with assertions: its presses keep the checked swap rule.
local function startChecked() HARNESS.record.trace = { u = 0, step = "start", checked = true } end
-- A traceUpdates test's trace starts once its fixture is done.
local function onTraceStarts(test)
	if test.snapshot then start() else startChecked() end
end
-- Later TRACE lines say they follow step `tag`.
local function stepBegins(tag)
	local o = HARNESS.record.trace
	if o and o.step ~= tag then o.step = tag; P("TRACE u" .. o.u, "step " .. tag .. " begins") end
end
-- A given-up step's timing watches.
local function stopTiming() HARNESS.record.timing = nil end
-- A finished test's trace and timing watches.
local function stop() HARNESS.record.trace, HARNESS.record.timing = nil, nil end

local pocketHeld = info("player 0 pocket active (711 = Flip)", function(p) return p:GetActiveItem(ActiveSlot.SLOT_POCKET) end)
local typeNow = info("player 0 type", function(p) return p:GetPlayerType() end)
local playerCount = info("players in game", function() return game:GetNumPlayers() end)
local storedSettlingNow = info("stored forms still settling", storedSettling)

-- Snapshot values: game state only, no raw hash, seed or Index, so a value compares across sessions. `kind`'s values get labels in
-- first-seen order within the test: entities (by GetPtrHash) A, B..., other kinds kind1, kind2...
local function labelOf(ctx, kind, value)
	if value == nil then return "none" end
	ctx.snapLabels = ctx.snapLabels or {}
	local t = ctx.snapLabels[kind] or { n = 0 }
	ctx.snapLabels[kind] = t
	if not t[value] then
		t.n = t.n + 1
		t[value] = kind ~= "entity" and (kind .. t.n) or t.n <= 26 and string.char(64 + t.n) or ("E" .. t.n)
	end
	return t[value]
end
-- An entity's label; no method is called on it, as a returned twin or Parent may be a removed entity (lua-api-notes.md).
local function label(ctx, e) return e and labelOf(ctx, "entity", GetPtrHash(e)) or "none" end

-- Every GetPlayer index as index:label(type), each character labelled by its entity as the snapshot labels it (bug 7: seeds are shared);
-- an entity first seen in a lineup also shows its seed.
local function lineup(ctx)
	ctx.lineupSeen = ctx.lineupSeen or {}
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		local h = GetPtrHash(p)
		t[#t + 1] = i .. ":" .. label(ctx, p) .. "(t" .. p:GetPlayerType() .. ")" .. (ctx.lineupSeen[h] and "" or ("=" .. seedOf(p)))
		ctx.lineupSeen[h] = true
	end
	return table.concat(t, " ")
end

-- The occupant of the pressed index once per game frame for 5 frames from its first sight with a seed other than the
-- presser's: does a new Esau Jr. form hold c703 on its very first update? The timing list holds one watch per press, as the next
-- press may come within those 5 frames; each watch ends early once its index holds a seed other than that first new one.
local function timingSee(p)
	local list = HARNESS.record.timing
	if not list then return end
	for i = #list, 1, -1 do
		local t = list[i]
		local occupant = Isaac.GetPlayer(t.index)
		local seed, frame = seedOf(p), game:GetFrameCount()
		if occupant and GetPtrHash(occupant) == GetPtrHash(p) and (seed ~= t.seed or t.first) then
			t.first, t.firstSeed = t.first or frame, t.firstSeed or seed
			if frame - t.first >= 5 or seed ~= t.firstSeed then table.remove(list, i)
			elseif frame ~= t.logged then -- MC_POST_PLAYER_UPDATE runs twice per game frame
				t.logged = frame
				P("INFO", HARNESS.session.ctx.name, "TIMING", t.label, "frame", frame, "+" .. (frame - t.first), "index", t.index, "seed", seed, "type", p:GetPlayerType(),
					"c703 owned", owned(p, ESAU_JR), "primary", p:GetActiveItem(PRIMARY), "secondary", p:GetActiveItem(SECONDARY), "pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET))
			end
		end
	end
end
local function onPlayerUpdate(_, p) timingSee(p) end

-- A swap step plus its verdict line: who holds `index` after it (by entity label, new or returned) and the whole lineup before and
-- after. `timed` also starts timingSee.
local function verdict(press, step, index, timed)
	index = index or 0
	return function(ctx)
		if not ctx.t then
			local presser = Isaac.GetPlayer(index)
			ctx.vBefore, ctx.vHash, ctx.vType, ctx.vAt = lineup(ctx), GetPtrHash(presser), presser:GetPlayerType(), {}
			for i = 0, game:GetNumPlayers() - 1 do ctx.vAt[GetPtrHash(Isaac.GetPlayer(i))] = i end
			if timed then
				local R = HARNESS.record
				R.timing = R.timing or {}
				table.insert(R.timing, { index = index, seed = seedOf(presser), label = press })
				P("INFO", ctx.name, "TIMING", press, "pressed at frame", game:GetFrameCount())
			end
		end
		local r = step(ctx)
		if ctx.sameSeed then -- press.sameSeedForm: the seed never changes, so this watch would wake on a later press
			local list = HARNESS.record.timing or {}
			for i = #list, 1, -1 do if list[i].label == ctx.sameSeed then table.remove(list, i) end end
			ctx.sameSeed = nil
		end
		if r == "again" then return r end
		local p = Isaac.GetPlayer(index)
		local h = p and GetPtrHash(p)
		local known = h and ctx.lineupSeen[h]
		local after = lineup(ctx)
		local what
		if not p then what = "nobody"
		elseif h == ctx.vHash then
			local t = p:GetPlayerType()
			what = "unchanged" .. (t ~= ctx.vType and (" (t" .. ctx.vType .. "->" .. t .. ")") or "")
		elseif ctx.vAt[h] then what = label(ctx, p) .. " moved from " .. ctx.vAt[h] -- a Birthright Flip swaps the twins' indices
		else what = label(ctx, p) .. (known and " returned" or " new") end
		P("INFO", ctx.name, "VERDICT", press, "index", index, labelOf(ctx, "entity", ctx.vHash), "->", what, "|", ctx.vBefore, "->", after)
	end
end

local slotsNow = info("player 0 slots", slots)

-- Each player's Parent (as a GetPlayer index), ControllerIndex and ReHUD key and number: which character a temporary one's number follows.
local function helpersInfo(what)
	return function(ctx)
		for i = 0, game:GetNumPlayers() - 1 do
			local p = Isaac.GetPlayer(i)
			local parent = p.Parent and select(2, findPlayer(function(q) return GetPtrHash(q) == GetPtrHash(p.Parent) end))
			P("INFO", ctx.name, "HELPERS", what, "index", i, "type", p:GetPlayerType(), "parent", p.Parent and ("index " .. tostring(parent)) or "none",
				"ctrl", p.ControllerIndex, "key", keyOf(p), "number", tostring(dbg().roster.number(keyOf(p))))
		end
	end
end

-- Every vanilla per-entity id of each player, each read pcall'd; twins as the GetPlayer index whose GetPtrHash matches
-- (no method is called on a returned twin but GetPtrHash).
local function ids(label)
	return function(ctx)
		local index = {}
		for i = 0, game:GetNumPlayers() - 1 do index[GetPtrHash(Isaac.GetPlayer(i))] = i end
		for i = 0, game:GetNumPlayers() - 1 do
			local p = Isaac.GetPlayer(i)
			local function twin(m)
				return try(function()
					local t = p[m](p)
					if t == nil then return "nil" end
					local k = index[GetPtrHash(t)]
					return k and ("index " .. k) or "not a player"
				end)
			end
			P("INFO", ctx.name, "IDS", label, "index", i, "type", p:GetPlayerType(), "CollectibleRNG(1)", seedOf(p), "hash", GetPtrHash(p),
				"InitSeed", try(function() return p.InitSeed end), "DropSeed", try(function() return p.DropSeed end), "Index", try(function() return p.Index end),
				"CardRNG(1)", try(function() return p:GetCardRNG(1):GetSeed() end), "PillRNG(1)", try(function() return p:GetPillRNG(1):GetSeed() end),
				"TrinketRNG(1)", try(function() return p:GetTrinketRNG(1):GetSeed() end), "OtherTwin", twin("GetOtherTwin"), "MainTwin", twin("GetMainTwin"))
		end
	end
end

-- G: every player's Inner Eye (c2) owned/total and item count, logged on each update it changed (ctx.innerWatch).
local function innerLine()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		t[#t + 1] = i .. ":t" .. p:GetPlayerType() .. ":seed " .. seedOf(p) .. ":c2 " .. owned(p, 2) .. "/" .. p:GetCollectibleNum(2, false) .. ":count " .. p:GetCollectibleCount()
	end
	return table.concat(t, " | ")
end
local function innerWatch(ctx)
	if not ctx.innerWatch or game:GetNumPlayers() == 0 then return end
	local s = innerLine()
	if s == ctx.innerLast then return end
	ctx.innerLast = s
	P("INFO", ctx.name, "INNER frame", game:GetFrameCount(), s)
end
local function innerOn(ctx) ctx.innerWatch = true end
local function innerInfo(what) return function(ctx) P("INFO", ctx.name, "INNER " .. what, innerLine()) end end

local function snap(ctx, key, value) P("SNAP", ctx.name, "|", key, "=", value) end

-- Player `p` after step `step`: the harness tags it (GetData) with its label once, and reads the tag back each time.
local function describe(ctx, step, p)
	local L = label(ctx, p)
	local d = p:GetData()
	if type(d) == "table" and d.harness == nil then d.harness = L end
	local function put(name, f) snap(ctx, step .. " / " .. L .. " " .. name, try(f)) end
	local function slotsOf(read, n)
		return function()
			local t = {}
			for i = 0, n do t[#t + 1] = read(i) end
			return table.concat(t, " ")
		end
	end
	put("type", function() return p:GetPlayerType() end)
	put("name", function() return p:GetName() end)
	put("seed", function() return labelOf(ctx, "s", seedOf(p)) end)
	put("InitSeed", function() return labelOf(ctx, "i", p.InitSeed) end)
	put("Index", function() return labelOf(ctx, "x", p.Index) end)
	put("items", function() return heldItems(p) end)
	put("actives", slotsOf(function(s) return p:GetActiveItem(s) .. ":" .. p:GetActiveCharge(s) .. "+" .. p:GetBatteryCharge(s) end, 3))
	put("trinkets", slotsOf(function(s) return p:GetTrinket(s) end, 1))
	put("cards", slotsOf(function(s) return p:GetCard(s) end, 3))
	put("pills", slotsOf(function(s) return p:GetPill(s) end, 3))
	put("twin", function() return label(ctx, p:GetOtherTwin()) end)
	put("main twin", function() return label(ctx, p:GetMainTwin()) end)
	put("parent", function() return label(ctx, p.Parent) end)
	put("sub player", function() return label(ctx, p:GetSubPlayer()) end)
	put("tag", function() return type(d) == "table" and d.harness or "none" end)
end

-- The runner's snap event: a snapshot test's state after step `step`, or that it never happened.
local function snapStep(ctx, step, reached)
	if not reached then return snap(ctx, step, "never happened") end
	local lineup, found = {}, {}
	for i = 0, game:GetNumPlayers() - 1 do lineup[#lineup + 1] = label(ctx, Isaac.GetPlayer(i)) end
	for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PLAYER)) do found[#found + 1] = label(ctx, e) end
	snap(ctx, step .. " / lineup", table.concat(lineup, " "))
	snap(ctx, step .. " / players", table.concat(found, " "))
	for i = 0, game:GetNumPlayers() - 1 do describe(ctx, step, Isaac.GetPlayer(i)) end
end

return {
	logState = logState, update = update, startChecked = startChecked, onTraceStarts = onTraceStarts, stepBegins = stepBegins,
	stopTiming = stopTiming, stop = stop, pocketHeld = pocketHeld, typeNow = typeNow, playerCount = playerCount, storedSettlingNow = storedSettlingNow,
	onPlayerUpdate = onPlayerUpdate, verdict = verdict, slotsNow = slotsNow, helpersInfo = helpersInfo, ids = ids, innerLine = innerLine, innerWatch = innerWatch,
	innerOn = innerOn, innerInfo = innerInfo, label = label, snap = snap, snapStep = snapStep,
}
