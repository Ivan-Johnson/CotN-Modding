local CurrentLevel = require "necro.game.level.CurrentLevel"
local Damage = require "necro.game.system.Damage"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local GrooveChain = require "necro.game.character.GrooveChain"
local Inventory = require "necro.game.item.Inventory"
local Marker = require "necro.game.tile.Marker"
local Move = require "necro.game.system.Move"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays a single-zone run as Cadence in no-beat mode. A level
-- change lands a second or more after the step that causes it, so tests poll
-- for it, and each ends on the level it changed to: a change still pending
-- would land in the next test.

local MINIBOSSES = {
	[1] = { BatMiniboss = true, Minotaur = true, Dragon = true },
	[2] = { BatMiniboss = true, Minotaur = true, Dragon = true },
	[3] = { Minotaur2 = true, Dragon2 = true },
}

local BOSSES = { KingConga = true, Deathmetal = true, King = true, Coralriff = true, Fortissimole = true }

local function stairs()
	local all = Marker.lookUpAll(Marker.Type.STAIRS)
	assert(#all == 1, "one staircase, found " .. #all)
	return all[1][1], all[1][2]
end

local function lockers()
	local found = {}
	for entity in Entities.entitiesWithComponents({ "stairLocker" }) do
		table.insert(found, entity)
	end
	return found
end

local function holds(name)
	for _, item in ipairs(Inventory.getItems(fixtures.player())) do
		if item.name == name then
			return true
		end
	end
	return false
end

local function kill(entity)
	Damage.inflict({
		victim = entity,
		attacker = fixtures.player(),
		damage = 99,
		type = Damage.Type.PHYSICAL + Damage.Flag.BYPASS_INVINCIBILITY,
	})
end

-- Calls after() once the level number is target, or fails after limit ticks.
local function awaitLevel(target, limit, after)
	local waited = 0
	local function poll()
		if CurrentLevel.getNumber() == target then
			-- The new level's entities settle a moment after the number changes.
			testsApi.afterTicks(300, after)
			return
		end
		assert(waited < limit, string.format("still on level %d after %d ticks", CurrentLevel.getNumber(), waited))
		waited = waited + 10
		testsApi.afterTicks(10, poll)
	end
	poll()
end

-- Holds for limit ticks, failing if the level changes meanwhile.
local function assertLevelStays(limit, after)
	local start = CurrentLevel.getNumber()
	local waited = 0
	local function poll()
		assert(CurrentLevel.getNumber() == start, "the level changed")
		if waited >= limit then
			after()
			return
		end
		waited = waited + 10
		testsApi.afterTicks(10, poll)
	end
	poll()
end

-- Jumps to level n. A jump requested from the level's load handler is
-- dropped, and one from the first level lands late, so the test waits on it.
local function goToLevel(n, after)
	testsApi.afterTicks(30, function()
		GameSession.goToLevel(n)
	end)
	awaitLevel(n, 5000, after)
end

-- Deletes every enemy but the miniboss, shuts the miniboss in at the start
-- tile, and stands the player on floor just left of the stairs. Returns the
-- miniboss and the stairs' tile.
local function besideStairs()
	local doomed = {}
	for entity in Entities.entitiesWithComponents({ "ai" }) do
		if not entity.stairLocker then
			table.insert(doomed, entity)
		end
	end
	for _, entity in ipairs(doomed) do
		Object.delete(entity)
	end
	local x, y = stairs()
	Tile.setType(x - 1, y, "Floor")
	Move.absolute(fixtures.player(), x - 1, y, Move.Type.TELEPORT)
	local miniboss = assert(lockers()[1], "a miniboss locks the stairs")
	for dy = -1, 1 do
		for dx = -1, 1 do
			Tile.setType(dx, dy, "LevelBorder")
		end
	end
	Tile.setType(0, 0, "Floor")
	Move.absolute(miniboss, 0, 0, Move.Type.TELEPORT)
	fixtures.assertAt(miniboss, 0, 0, "the miniboss moved off the stairs")
	return miniboss, x, y
end

local function scene(name, body)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			-- The player is placed on the start tile after the load handler.
			testsApi.afterTicks(60, function()
				body(finish)
			end)
		end,
	})
end

