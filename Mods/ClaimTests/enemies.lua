local Entities = require "system.game.Entities"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on HelloWorldTests; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end
local fixtures = require "HelloWorldTests.fixtures"

-- Each test plays Cadence in no-beat mode on
-- an open floor, spawning enemies by hand at offsets from the player, who
-- starts at (0,0); "up" is toward negative y. Enemies spawned in different
-- quadrants do not interfere within the beats a test watches.

local function scene(name, radius, setup, actions, checks)
	fixtures.scene({ name = name, radius = radius, setup = setup, actions = actions, checks = checks })
end

local wallColumn = fixtures.wallColumn
local assertAt = fixtures.assertAt
local health = fixtures.health

-- Remembers where each entity was, so a check can say whether it has moved.
local function track(things)
	local last = {}
	for key, entity in pairs(things) do
		last[key] = { x = entity.position.x, y = entity.position.y }
	end
	return function(key, entity)
		local before = last[key]
		local moved = before.x ~= entity.position.x or before.y ~= entity.position.y
		last[key] = { x = entity.position.x, y = entity.position.y }
		return moved
	end
end

-- A speed-2 enemy acts on the first beat after it appears and on every second
-- beat after that, and an attack takes the slot of a move: a Skeleton that
-- appears next to the player after the second beat hits on beats 3, 5 and 7.
-- (The player cannot be hurt during the first beat of a level.)
scene("enemySpeedTwoHitsEverySecondBeat", 10, function()
	return {}
end, fixtures.repeated("idle", 7), {
	[2] = function()
		fixtures.spawn("Skeleton", 1, 0)
	end,
	[3] = function()
		assert(health() == 11, "hit on the first beat after it appears")
	end,
	[4] = function()
		assert(health() == 11, "no hit on the second beat")
	end,
	[5] = function()
		assert(health() == 10, "hit two beats after the first")
	end,
	[6] = function()
		assert(health() == 10, "no hit on the next beat")
	end,
	[7] = function()
		assert(health() == 9, "hit two beats after the second")
	end,
})

-- Nothing can hurt the player on the first beat of a level: a Minotaur next to
-- the player at the start lands its first hit, which would come on beat 1,
-- on beat 4 instead (a Minotaur hits once every three beats).
scene("enemyPlayerIsUnhurtOnTheFirstBeat", 10, function()
	return fixtures.spawn("Minotaur", 1, 0)
end, fixtures.repeated("idle", 4), {
	[1] = function()
		assert(health() == 12, "no damage on beat 1")
	end,
	[3] = function()
		assert(health() == 12, "no damage on beat 3")
	end,
	[4] = function()
		assert(health() == 8, "the Minotaur's next hit lands")
	end,
})

-- A speed-1 Slime3 steps every beat, around a four-tile loop.
scene("enemySpeedOneStepsEveryBeat", 10, function()
	return fixtures.spawn("Slime3", 6, 6)
end, fixtures.repeated("idle", 4), {
	[1] = function(slime)
		assertAt(slime, 7, 6, "first beat")
	end,
	[2] = function(slime)
		assertAt(slime, 7, 7, "second beat")
	end,
	[3] = function(slime)
		assertAt(slime, 6, 7, "third beat")
	end,
	[4] = function(slime)
		assertAt(slime, 6, 6, "fourth beat")
	end,
})

-- The beat the enemy appears on does not matter: a Zombie that appears after
-- the first beat still moves on the next beat, then every second beat.
local lateZombie = {}
scene("enemySpeedTwoStartsOnTheNextBeat", 10, function()
	return lateZombie
end, fixtures.repeated("idle", 4), {
	[1] = function()
		lateZombie.zombie = fixtures.spawn("Zombie", 6, 6)
		lateZombie.moved = track(lateZombie)
	end,
	[2] = function()
		assert(lateZombie.moved("zombie", lateZombie.zombie), "moves on the beat after it appears")
	end,
	[3] = function()
		assert(not lateZombie.moved("zombie", lateZombie.zombie), "rests on the next beat")
	end,
	[4] = function()
		assert(lateZombie.moved("zombie", lateZombie.zombie), "moves again two beats later")
	end,
})

