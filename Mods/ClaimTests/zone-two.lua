-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Surveys the 24 regular levels of zone 2 from eight all-zones runs, the same
-- levels every time, and checks what they hold.
testsApi.registerTest({
	name = "zoneTwoContents",
	character = "Cadence",
	async = true,
	timeoutTicks = 12000,
	onLoad = function(_, finish)
		fixtures.zoneCensus(2, 8, false, function(census)
			fixtures.assertAllPresent(census.tiles, { "Grass1", "Grass2", "Grass3", "Tar" }, "tile")
			fixtures.assertAllPresent(census.entities, {
				"BounceTrapOmni", "Mushroom", "Mushroom2", "MushroomExploding", "MushroomLight",
				"Fakewall", "Clone", "Mole", "Tarmonster", "Armadillo", "Armadillo2",
				"Armoredskeleton", "Armoredskeleton2", "Armoredskeleton3", "Skeletonmage",
				"Skeletonmage2", "Skeletonmage3", "Golem", "Golem2", "Wight",
			}, "entity")
			assert(census.tiles.Grass1 == census.levels, "grass on every level")
			finish()
		end)
	end,
})