-- On 1-1 to 1-3 the stairs start locked, with one miniboss of the level's
-- kinds standing on them.
local function assertGuardedStairs()
	local level = CurrentLevel.getNumber()
	local x, y = stairs()
	assert(fixtures.tileName(x, y) == "LockedStairs", string.format("%d: the stairs start locked", level))
	local found = lockers()
	assert(#found == 1, string.format("%d: one miniboss, found %d", level, #found))
	local miniboss = found[1]
	assert(MINIBOSSES[level][miniboss.name], string.format("%d: unexpected miniboss %s", level, miniboss.name))
	fixtures.assertAt(miniboss, x, y, "the miniboss stands on the stairs")
end

scene("stairsStartLockedUnderAMiniboss", function(finish)
	assertGuardedStairs()
	goToLevel(2, function()
		assertGuardedStairs()
		goToLevel(3, function()
			assertGuardedStairs()
			finish()
		end)
	end)
end)

-- Standing on locked stairs does nothing; the miniboss's death unlocks them
-- and takes a player standing there down with no further input.
scene("stairsUnlockWhenTheMinibossDies", function(finish)
	local miniboss, x, y = besideStairs()
	testsApi.play({ "right" }, nil, function()
		fixtures.assertAt(fixtures.player(), x, y, "the player stands on the locked stairs")
		assertLevelStays(3000, function()
			kill(miniboss)
			testsApi.afterTicks(30, function()
				assert(fixtures.tileName(x, y) == "Stairs", "the miniboss's death unlocks the stairs")
				awaitLevel(2, 5000, finish)
			end)
		end)
	end)
end)

-- Health, gold, the coin multiplier's chain and items carry down the stairs.
scene("stairsKeepTheRunState", function(finish)
	local miniboss = besideStairs()
	kill(miniboss)
	local player = fixtures.player()
	player.health.health = 3
	player.grooveChain.killCount = 5
	player.grooveChain.multiplier = 3
	GrooveChain.update(player)
	Inventory.grant("RingGold", player)
	testsApi.afterTicks(30, function()
		testsApi.play({ "right" }, nil, function()
			-- After the step, which picks up the miniboss's gold.
			local gold = player.goldCounter.amount
			awaitLevel(2, 5000, function()
				player = fixtures.player()
				assert(player.health.health == 3, "health carries over: " .. player.health.health)
				assert(player.goldCounter.amount == gold, "gold carries over")
				assert(player.grooveChain.multiplier == 3 and player.grooveChain.killCount == 5, "the chain carries over")
				assert(holds("RingGold"), "items carry over")
				finish()
			end)
		end)
	end)
end)

-- A trapdoor drops the player to the next level, whatever the stairs' state,
-- keeping health and gold but ending the chain; from 1-3 it drops to the boss
-- level.
scene("trapdoorDropsToTheNextLevel", function(finish)
	fixtures.openArena(4, lockers()[1].name)
	fixtures.spawn("Trapdoor", 1, 0)
	local x, y = stairs()
	assert(fixtures.tileName(x, y) == "LockedStairs", "the stairs are still locked")
	local player = fixtures.player()
	player.health.health = 5
	player.goldCounter.amount = 50
	player.grooveChain.killCount = 5
	player.grooveChain.multiplier = 3
	GrooveChain.update(player)
	testsApi.play({ "right" }, nil, function()
		awaitLevel(2, 8000, function()
			player = fixtures.player()
			assert(player.health.health == 5, "health unchanged: " .. player.health.health)
			assert(player.goldCounter.amount == 50, "gold unchanged")
			assert(player.grooveChain.multiplier == 1, "the chain ends")
			finish()
		end)
	end)
end)

scene("levelTrapdoorDropsFromThreeToTheBoss", function(finish)
	goToLevel(2, function()
		goToLevel(3, function()
			local trapdoor
			for entity in Entities.entitiesWithComponents({ "trapDescend" }) do
				trapdoor = trapdoor or entity
			end
			assert(trapdoor, "1-3 has a trapdoor")
			local x, y = trapdoor.position.x, trapdoor.position.y
			local doomed = {}
			for entity in Entities.entitiesWithComponents({ "ai" }) do
				table.insert(doomed, entity)
			end
			for _, entity in ipairs(doomed) do
				Object.delete(entity)
			end
			Tile.setType(x - 1, y, "Floor")
			Move.absolute(fixtures.player(), x - 1, y, Move.Type.TELEPORT)
			testsApi.play({ "right" }, nil, function()
				awaitLevel(4, 8000, function()
					assert(CurrentLevel.isBoss(), "1-4 is the boss level")
					finish()
				end)
			end)
		end)
	end)
end)

-- 1-4: an empty start room with no trapdoor, whose doors open onto a row of
-- barriers; the first step onto that row walls the way back off. The boss is
-- one of the zone's five.
scene("bossRoomSealsBehindThePlayer", function(finish)
	goToLevel(2, function()
		goToLevel(4, function()
			assert(CurrentLevel.isBoss(), "1-4 is the boss level")
			local bossName
			for entity in Entities.entitiesWithComponents({ "boss" }) do
				bossName = bossName or entity.name
			end
			assert(BOSSES[bossName], "unexpected boss " .. tostring(bossName))
			for x = -1, 1 do
				assert(fixtures.tileName(x, -6):find("^Door"), "a door at y = -6")
			end
			local barriers = 0
			for entity in Entities.entitiesWithComponents({ "position" }) do
				if entity.name == "PreBossBarrier" and entity.position.y == -7 then
					barriers = barriers + 1
				end
			end
			assert(barriers == 5, "five barriers at y = -7, found " .. barriers)
			for entity in Entities.entitiesWithComponents({ "ai" }) do
				assert(entity.position.y < -6, "an enemy in the start room: " .. entity.name)
			end
			for _ in Entities.entitiesWithComponents({ "trapDescend" }) do
				error("1-4 has a trapdoor")
			end
			local player = fixtures.player()
			-- Five steps to the door, one to open it, one through it, one onto
			-- the barriers' row; then try to go back.
			testsApi.play(fixtures.repeated("up", 8), nil, function()
				fixtures.assertAt(player, 0, -7, "past the barriers")
				for x = -1, 1 do
					assert(fixtures.tileName(x, -6) == "BossWall", "the doorway is walled off")
				end
				testsApi.play({ "down" }, nil, function()
					fixtures.assertAt(player, 0, -7, "no way back")
					finish()
				end)
			end)
		end)
	end)
end)
