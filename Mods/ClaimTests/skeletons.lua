local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Move = require "necro.game.system.Move"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence with her dagger in no-beat mode on an open floor,
-- spawning skeletons by hand at offsets from the player, who starts at (0,0).
-- The character is pinned because the game otherwise keeps whichever
-- character the previous test played.

local assertAt = fixtures.assertAt
local health = fixtures.health

-- fixtures.scene, with the character pinned.
local function scene(name, setup, actions, checks)
	testsApi.registerTest({
		name = name,
		character = "Cadence",
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(10)
			local state = setup()
			testsApi.play(actions, function(index)
				if checks[index] then
					checks[index](state)
				end
			end, finish)
		end,
	})
end

local function assertIs(entity, name, hp, what)
	assert(Entities.entityExists(entity.id), what .. ": expected " .. name .. ", but it is dead")
	assert(entity.name == name, what .. ": expected " .. name .. ", got " .. entity.name)
	assert(entity.health.health == hp, string.format("%s: expected %d HP, got %d", what, hp, entity.health.health))
end

local function assertDead(entity, what)
	assert(not Entities.entityExists(entity.id), what .. ": expected it to be dead")
end

-- A list of the actions in order, each repeated as often as the number after
-- it, e.g. sequence("right", 2, "idle", 3).
local function sequence(...)
	local list = {}
	local args = { ... }
	for index = 1, #args, 2 do
		for _ = 1, args[index + 1] do
			table.insert(list, args[index])
		end
	end
	return list
end

-- Each type has the table's HP and damage, and chases like a Skeleton: one
-- next to the player hits on beats 3 and 5, and one in plain sight three
-- tiles away steps in on beats 1 and 3. Each is a sleeper: one four tiles
-- away never moves. The full rules for when sleepers wake are enemies.lua's
-- to back.
local STATS = {
	Skeleton = { hp = 1, damage = 1 },
	Skeleton2 = { hp = 2, damage = 3 },
	Skeleton3 = { hp = 3, damage = 4 },
}
for type, stats in pairs(STATS) do
	scene("skeletonStats" .. type, function()
		return {
			near = fixtures.spawn(type, 1, 0),
			far = fixtures.spawn(type, -3, 0),
			asleep = fixtures.spawn(type, 0, -4),
		}
	end, sequence("idle", 5), {
		[1] = function(things)
			assertIs(things.near, type, stats.hp, "full health")
			assertAt(things.far, -2, 0, "first step")
		end,
		[2] = function(things)
			assertAt(things.far, -2, 0, "rests a beat")
			assert(health() == 12, "no hit yet")
		end,
		[3] = function(things)
			assertAt(things.far, -1, 0, "second step")
			assert(health() == 12 - stats.damage, "one hit")
		end,
		[5] = function(things)
			assert(health() == 12 - 2 * stats.damage, "a second hit two beats later")
			assertAt(things.asleep, 0, -4, "four tiles away sleeps")
		end,
	})
end

scene("skeletonDaggerKillsSkeleton", function()
	return fixtures.spawn("Skeleton", 1, 0)
end, { "right" }, {
	[1] = function(skeleton)
		assertDead(skeleton, "one dagger hit")
	end,
})

