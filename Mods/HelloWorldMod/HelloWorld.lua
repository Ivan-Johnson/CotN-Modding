-- Press Shift+F1 to display debug output in-game
print("Hello world, this is Hello World!")

local Object = require "necro.game.object.Object"
local Marker = require "necro.game.tile.Marker"

-- Runs after markers are located but before the level is handed off to the
-- player, alongside other mods' extra entity placement (e.g. quantum chests).
event.levelLoad.add("SpawnApplesOnStairs", { order = "extraEntities" }, function()
	-- This is supposed to spawn apples on top of the exit stairs
	-- TODO - find out why it is instead spawning them at the start of level
	for _, pos in ipairs(Marker.lookUpAll(Marker.Type.STAIRS)) do
		Object.spawn("Food1", pos.x, pos.y)
	end
end)
