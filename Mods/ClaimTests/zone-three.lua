-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Surveys the 24 regular levels of zone 3 from eight all-zones runs, the same
-- levels every time, and checks what they hold.
testsApi.registerTest({
	name = "zoneThreeContents",
	character = "Cadence",
	async = true,
	timeoutTicks = 12000,
	onLoad = function(_, finish)
		fixtures.zoneCensus(3, 8, false, function(census)
			fixtures.assertAllPresent(census.tiles, { "CatacombWall" }, "tile")
			fixtures.assertAllPresent(census.entities, {
				"Piston", "TeleportTrap", "ConfusionTrap", "Fireelemental", "Iceelemental", "Yeti",
				"Hellhound", "Cauldron", "Cauldron2", "Slime4", "Slime5", "Beetle", "Beetle2",
				"Skeletonknight", "Skeletonknight2", "Skeletonknight3", "Goblin", "Goblin2",
				"Shovemonster", "Shovemonster2", "Ghast",
			}, "entity")
			finish()
		end)
	end,
})
