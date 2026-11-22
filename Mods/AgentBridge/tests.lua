local Action = require "necro.game.system.Action"
local Blockers = require "AgentBridge.Blockers"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local Tile = require "necro.game.tile.Tile"

-- Optional, like HelloWorld/tests.lua: without HelloWorldTests this registers nothing.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end

testsApi.registerTest({
	name = "blockersNameWhatStandsOnTheTile",
	onLoad = function()
		local player = Player.getPlayerEntity()
		local from = { x = player.position.x, y = player.position.y }
		local open
		local D = Action.Direction
		for _, direction in ipairs({ D.RIGHT, D.LEFT, D.UP, D.DOWN }) do
			if not Tile.isSolid(from.x + Action.dx(direction), from.y + Action.dy(direction)) then
				open = direction
				break
			end
		end
		assert(open, "no open tile beside the player")
		assert(Blockers.at(from, open) == nil, "an empty tile blocks nothing")

		Object.spawn("Shopkeeper", from.x + Action.dx(open), from.y + Action.dy(open))
		local blockers = Blockers.at(from, open)
		assert(blockers and blockers[1].type == "Shopkeeper", "expected a Shopkeeper blocker")
		assert(Blockers.at(from, Action.Special.IDLE) == nil, "a non-move blocks nothing")
	end,
})