-- Slimes and Zombies act from the first beats however far away they are.
scene("enemyAlwaysActiveTypesActFromFarAway", 16, function()
	local things = {
		slime2 = fixtures.spawn("Slime2", 14, 0),
		slime3 = fixtures.spawn("Slime3", 0, 14),
		zombie = fixtures.spawn("Zombie", -14, 0),
	}
	things.moved = track(things)
	return things
end, fixtures.repeated("idle", 1), {
	[1] = function(things)
		assert(things.moved("slime2", things.slime2), "Slime2 moved")
		assert(things.moved("slime3", things.slime3), "Slime3 moved")
		assert(things.moved("zombie", things.zombie), "Zombie moved")
	end,
})

-- Skeletons sleep until the player is within 3 tiles in a straight line:
-- (3,0) and (0,3) wake, as does (-2,-2), but (-3,-1) and (0,-4) do not.
scene("enemySkeletonWakesWithinThreeTiles", 12, function()
	return {
		east = fixtures.spawn("Skeleton", 3, 0),
		south = fixtures.spawn("Skeleton", 0, 3),
		northWest = fixtures.spawn("Skeleton", -2, -2),
		tooFarWest = fixtures.spawn("Skeleton", -3, 1),
		tooFarNorth = fixtures.spawn("Skeleton", 0, -4),
	}
end, fixtures.repeated("idle", 4), {
	[4] = function(things)
		assertAt(things.east, 1, 0, "woke and closed in")
		assertAt(things.south, 0, 1, "woke and closed in")
		assertAt(things.northWest, 0, -2, "woke and closed in")
		assertAt(things.tooFarWest, -3, 1, "3.2 tiles away stays asleep")
		assertAt(things.tooFarNorth, 0, -4, "4 tiles away stays asleep")
	end,
})

-- Monkeys wake the same way; so do bats, which then wander at random.
scene("enemyMonkeysAndBatsWakeWithinThreeTiles", 12, function()
	local things = {
		monkey = fixtures.spawn("Monkey", 3, 0),
		sleepingMonkey = fixtures.spawn("Monkey", 0, -4),
		bat = fixtures.spawn("Bat2", -2, 2),
		sleepingBat = fixtures.spawn("Bat2", -4, -2),
	}
	things.moved = track(things)
	return things
end, fixtures.repeated("idle", 4), {
	[1] = function(things)
		assertAt(things.monkey, 2, 0, "first step")
		assert(things.moved("bat", things.bat), "the bat 2.8 tiles away wakes and wanders")
	end,
	[2] = function(things)
		assertAt(things.monkey, 1, 0, "second step")
		assert(not things.moved("sleepingMonkey", things.sleepingMonkey), "a monkey 4 tiles away sleeps")
		assert(not things.moved("sleepingBat", things.sleepingBat), "a bat 4.5 tiles away sleeps")
	end,
	[4] = function(things)
		assert(not things.moved("sleepingMonkey", things.sleepingMonkey), "still asleep")
		assert(not things.moved("sleepingBat", things.sleepingBat), "still asleep")
	end,
})

-- Walls do not stop an enemy waking, and an awake enemy keeps chasing a player
-- who walks away. The Skeleton two tiles diagonally behind a wall wakes and
-- slides along it; the one 3.2 tiles away does not.
scene("enemyWakesThroughWalls", 12, function()
	wallColumn(1, -10, 10)
	return {
		near = fixtures.spawn("Skeleton", 2, 2),
		far = fixtures.spawn("Skeleton", 3, -1),
	}
end, fixtures.repeated("idle", 4), {
	[4] = function(things)
		assertAt(things.near, 2, 0, "woke behind the wall and slid along it")
		assertAt(things.far, 3, -1, "stays asleep behind the wall")
	end,
})

