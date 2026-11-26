-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Surveys the 24 regular levels of zone 5 from eight all-zones runs, the same
-- levels every time, and checks what they hold.
testsApi.registerTest({
	name = "zoneFiveContents",
	character = "Cadence",
	async = true,
	timeoutTicks = 12000,
	onLoad = function(_, finish)
		fixtures.zoneCensus(5, 8, false, function(census)
			fixtures.assertAllPresent(census.tiles, { "Wire", "WireDoorHorizontal", "WireDoorVertical" }, "tile")
			fixtures.assertAllPresent(census.entities, {
				"ScatterTrap", "ZombieElectric", "ElectricMage", "ElectricMage2", "ElectricMage3",
				"Devil", "Devil2", "Evileye", "Evileye2", "Gorgon", "Gorgon2", "Orc", "Orc2",
				"Orc3", "Skull", "Skull2", "Skull3", "WaterBall", "Wraith2",
			}, "entity")
			assert(census.tiles.Wire == census.levels, "wire on every level")
			finish()
		end)
	end,
})
