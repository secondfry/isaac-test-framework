HARNESS = HARNESS or {} -- each module keeps its state under its own key; Lua state survives restart and exit/continue
-- ReHUD test harness: on the first new run after launch it plays its tests by itself and logs PROBE/RESULT lines to log.txt.
-- Needs the `ReHUD.dbg` hook (ReHUD cf965b0 or later). This file only wires: the specs to the runner, the handlers to the game.
local mod = RegisterMod("ReHUD Test Harness", 1)
local runner = include("scripts.runner")
local wait = include("scripts.wait")
local callbacks = include("scripts.callbacks")
local console = include("scripts.console")
local press = include("scripts.press")
local characters = include("scripts.characters")
local record = include("scripts.record")

local SPECS = { "hello", "engine", "characters", "esau_jr", "base_change", "continue", "item_copies", "regressions", "revive" }

runner.setMod(mod)
for _, name in ipairs(SPECS) do runner.add(include("specs." .. name)) end
runner.on("teardown", console.reset)
runner.on("teardown", press.teardown)
runner.on("teardown", record.stop)
runner.on("teardown", callbacks.reset)
runner.on("busy", console.busy)
runner.on("stepBegins", record.stepBegins)
runner.on("giveUp", wait.resetStep)
runner.on("giveUp", press.teardown)
runner.on("giveUp", record.stopTiming)
runner.on("snap", record.snapStep)
runner.on("fixtureDone", record.onFixtureDone)

-- Registration order matters within one callback: the engine runs same-priority callbacks in the order they were added.
mod:AddCallback(ModCallbacks.MC_USE_ITEM, press.onUse)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, callbacks.count(ModCallbacks.MC_USE_ITEM))
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, press.onPlayerUpdate)
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, press.onInput)
mod:AddPriorityCallback(ModCallbacks.MC_PRE_USE_ITEM, CallbackPriority.LATE, press.onVetoPre, CollectibleType.COLLECTIBLE_CLICKER)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, press.onClickerUse, CollectibleType.COLLECTIBLE_CLICKER)
mod:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.EARLY, press.onVetoUpdate)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, record.onPlayerUpdate)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, runner.guard(function()
	record.update()
	runner.tick(characters.track)
end))
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
	console.flush()
	runner.render()
end)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	characters.onGameStart(isContinued)
	runner.onGameStart(isContinued)
end)
