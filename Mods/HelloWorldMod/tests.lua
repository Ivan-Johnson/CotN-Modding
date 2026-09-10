local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local Map = require "necro.game.object.Map"
local Marker = require "necro.game.tile.Marker"

-- Optional dependency on HelloWorldModTests' generic test framework.
-- Deliberately not declared in mod.json: this mod must not require players
-- to install the test-only mod. If HelloWorldModTests isn't installed (or
-- hasn't loaded yet this cycle), the require fails and this script quietly
-- registers nothing.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end

testsApi.registerTest({
	name = "appleSpawnsOnStairs",
	onLoad = function(fixedSeed)
		assert(CurrentLevel.getSeed() == fixedSeed, string.format(
			"expected level seed %d, got %s", fixedSeed, tostring(CurrentLevel.getSeed())))

		local stairs = Marker.lookUpAll(Marker.Type.STAIRS)
		assert(#stairs == 1, string.format(
			"expected exactly 1 stairs marker, got %d", #stairs))

		local entityIDs = Map.getAll(stairs[1][1], stairs[1][2])
		local foundApple = false
		for _, entityID in ipairs(entityIDs) do
			if Entities.getEntityTypeName(Entities.getEntityByID(entityID)) == "Food1" then
				assert(not foundApple, "Expected exactly one apple")
				foundApple = true
			end
		end
	end,
})
