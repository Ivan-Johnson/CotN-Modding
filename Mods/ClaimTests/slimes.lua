local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence in no-beat mode on an open floor, spawning slimes
-- by hand at offsets from the player, who starts at (0,0) with 12 health;
-- "up" is toward negative y. Slimes in different quadrants never meet.

local function scene(name, setup, actions, checks)
	fixtures.scene({ name = name, setup = setup, actions = actions, checks = checks })
end

local assertAt = fixtures.assertAt
local health = fixtures.health
local idles = fixtures.repeated

local function assertGone(entity, what)
	assert(not Entities.entityExists(entity.id), what .. ": expected the " .. entity.name .. " to be dead")
end

-- A Slime never moves or attacks, even with the player next to it, and one
-- dagger hit kills it.
scene("slimeGreenNeverActs", function()
	return {
		right = fixtures.spawn("Slime", 1, 0),
		below = fixtures.spawn("Slime", 0, 1),
		left = fixtures.spawn("Slime", -1, 0),
		above = fixtures.spawn("Slime", 0, -1),
	}
end, { "idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle", "right" }, {
	[8] = function(slimes)
		assertAt(slimes.right, 1, 0, "right")
		assertAt(slimes.below, 0, 1, "below")
		assertAt(slimes.left, -1, 0, "left")
		assertAt(slimes.above, 0, -1, "above")
		assert(health() == 12, "a Slime never hits")
	end,
	[9] = function(slimes)
		assertGone(slimes.right, "one dagger hit")
	end,
})

-- A Slime2 moves down, rests, moves up, rests; a Slime3 steps right, down,
-- left, up, one step every beat.
scene("slimeLoops", function()
	return {
		blue = fixtures.spawn("Slime2", 3, 3),
		orange = fixtures.spawn("Slime3", 3, -4),
	}
end, idles("idle", 5), {
	[1] = function(slimes)
		assertAt(slimes.blue, 3, 4, "Slime2 moves down on the first beat")
		assertAt(slimes.orange, 4, -4, "Slime3 steps right")
	end,
	[2] = function(slimes)
		assertAt(slimes.blue, 3, 4, "Slime2 rests")
		assertAt(slimes.orange, 4, -3, "Slime3 steps down")
	end,
	[3] = function(slimes)
		assertAt(slimes.blue, 3, 3, "Slime2 moves up")
		assertAt(slimes.orange, 3, -3, "Slime3 steps left")
	end,
	[4] = function(slimes)
		assertAt(slimes.blue, 3, 3, "Slime2 rests")
		assertAt(slimes.orange, 3, -4, "Slime3 steps up, back where it started")
	end,
	[5] = function(slimes)
		assertAt(slimes.blue, 3, 4, "Slime2 moves down again")
		assertAt(slimes.orange, 4, -4, "Slime3 starts the loop again")
	end,
})

-- One dagger hit kills a Slime3. A Slime2 takes two, and a hit never knocks
-- it back: boxed in by walls it stays put, and free it carries on bouncing.
scene("slimeHitsToKill", function()
	Tile.setType(1, -1, "StoneWall")
	Tile.setType(1, 1, "StoneWall")
	return {
		blue = fixtures.spawn("Slime2", 1, 0),
		orange = fixtures.spawn("Slime3", -1, 0),
	}
end, { "left", "right", "idle", "right" }, {
	[1] = function(slimes)
		assertGone(slimes.orange, "one dagger hit")
	end,
	[2] = function(slimes)
		assertAt(slimes.blue, 1, 0, "not knocked back")
		assert(slimes.blue.health.health == 1, "a dagger hit takes 1 of the Slime2's 2 health")
	end,
	[4] = function(slimes)
		assertGone(slimes.blue, "second dagger hit")
	end,
})

scene("slimeBlueKeepsBouncingWhenHit", function()
	return fixtures.spawn("Slime2", 1, -1)
end, { "idle", "idle", "right", "idle" }, {
	[2] = function(slime)
		assertAt(slime, 1, 0, "bounced down beside the player")
	end,
	[3] = function(slime)
		assert(slime.health.health == 1, "hit")
		assertAt(slime, 1, -1, "it bounces up as usual on the beat it is hit")
	end,
})

