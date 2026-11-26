-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Surveys the 24 regular levels of zone 4 from eight all-zones runs, the same
-- levels every time, and checks what they hold.
testsApi.registerTest({
	name = "zoneFourContents",
	character = "Cadence",
	async = true,
	timeoutTicks = 12000,
	onLoad = function(_, finish)
		fixtures.zoneCensus(4, 8, false, function(census)
			fixtures.assertAllPresent(census.tiles, { "Ooze" }, "tile")
			fixtures.assertAllPresent(census.entities, {
				"BounceTrapUpLeft", "BounceTrapUpRight", "BounceTrapDownLeft",
				"BounceTrapDownRight", "ConfusionTrap", "Sarcophagus", "Sarcophagus2",
				"Sarcophagus3", "Gargoyle", "Gargoyle2", "Gargoyle3", "Harpy", "Spider",
				"SleepingGoblin", "GoblinBomber", "FirepigLeft", "FirepigRight", "Lich", "Lich2",
				"Lich3", "Warlock", "Warlock2", "Blademaster", "Blademaster2", "Ghoul", "Monkey3",
				"Monkey4", "Bat4", "Golem3", "Ogre", "Mommy", "Pixie", "Armadillo3",
			}, "entity")
			finish()
		end)
	end,
})
