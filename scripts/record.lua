-- What the logs record about the engine and ReHUD: the state after a step, the per-update OBS trace, press verdicts and timing, ids and Inner Eye lines.
local P = include("scripts.log").P
local engine = include("scripts.game")
local ITEM_IDS, floorName, seedOf, owned, wispsOf, heldItems, pedestals, slots = engine.ITEM_IDS, engine.floorName, engine.seedOf, engine.owned,
	engine.wispsOf, engine.heldItems, engine.pedestals, engine.slots
local rehud = include("scripts.rehud")
local dbg, entries, tagText, storedSettling = rehud.dbg, rehud.entries, rehud.tagText, rehud.storedSettling
local info = include("scripts.steps").info
local enums = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, BIRTHRIGHT, PRIMARY, SECONDARY = enums.FLIP, enums.ESAU_JR, enums.CLICKER, enums.BIRTHRIGHT, enums.PRIMARY,
	enums.SECONDARY

local game = Game()

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

-- obs esaujr: no checks, only what the engine and ReHUD do and in what order. While HARNESS.obs is set, tick logs the whole state on
-- every update where it changed: one OBS line per player, roster row and tracker entry.
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
	local o = HARNESS.obs
	if not o then return end
	o.u = o.u + 1
	local lines = obsLines()
	local s = table.concat(lines, "\n")
	if s == o.last then return end
	o.last = s
	for _, l in ipairs(lines) do P("OBS u" .. o.u, "after " .. o.step .. ":", l) end
end

local function start() HARNESS.obs = { u = 0, step = "start" } end
-- OBS lines in a checked scenario: its presses keep the checked swap rule.
local function startChecked() HARNESS.obs = { u = 0, step = "start", checked = true } end
-- Later OBS lines say they follow step `tag`.
local function stepBegins(tag)
	local o = HARNESS.obs
	if o and o.step ~= tag then o.step = tag; P("OBS u" .. o.u, "step " .. tag .. " begins") end
end
-- A finished scenario's trace and timing watches.
local function stop(H) H.obs, H.timing = nil, nil end

local pocketHeld = info("player 0 pocket active (711 = Flip)", function(p) return p:GetActiveItem(ActiveSlot.SLOT_POCKET) end)
local typeNow = info("player 0 type", function(p) return p:GetPlayerType() end)
local playerCount = info("players in game", function() return game:GetNumPlayers() end)
local storedSettlingNow = info("stored forms still settling", storedSettling)

-- Seeds as labels A, B, C... in first-seen order within the scenario.
local function tagOf(ctx, seed)
	local t = ctx.tags or { n = 0 }
	ctx.tags = t
	if not t[seed] then t.n = t.n + 1; t[seed] = string.char(64 + t.n) end
	return t[seed]
end

