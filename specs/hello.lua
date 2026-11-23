-- The harness itself on vanilla, ReHUD not needed: a fresh run, Clicker on Isaac, and what the seed command does.
local P = include("scripts.log").P
local engine = include("scripts.game")
local seeds, heldItems, chargeOf = engine.seeds, engine.heldItems, engine.chargeOf
local console = include("scripts.console")
local fresh, give, seed = console.fresh, console.give, console.seed
local expect = include("scripts.assert").expect
local snap = include("scripts.record").snap
local clicker = include("scripts.press").clicker
local freshRun = include("scripts.fixtures").freshRun
local snapshotTest = include("scripts.snapshot").test
local ids = include("scripts.ids")
local CLICKER, ISAAC, T_LAZ, PRIMARY = ids.CLICKER, ids.ISAAC, ids.T_LAZ, ids.PRIMARY

local game = Game()
local VANILLA = { "hello", "vanilla" }

-- The seed recon's reads: the start seed, each player's item seed, and player 0's InitSeed, type and items.
local function seedsNow(what)
	return function(ctx)
		local p = Isaac.GetPlayer(0)
		P("INFO", ctx.name, "SEEDS", what, "start seed", game:GetSeeds():GetStartSeedString(), "item seeds", seeds(), "InitSeed", p.InitSeed,
			"type", p:GetPlayerType(), "items", heldItems(p))
	end
end

return { name = "hello", tests = {
	snapshotTest("fresh Isaac on a fixed seed", VANILLA, freshRun(ISAAC), {}),
	-- Which type Clicker rolls on a seed is unobserved, so it is a snapshot value, not an assertion. Clicker's 50% item removal may take
	-- Clicker itself (unobserved): the charge assertion then fails.
	{ name = "Clicker on Isaac", tags = VANILLA, fixture = freshRun(ISAAC), steps = {
		function(ctx) expect(ctx, "player 0 type", Isaac.GetPlayer(0):GetPlayerType(), ISAAC) end,
		give(CLICKER),
		function(ctx) expect(ctx, "player 0 primary active", Isaac.GetPlayer(0):GetActiveItem(PRIMARY), CLICKER) end,
		clicker,
		function(ctx)
			local p = Isaac.GetPlayer(0)
			snap(ctx, "Clicker roll / type", p:GetPlayerType())
			expect(ctx, "Clicker charge after the use", chargeOf(p, CLICKER, PRIMARY), 0)
		end,
	} },
	-- Recon: no assertions; what the seed command and restarts do to the seeds, which console.fresh relies on (session 1).
	snapshotTest("fresh run on a fixed seed", { "hello", "vanilla", "seed" }, freshRun(ISAAC), {
		{ "seeds after restart 0", seedsNow("after restart 0") },
		{ "seed command", seed() }, { "seeds after the seed command", seedsNow("after the seed command") },
		{ "seed command again", seed() }, { "seeds after the second seed command", seedsNow("after the second seed command") },
		{ "restart 0", fresh(ISAAC) }, { "seeds after restart 0 again", seedsNow("after restart 0 again") },
		{ "restart 29", fresh(T_LAZ) }, { "seeds after restart 29", seedsNow("after restart 29") },
	}, { strict = true }),
} }
