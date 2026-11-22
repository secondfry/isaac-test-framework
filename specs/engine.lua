-- Engine facts the presses rely on, as assertions, so a game patch that changes one fails here first.
local itemConfig = include("scripts.game").itemConfig
local give = include("scripts.console").give
local addCard = include("scripts.steps").addCard
local expect = include("scripts.assert").expect
local press = include("scripts.press")
local flip, esauJr, clicker = press.flip, press.esauJr, press.clicker
local freshRun = include("scripts.fixtures").freshRun
local ids = include("scripts.ids")
local FLIP, ESAU_JR, CLICKER, ISAAC, T_LAZ, POCKET = ids.FLIP, ids.ESAU_JR, ids.CLICKER, ids.ISAAC, ids.T_LAZ, ids.POCKET

local function maxCharges(ctx)
	for _, c in ipairs({ { CLICKER, 6 }, { ESAU_JR, 1 }, { FLIP, 6 } }) do -- want: pre-REP+ items.xml
		expect(ctx, "MaxCharges c" .. c[1], itemConfig:GetCollectible(c[1]).MaxCharges, c[2])
	end
end

-- REP+ Flip takes 4 though MaxCharges reads 6 (user, in game; run 3).
local function pocketCharge(ctx)
	local p, s = Isaac.GetPlayer(0), POCKET
	local function read() return p:GetActiveCharge(s) .. " + " .. p:GetBatteryCharge(s) end
	expect(ctx, "pocket item", p:GetActiveItem(s), FLIP)
	p:SetActiveCharge(6, s)
	expect(ctx, "SetActiveCharge(6, 2): charge + battery", read(), "4 + 2")
	p:SetActiveCharge(0, s)
	p:FullCharge(s)
	expect(ctx, "FullCharge(2) from 0: charge + battery", read(), "4 + 0")
end

local function onePress(label) return function(ctx) expect(ctx, label .. ": arms needed", ctx.arms, 1) end end

local function clickerHeld(ctx)
	local p = Isaac.GetPlayer(0)
	expect(ctx, "Clicker after a real press: active, charge", p:GetActiveItem() .. ", " .. p:GetActiveCharge(), CLICKER .. ", 0")
end

local function cardBesideFlip(ctx)
	local p, slot = Isaac.GetPlayer(0), nil
	for i = 0, 3 do
		if p:GetCard(i) == Card.CARD_SOUL_JACOB then slot = slot or i end
	end
	expect(ctx, "Soul of J&E beside Flip: card slot", slot, 1)
end

local TAGS = { "engine", "rehud" }

return { name = "engine", tests = {
	{ name = "MaxCharges reads pre-REP+ charges", tags = TAGS, fixture = freshRun(ISAAC), steps = { maxCharges } },
	{ name = "Esau Jr. takes one press", tags = TAGS, fixture = freshRun(ISAAC), steps = { give(ESAU_JR), esauJr("Esau Jr."), onePress("Esau Jr.") } },
	-- c1 after Clicker, so Clicker's 50% item removal takes c1, not Clicker
	{ name = "Clicker stays held after a real press", tags = TAGS, fixture = freshRun(ISAAC), steps = { give(CLICKER), give(1), clicker, clickerHeld } },
	{ name = "a card beside Flip sits in pocket slot 1", tags = TAGS, fixture = freshRun(T_LAZ), steps = { addCard(Card.CARD_SOUL_JACOB), cardBesideFlip } },
	{ name = "Flip takes 4 charges and one press", tags = TAGS, fixture = freshRun(T_LAZ), steps = { pocketCharge, flip("Flip"), onePress("Flip") } },
} }