-- A slime that appears with a wall on its loop starts at the first move of
-- its pattern whose whole loop is clear of walls; it checks every tile of the
-- loop, not only the next one.
scene("slimeStartAvoidsWalls", function()
	Tile.setType(-4, 4, "StoneWall")
	Tile.setType(4, -4, "StoneWall")
	Tile.setType(-4, -3, "StoneWall")
	Tile.setType(4, 5, "StoneWall")
	return {
		blueWallBelow = fixtures.spawn("Slime2", -4, 3),
		wallRight = fixtures.spawn("Slime3", 3, -4),
		wallDiagonal = fixtures.spawn("Slime3", -5, -4),
		wallBelow = fixtures.spawn("Slime3", 4, 4),
	}
end, idles("idle", 4), {
	[1] = function(slimes)
		assertAt(slimes.blueWallBelow, -4, 2, "Slime2 with a wall below moves up first")
		assertAt(slimes.wallRight, 3, -3, "Slime3 with a wall to its right steps down first")
		assertAt(slimes.wallDiagonal, -5, -3, "Slime3 with a wall down and right steps down first")
		assertAt(slimes.wallBelow, 3, 4, "Slime3 with a wall below steps left first")
	end,
	[2] = function(slimes)
		assertAt(slimes.blueWallBelow, -4, 2, "rests")
		assertAt(slimes.wallRight, 2, -3, "left")
		assertAt(slimes.wallDiagonal, -6, -3, "left")
		assertAt(slimes.wallBelow, 3, 3, "up")
	end,
	[4] = function(slimes)
		assertAt(slimes.blueWallBelow, -4, 3, "back home")
		assertAt(slimes.wallRight, 3, -4, "back home")
		assertAt(slimes.wallDiagonal, -5, -4, "back home")
		assertAt(slimes.wallBelow, 4, 4, "back home")
	end,
})

-- A slime with no clear loop never moves.
scene("slimeBoxedInNeverMoves", function()
	Tile.setType(5, 4, "StoneWall")
	Tile.setType(4, 5, "StoneWall")
	Tile.setType(3, 4, "StoneWall")
	Tile.setType(4, 3, "StoneWall")
	Tile.setType(-4, 2, "StoneWall")
	Tile.setType(-4, 4, "StoneWall")
	return {
		orange = fixtures.spawn("Slime3", 4, 4),
		blue = fixtures.spawn("Slime2", -4, 3),
	}
end, idles("idle", 4), {
	[4] = function(slimes)
		assertAt(slimes.orange, 4, 4, "Slime3")
		assertAt(slimes.blue, -4, 3, "Slime2")
	end,
})

-- The loop is picked when the slime appears: a wall built on it afterwards
-- stops the slime for good in front of the wall.
scene("slimeLaterWallStopsIt", function()
	local slimes = {
		orange = fixtures.spawn("Slime3", 4, 4),
		blue = fixtures.spawn("Slime2", -4, 3),
	}
	Tile.setType(5, 5, "StoneWall")
	Tile.setType(-4, 4, "StoneWall")
	return slimes
end, idles("idle", 6), {
	[1] = function(slimes)
		assertAt(slimes.orange, 5, 4, "Slime3 still steps right first")
	end,
	[6] = function(slimes)
		assertAt(slimes.orange, 5, 4, "Slime3 stopped above the wall")
		assertAt(slimes.blue, -4, 3, "Slime2 stopped above the wall")
	end,
})

-- An enemy on a slime's next tile makes it wait, and it carries on once the
-- tile is free.
scene("slimeWaitsForAnEnemy", function()
	return {
		orange = fixtures.spawn("Slime3", 4, 4),
		blocker = fixtures.spawn("Slime", 5, 4),
	}
end, idles("idle", 4), {
	[2] = function(slimes)
		assertAt(slimes.orange, 4, 4, "waits behind the enemy")
		Object.delete(slimes.blocker)
	end,
	[3] = function(slimes)
		assertAt(slimes.orange, 5, 4, "carries on with the step it was waiting to take")
	end,
	[4] = function(slimes)
		assertAt(slimes.orange, 5, 5, "and the rest of its loop")
	end,
})