-- The hit that leaves 1 HP turns a Skeleton2 or Skeleton3 headless and shoves
-- it a tile; it then runs a tile every beat in the direction of the hit until
-- something stops it, then stands there. It never hits the player, who walks
-- up and waits beside it, and the next hit kills it.
local function chargeScene(name, type, hits, dir, sign, blocker)
	local checks = {
		[hits] = function(skeleton)
			assertIs(skeleton, type .. "Headless", 1, "headless after " .. hits .. " hits")
			assertAt(skeleton, 2 * sign, 0, "shoved one tile")
		end,
		[hits + 1] = function(skeleton)
			assertAt(skeleton, 3 * sign, 0, "runs a tile")
		end,
		[hits + 2] = function(skeleton)
			assertAt(skeleton, 4 * sign, 0, "runs a tile every beat")
		end,
		[hits + 6] = function(skeleton)
			assertAt(skeleton, 4 * sign, 0, "stopped in front of the blocker")
		end,
		[hits + 13] = function(skeleton)
			assert(fixtures.player().position.x == 3 * sign, "the player stands beside it")
			assertAt(skeleton, 4 * sign, 0, "stays put")
			assert(health() == 12, "it never hits")
		end,
		[hits + 14] = function(skeleton)
			assertDead(skeleton, "one more hit")
		end,
	}
	if hits == 2 then
		checks[1] = function(skeleton)
			assertIs(skeleton, type, 2, "the first hit only takes 1 HP")
			assertAt(skeleton, sign, 0, "not shoved")
		end
	end
	scene(name, function()
		blocker(5 * sign)
		return fixtures.spawn(type, sign, 0)
	end, sequence(dir, hits, "idle", 6, dir, 3, "idle", 4, dir, 1), checks)
end

chargeScene("skeletonHeadlessChargesToAWall", "Skeleton2", 1, "right", 1, function(x)
	fixtures.wallColumn(x, -2, 2)
end)
chargeScene("skeletonHeadlessChargesToAnEnemy", "Skeleton3", 2, "left", -1, function(x)
	fixtures.spawn("Slime", x, 0)
end)

-- With a wall (right) or an enemy (left) right behind it, the headless
-- skeleton is not shoved and does not run, and the next hit kills it.
scene("skeletonHeadlessBlockedBehind", function()
	fixtures.wallColumn(2, 0, 0)
	fixtures.spawn("Slime", -2, 0)
	return {
		walled = fixtures.spawn("Skeleton2", 1, 0),
		backed = fixtures.spawn("Skeleton3", -1, 0),
	}
end, sequence("right", 1, "left", 2, "idle", 4, "right", 1, "left", 1), {
	[3] = function(things)
		assertIs(things.walled, "Skeleton2Headless", 1, "headless")
		assertIs(things.backed, "Skeleton3Headless", 1, "headless")
	end,
	[7] = function(things)
		assertAt(things.walled, 1, 0, "not shoved into the wall")
		assertAt(things.backed, -1, 0, "not shoved into the enemy")
		assert(health() == 12, "neither hits")
	end,
	[8] = function(things)
		assertDead(things.walled, "the next hit")
	end,
	[9] = function(things)
		assertDead(things.backed, "the next hit")
	end,
})

-- A Skeleton2 or Skeleton3 that comes with level 3 loses its head and
-- charges the same way, once moved next to the player.
for type, hits in pairs({ Skeleton2 = 1, Skeleton3 = 2 }) do
	testsApi.registerTest({
		name = "skeletonNaturalHeadlessCharge" .. type,
		character = "Cadence",
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			-- A level change from the first level takes effect late, so go
			-- through level 2 and poll.
			GameSession.goToLevel(2)
			testsApi.afterTicks(400, function()
				GameSession.goToLevel(3)
				local function whenLoaded()
					if CurrentLevel.getNumber() ~= 3 then
						testsApi.afterTicks(10, whenLoaded)
						return
					end
					testsApi.afterTicks(300, function()
						fixtures.openArena(8, type)
						local skeleton
						for entity in Entities.entitiesWithComponents({ "ai" }) do
							skeleton = entity
						end
						assert(skeleton and skeleton.name == type, "level 3 has a " .. type)
						local x, y = fixtures.player().position.x, fixtures.player().position.y
						Move.absolute(skeleton, x + 1, y, Move.Type.TELEPORT)
						testsApi.play(sequence("right", hits, "idle", 3), function(index)
							if index == hits then
								assertIs(skeleton, type .. "Headless", 1, "headless")
								assertAt(skeleton, x + 2, y, "shoved")
							elseif index == hits + 3 then
								assertAt(skeleton, x + 5, y, "ran a tile every beat")
							end
						end, finish)
					end)
				end
				whenLoaded()
			end)
		end,
	})
end
