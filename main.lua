-- ReHUD test harness: on the first new run after launch it plays its tests by itself and logs PROBE/RESULT lines to log.txt.
-- Needs the `ReHUD.dbg` hook (ReHUD cf965b0 or later). This file only wires: the tests to the runner, the handlers to the game.
local mod = RegisterMod("ReHUD Test Harness", 1)
local runner = include("scripts.runner")
local press = include("scripts.press")
local record = include("scripts.record")
local characters = include("scripts.characters")
local console = include("scripts.console")

HARNESS.mod = mod
runner.add(include("specs.legacy"))
runner.onTeardown(press.teardown)
runner.onTeardown(record.stop)

-- Registration order matters within one callback: the engine runs same-priority callbacks in the order they were added.
mod:AddCallback(ModCallbacks.MC_USE_ITEM, press.onUse)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, press.onPlayerUpdate)
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, press.onInput)
mod:AddPriorityCallback(ModCallbacks.MC_PRE_USE_ITEM, CallbackPriority.LATE, press.onVetoPre, CollectibleType.COLLECTIBLE_CLICKER)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, press.onClickerUse, CollectibleType.COLLECTIBLE_CLICKER)
mod:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.EARLY, press.onVetoUpdate)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, record.onPlayerUpdate)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, runner.guard(function()
	record.update()
	runner.tick(characters.track, record.innerWatch)
end))
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
	console.flush()
	runner.render()
end)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	characters.onGameStart(isContinued)
	runner.onGameStart(isContinued)
end)
