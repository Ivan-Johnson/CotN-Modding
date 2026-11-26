local Boss = require "necro.game.level.Boss"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Player = require "necro.game.character.Player"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test starts an all-zones run itself, since the framework starts a
-- single-zone one, and reads the run's levels from the level sequence the
-- run generates. The dungeon seed is random per run, so the bosses differ
-- between runs.

local sequence
event.levelSequenceUpdate.add("ClaimTestsAllZonesSequence", { order = "storyBosses", sequence = 10 }, function(ev)
	sequence = ev.sequence
end)

local function itemNames()
	local names = {}
	for _, item in ipairs(Inventory.getItems(fixtures.player())) do
		names[#names + 1] = item.name
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function whenOnLevel(number, andThen)
	if CurrentLevel.isLoading() or CurrentLevel.getNumber() ~= number or CurrentLevel.getMode().id ~= "AllZones" then
		testsApi.afterTicks(10, function()
			whenOnLevel(number, andThen)
		end)
		return
	end
	testsApi.afterTicks(300, andThen)
end

local function startAllZones(character, andThen)
	Player.setCharacterType(1, character)
	sequence = nil
	testsApi.afterTicks(100, function()
		GameSession.start({ mode = GameSession.Mode.AllZones })
		testsApi.afterTicks(50, function()
			whenOnLevel(1, andThen)
		end)
	end)
end

local function allZonesTest(name, character, check)
	testsApi.registerTest({
		name = name,
		character = character,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			startAllZones(character, function()
				check(finish)
			end)
		end,
	})
end

-- Five zones of three levels and a boss level, then the NecroDancer on 5-5.
-- Zones 1 to 4 each get a different one of the five zone bosses; zone 5 is
-- always Dead Ringer.
allZonesTest("allZonesCadenceLevels", "Cadence", function(finish)
	assert(#sequence == 21, "levels: " .. #sequence)
	local zoneBosses = {
		[Boss.Type.KING_CONGA] = true,
		[Boss.Type.DEATH_METAL] = true,
		[Boss.Type.DEEP_BLUES] = true,
		[Boss.Type.CORAL_RIFF] = true,
		[Boss.Type.FORTISSIMOLE] = true,
	}
	local seen = {}
	for index, level in ipairs(sequence) do
		local zone = math.floor((index - 1) / 4) + 1
		local floor = (index - 1) % 4 + 1
		if index == 21 then
			zone, floor = 5, 5
		end
		local where = "level " .. index .. " (" .. level.zone .. "-" .. level.floor .. ")"
		assert(level.zone == zone and level.floor == floor, where)
		assert((level.isFinal == true) == (index == 21), where .. " final")
		if floor <= 3 then
			assert(level.type == "Necro" and not level.boss, where .. " is a regular level")
		else
			assert(level.type == "Boss", where .. " is a boss level")
			if zone <= 4 then
				assert(zoneBosses[level.boss] and not seen[level.boss], where .. " boss " .. level.boss)
				seen[level.boss] = true
			elseif floor == 4 then
				assert(level.boss == Boss.Type.DEAD_RINGER, where .. " boss " .. level.boss)
			else
				assert(level.boss == Boss.Type.NECRODANCER, where .. " boss " .. level.boss)
			end
		end
	end
	finish()
end)

-- Dove's run has the same five zones with no boss levels.
allZonesTest("allZonesDoveLevels", "Dove", function(finish)
	assert(#sequence == 15, "levels: " .. #sequence)
	for index, level in ipairs(sequence) do
		local where = "level " .. index .. " (" .. level.zone .. "-" .. level.floor .. ")"
		assert(level.zone == math.floor((index - 1) / 3) + 1 and level.floor == (index - 1) % 3 + 1, where)
		assert(level.type == "Necro" and not level.boss, where .. " is a regular level")
		assert((level.isFinal == true) == (index == 15), where .. " final")
	end
	finish()
end)

-- Cadence and Dove each start with 6 health and none of the single-zone bonus
-- items.
for character, items in pairs({
	Cadence = "Bomb,ShovelBasic,WeaponDagger",
	Dove = "Bomb,RingPeace,ShovelCrystal,WeaponFlower",
}) do
	allZonesTest("allZones" .. character .. "Start", character, function(finish)
		local player = fixtures.player()
		assert(player.name == character, "playing as " .. player.name)
		assert(player.health.health == 6 and player.health.maxHealth == 6,
			"health " .. player.health.health .. "/" .. player.health.maxHealth)
		assert(itemNames() == items, "items " .. itemNames())
		finish()
	end)
end

-- Health, gold and items carry from a zone's boss level into the next zone.
allZonesTest("allZonesCarryIntoNextZone", "Cadence", function(finish)
	local player = fixtures.player()
	player.health.health = 3
	player.goldCounter.amount = 77
	Inventory.grant("Torch1", player)
	GameSession.goToLevel(4)
	whenOnLevel(4, function()
		assert(CurrentLevel.isBoss(), "level 4 is a boss level")
		GameSession.goToLevel(5)
		whenOnLevel(5, function()
			player = fixtures.player()
			assert(CurrentLevel.getZone() == 2 and CurrentLevel.getFloor() == 1, "on " .. CurrentLevel.getName())
			assert(player.health.health == 3, "health " .. player.health.health)
			assert(player.goldCounter.amount == 77, "gold " .. player.goldCounter.amount)
			assert(itemNames() == "Bomb,ShovelBasic,Torch1,WeaponDagger", "items " .. itemNames())
			finish()
		end)
	end)
end)