-- Every GetPlayer index as index:label(type); a seed first seen here also shows its value.
local function lineup(ctx)
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		local s = seedOf(p)
		local new = not (ctx.tags and ctx.tags[s])
		t[#t + 1] = i .. ":" .. tagOf(ctx, s) .. "(t" .. p:GetPlayerType() .. ")" .. (new and ("=" .. s) or "")
	end
	return table.concat(t, " ")
end

-- The occupant of the pressed index once per game frame for 5 frames from its first sight with a seed other than the
-- presser's: does a new Esau Jr. form hold c703 on its very first update? HARNESS.timing lists one watch per press, as the next
-- press may come within those 5 frames; each watch ends early once its index holds a seed other than that first new one.
local function timingSee(p)
	local list = HARNESS.timing
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
				P("INFO", HARNESS.ctx.name, "TIMING", t.label, "frame", frame, "+" .. (frame - t.first), "index", t.index, "seed", seed, "type", p:GetPlayerType(),
					"c703 owned", owned(p, ESAU_JR), "primary", p:GetActiveItem(PRIMARY), "secondary", p:GetActiveItem(SECONDARY), "pocket", p:GetActiveItem(ActiveSlot.SLOT_POCKET))
			end
		end
	end
end
local function onPlayerUpdate(_, p) timingSee(p) end

-- A swap step plus its verdict line: who holds `index` after it (by label, new or returned) and the whole lineup before and after.
-- `timed` also starts timingSee.
local function verdict(label, step, index, timed)
	index = index or 0
	return function(ctx)
		if not ctx.t then
			ctx.vBefore, ctx.vSeed, ctx.vType, ctx.vSeeds = lineup(ctx), seedOf(Isaac.GetPlayer(index)), Isaac.GetPlayer(index):GetPlayerType(), {}
			for i = 0, game:GetNumPlayers() - 1 do ctx.vSeeds[seedOf(Isaac.GetPlayer(i))] = i end
			if timed then
				HARNESS.timing = HARNESS.timing or {}
				table.insert(HARNESS.timing, { index = index, seed = ctx.vSeed, label = label })
				P("INFO", ctx.name, "TIMING", label, "pressed at frame", game:GetFrameCount())
			end
		end
		local r = step(ctx)
		if r == "again" then return r end
		local p = Isaac.GetPlayer(index)
		local s = p and seedOf(p)
		local known = s and ctx.tags[s]
		local after = lineup(ctx)
		local what
		if not p then what = "nobody"
		elseif s == ctx.vSeed then
			local t = p:GetPlayerType()
			what = "unchanged" .. (t ~= ctx.vType and (" (t" .. ctx.vType .. "->" .. t .. ")") or "")
		elseif ctx.vSeeds[s] then what = tagOf(ctx, s) .. " moved from " .. ctx.vSeeds[s] -- a Birthright Flip swaps the twins' indices
		else what = tagOf(ctx, s) .. (known and " returned" or " new") end
		P("INFO", ctx.name, "VERDICT", label, "index", index, tagOf(ctx, ctx.vSeed), "->", what, "|", ctx.vBefore, "->", after)
	end
end

local slotsNow = info("player 0 slots", slots)

-- Every vanilla per-entity id of each player, each read pcall'd; twins as the GetPlayer index whose GetPtrHash matches
-- (no method is called on a returned twin but GetPtrHash).
local function ids(label)
	return function(ctx)
		local index = {}
		for i = 0, game:GetNumPlayers() - 1 do index[GetPtrHash(Isaac.GetPlayer(i))] = i end
		local function try(f)
			local ok, v = pcall(f)
			return ok and tostring(v) or ("error " .. tostring(v))
		end
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

-- G: every player's Inner Eye (c2) owned/total and item count, logged on each update it changed (H.ctx.innerWatch).
local function innerLine()
	local t = {}
	for i = 0, game:GetNumPlayers() - 1 do
		local p = Isaac.GetPlayer(i)
		t[#t + 1] = i .. ":t" .. p:GetPlayerType() .. ":seed " .. seedOf(p) .. ":c2 " .. owned(p, 2) .. "/" .. p:GetCollectibleNum(2, false) .. ":count " .. p:GetCollectibleCount()
	end
	return table.concat(t, " | ")
end
local function innerWatch()
	local ctx = HARNESS.ctx
	if not ctx.innerWatch or game:GetNumPlayers() == 0 then return end
	local s = innerLine()
	if s == ctx.innerLast then return end
	ctx.innerLast = s
	P("INFO", ctx.name, "INNER frame", game:GetFrameCount(), s)
end
local function innerOn(ctx) ctx.innerWatch = true end
local function innerInfo(what) return function(ctx) P("INFO", ctx.name, "INNER " .. what, innerLine()) end end

return {
	logState = logState, update = update, start = start, startChecked = startChecked, stepBegins = stepBegins, stop = stop, pocketHeld = pocketHeld,
	typeNow = typeNow, playerCount = playerCount, storedSettlingNow = storedSettlingNow, onPlayerUpdate = onPlayerUpdate, verdict = verdict,
	slotsNow = slotsNow, ids = ids, innerLine = innerLine, innerWatch = innerWatch, innerOn = innerOn, innerInfo = innerInfo,
}