scene("enemyStaysAwakeOnceWoken", 12, function()
	local things = {
		skeleton = fixtures.spawn("Skeleton", 2, 0),
		bat = fixtures.spawn("Bat2", 1, 2),
	}
	things.moved = track(things)
	return things
end, { "left", "left", "left", "left", "left", "left" }, {
	[4] = function(things)
		things.moved("bat", things.bat)
	end,
	[5] = function(things)
		things.wandered = things.moved("bat", things.bat)
	end,
	[6] = function(things)
		-- A bat's step can be blocked by another enemy, so allow either beat.
		local wandered = things.moved("bat", things.bat) or things.wandered
		assert(wandered, "the bat still wanders 5 and 6 tiles from the player")
		assertAt(things.skeleton, -1, 0, "still following 5 tiles behind the player")
	end,
})

-- Minotaurs wake within 7 tiles and Dragon2s within 10, even through a wall;
-- a Dragon has no such radius and sleeps behind a wall at any distance.
scene("enemyMinibossWakeRadiusThroughWalls", 14, function()
	wallColumn(1, -12, 12)
	return {
		minotaur = fixtures.spawn("Minotaur", 6, 3),
		sleepingMinotaur2 = fixtures.spawn("Minotaur2", 6, -4),
		dragon2 = fixtures.spawn("Dragon2", 8, -5),
		sleepingDragon = fixtures.spawn("Dragon", 3, -3),
		sleepingDragon2 = fixtures.spawn("Dragon2", 9, 5),
	}
end, fixtures.repeated("idle", 3), {
	[3] = function(things)
		assert(things.minotaur.position.x < 6, "a Minotaur 6.7 tiles away woke")
		assertAt(things.sleepingMinotaur2, 6, -4, "a Minotaur2 7.2 tiles away sleeps")
		assert(things.dragon2.position.x < 8, "a Dragon2 9.4 tiles away woke")
		assertAt(things.sleepingDragon, 3, -3, "a Dragon behind a wall sleeps")
		assertAt(things.sleepingDragon2, 9, 5, "a Dragon2 10.3 tiles away sleeps")
	end,
})

-- With a clear line to the player, Minotaurs and Dragons wake from across the
-- room.
scene("enemyMinibossWakesOnSightFromFarAway", 16, function()
	return {
		minotaur = fixtures.spawn("Minotaur", 14, 0),
		dragon = fixtures.spawn("Dragon", -14, 0),
		dragon2 = fixtures.spawn("Dragon2", 0, 14),
	}
end, fixtures.repeated("idle", 4), {
	[4] = function(things)
		assert(things.minotaur.position.x < 14, "the Minotaur charged")
		assert(things.dragon.position.x > -14, "the Dragon approached")
		assert(things.dragon2.position.y < 14, "the Dragon2 approached")
	end,
})

-- Seekers step horizontally first, even when the player is farther away
-- vertically, and Minotaurs do the same.
scene("enemySeekersStepHorizontallyFirst", 10, function()
	return {
		diagonal = fixtures.spawn("Skeleton", 2, 2),
		longWay = fixtures.spawn("Skeleton", -1, -2),
		monkey = fixtures.spawn("Monkey", 2, -2),
		minotaur = fixtures.spawn("Minotaur", -4, 3),
	}
end, fixtures.repeated("idle", 1), {
	[1] = function(things)
		assertAt(things.diagonal, 1, 2, "diagonal")
		assertAt(things.longWay, 0, -2, "farther vertically")
		assertAt(things.monkey, 1, -2, "monkey")
		assertAt(things.minotaur, -3, 3, "minotaur")
	end,
})

-- When a wall or another enemy blocks the horizontal step, a seeker steps
-- vertically instead.
scene("enemySeekersStepVerticallyWhenBlocked", 10, function()
	Tile.setType(1, 2, "StoneWall")
	fixtures.spawn("Slime", -1, -1)
	return {
		wall = fixtures.spawn("Skeleton", 2, 2),
		enemy = fixtures.spawn("Skeleton", -2, -1),
	}
end, fixtures.repeated("idle", 1), {
	[1] = function(things)
		assertAt(things.wall, 2, 1, "wall in the way")
		assertAt(things.enemy, -2, 0, "enemy in the way")
	end,
})