-- A Slime2 whose next move is onto the player hits for 2 on its beats instead,
-- and moves on once the player leaves.
scene("slimeBlueHitsThePlayerInItsPath", function()
	return fixtures.spawn("Slime2", 0, -1)
end, { "idle", "idle", "idle", "idle", "idle", "left", "idle" }, {
	[3] = function(slime)
		assertAt(slime, 0, -1, "stays put")
		assert(health() == 10, "hits for 2")
	end,
	[4] = function()
		assert(health() == 10, "rests")
	end,
	[5] = function()
		assert(health() == 8, "hits again two beats later")
	end,
	[7] = function(slime)
		assertAt(slime, 0, 0, "moves down once the player has left")
		assert(health() == 8, "no more hits")
	end,
})

-- A Slime3 whose next step is onto the player hits for 1, every second beat
-- although it moves every beat.
scene("slimeOrangeHitsThePlayerInItsPath", function()
	return fixtures.spawn("Slime3", -1, 0)
end, idles("idle", 6), {
	[2] = function(slime)
		assertAt(slime, -1, 0, "stays put")
		assert(health() == 11, "hits for 1")
	end,
	[3] = function()
		assert(health() == 11, "no hit on the next beat")
	end,
	[4] = function()
		assert(health() == 10, "hits every second beat")
	end,
	[6] = function()
		assert(health() == 9, "hits every second beat")
	end,
})

-- Next to the player but with the player off its loop, a slime never hits.
scene("slimeOffItsLoopIsSafe", function()
	return {
		blue = fixtures.spawn("Slime2", 1, 0),
		orange = fixtures.spawn("Slime3", -2, -1),
	}
end, idles("idle", 8), {
	[8] = function()
		assert(health() == 12, "no hits")
	end,
})

-- The slimes a level starts with follow the same loops. Other enemies are
-- removed so they cannot get in the way, and so is a slime in water, which is
-- slowed; level 1 of the fixed seed has Slimes
-- and Slime2s, level 3 Slime3s.
local function naturalSlimes(name, level, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			local function run()
				local slimes, doomed = {}, {}
				for entity in Entities.entitiesWithComponents({ "ai" }) do
					local onFloor = fixtures.tileName(entity.position.x, entity.position.y) == "Floor"
					if checks[entity.name] and onFloor then
						table.insert(slimes, { entity = entity, x = entity.position.x, y = entity.position.y })
					else
						table.insert(doomed, entity.id)
					end
				end
				for _, id in ipairs(doomed) do
					Object.delete(Entities.getEntityByID(id))
				end
				local checked = {}
				testsApi.play(idles("idle", 3), function(index)
					for _, slime in ipairs(slimes) do
						local offset = checks[slime.entity.name][index]
						if offset then
							checked[slime.entity.name] = true
							assertAt(slime.entity, slime.x + offset[1], slime.y + offset[2], "natural " .. slime.entity.name)
						end
					end
				end, function()
					for typeName in pairs(checks) do
						assert(checked[typeName], "level " .. level .. " has no " .. typeName .. " to check")
					end
					finish()
				end)
			end
			if level == 1 then
				run()
				return
			end
			-- A level change from the first level takes effect late, so go
			-- through level 2 and poll.
			GameSession.goToLevel(2)
			testsApi.afterTicks(400, function()
				GameSession.goToLevel(level)
				local function whenLoaded()
					if CurrentLevel.getNumber() ~= level then
						testsApi.afterTicks(10, whenLoaded)
						return
					end
					testsApi.afterTicks(300, run)
				end
				whenLoaded()
			end)
		end,
	})
end

naturalSlimes("slimeNaturalGreenAndBlue", 1, {
	Slime = { { 0, 0 }, { 0, 0 }, { 0, 0 } },
	Slime2 = { { 0, 1 }, { 0, 1 }, { 0, 0 } },
})

-- Only the first two steps: one Slime3's third step lands on a bounce trap.
naturalSlimes("slimeNaturalOrange", 3, {
	Slime3 = { { 1, 0 }, { 1, 1 } },
})
