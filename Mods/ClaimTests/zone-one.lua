-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Surveys the 24 regular levels of zone 1 from eight all-zones runs, and the
-- 24 of eight single-zone runs, the same levels every time, and checks what
-- each set holds.
testsApi.registerTest({
	name = "zoneOneContents",
	character = "Cadence",
	async = true,
	timeoutTicks = 24000,
	onLoad = function(_, finish)
		local function check(census)
			fixtures.assertAllPresent(census.tiles, {
				"DirtWall", "StoneWall", "CatacombWall", "ShopWall", "DoorHorizontal",
				"DoorVertical", "Water",
			}, "tile")
			fixtures.assertAllPresent(census.entities, {
				"Slime", "Slime2", "Slime3", "Skeleton", "Skeleton2", "Skeleton3", "Zombie",
				"Monkey", "Monkey2", "Bat", "Ghost", "Wraith", "BounceTrapUp",
				"BounceTrapDown", "BounceTrapLeft", "BounceTrapRight", "SpikeTrap",
				"Sync_AutoSpikeTrap", "BombTrap", "TempoUpTrap", "TempoDownTrap", "Sync_DiceTrap",
				"Trapdoor", "Sync_FloorCrack",
			}, "entity")
			for _, bounce in ipairs({
				"BounceTrapOmni", "BounceTrapUpLeft", "BounceTrapUpRight", "BounceTrapDownLeft",
				"BounceTrapDownRight",
			}) do
				assert(not census.entities[bounce], "no " .. bounce)
			end
		end
		fixtures.zoneCensus(1, 8, false, function(allZones)
			check(allZones)
			assert(allZones.entities.Bat2, "Bat2 in an all-zones run")
			fixtures.zoneCensus(1, 8, true, function(singleZone)
				check(singleZone)
				assert(not singleZone.entities.Bat2, "no Bat2 in a single-zone run")
				finish()
			end)
		end)
	end,
})