-- A seeker never walks around an obstacle: with a wall or an enemy straight
-- between it and the player it stays where it is.
scene("enemySeekersDoNotWalkAroundObstacles", 10, function()
	Tile.setType(1, 0, "StoneWall")
	fixtures.spawn("Slime", -1, 0)
	return {
		behindWall = fixtures.spawn("Skeleton", 2, 0),
		behindEnemy = fixtures.spawn("Skeleton", -2, 0),
	}
end, fixtures.repeated("idle", 6), {
	[6] = function(things)
		assertAt(things.behindWall, 2, 0, "behind a wall")
		assertAt(things.behindEnemy, -2, 0, "behind an enemy")
	end,
})

-- A Minotaur with a wall straight between it and the player breaks through a
-- stone or dirt wall, which costs it one extra beat.
scene("enemyMinotaurBreaksWalls", 10, function()
	Tile.setType(3, 0, "StoneWall")
	Tile.setType(-3, 0, "DirtWall")
	return {
		stone = fixtures.spawn("Minotaur2", 5, 0),
		dirt = fixtures.spawn("Minotaur", -5, 0),
	}
end, fixtures.repeated("idle", 3), {
	[1] = function(things)
		assertAt(things.stone, 4, 0, "up to the wall")
		assertAt(things.dirt, -4, 0, "up to the wall")
	end,
	[2] = function(things)
		assertAt(things.stone, 4, 0, "breaking the wall")
		assertAt(things.dirt, -4, 0, "breaking the wall")
	end,
	[3] = function(things)
		assertAt(things.stone, 3, 0, "through the stone wall")
		assertAt(things.dirt, -3, 0, "through the dirt wall")
		assert(Tile.getInfo(3, 0).isFloor and Tile.getInfo(-3, 0).isFloor, "the walls are gone")
	end,
})

-- Skeletons move the same way every time; a Zombie's first direction and a
-- bat's steps vary between identical spawns.
local function distinctOutcomes(typeName, x, y, beats, trials, onDone)
	local outcomes = {}
	local trial = 0
	local function nextTrial()
		trial = trial + 1
		if trial > trials then
			onDone(outcomes)
			return
		end
		fixtures.openArena(10)
		local enemy = fixtures.spawn(typeName, x, y)
		testsApi.play(fixtures.repeated("idle", beats), nil, function()
			outcomes[enemy.position.x .. "," .. enemy.position.y] = true
			nextTrial()
		end)
	end
	nextTrial()
end

local function countKeys(set)
	local count = 0
	for _ in pairs(set) do
		count = count + 1
	end
	return count
end

testsApi.registerTest({
	name = "enemyRandomAndDeterministicMovers",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		distinctOutcomes("Skeleton", 2, 2, 4, 4, function(skeletons)
			assert(countKeys(skeletons) == 1, "a Skeleton ends in the same place every time")
			distinctOutcomes("Zombie", 6, 6, 2, 8, function(zombies)
				assert(countKeys(zombies) > 1, "a Zombie starts in a random direction")
				distinctOutcomes("Bat3", 2, 2, 3, 8, function(bats)
					assert(countKeys(bats) > 1, "a bat wanders at random")
					finish()
				end)
			end)
		end)
	end,
})

-- Enemies that come with the level follow the same rules: on the first level
-- only the Slime2s, which always act, move while the player idles.
testsApi.registerTest({
	name = "enemyNaturalEnemiesFollowTheRules",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		local watched = {}
		for entity in Entities.entitiesWithComponents({ "ai" }) do
			watched[entity.id] = { name = entity.name, x = entity.position.x, y = entity.position.y }
		end
		local movers = {}
		testsApi.play(fixtures.repeated("idle", 6), function()
			for id, before in pairs(watched) do
				if Entities.entityExists(id) then
					local entity = Entities.getEntityByID(id)
					if entity.position.x ~= before.x or entity.position.y ~= before.y then
						movers[before.name] = true
					end
				end
			end
		end, function()
			assert(movers.Slime2, "the level's Slime2s move")
			for name in pairs(movers) do
				assert(
					name == "Slime2" or name == "Slime3" or name == "Zombie",
					name .. " moved although the player was far away"
				)
			end
			finish()
		end)
	end,
})
