-- Press Shift+F1 to display debug output in-game
print("Hello world, this is Hello World! 9")

local Object = require "necro.game.object.Object"
local Marker = require "necro.game.tile.Marker"

-- Runs after markers are located but before the level is handed off to the
-- player, alongside other mods' extra entity placement (e.g. quantum chests).
event.levelLoad.add("SpawnApplesOnStairs", { order = "extraEntities" }, function()
	for _, pos in ipairs(Marker.lookUpAll(Marker.Type.STAIRS)) do
		Object.spawn("Food1", pos[1], pos[2])
	end
end)
