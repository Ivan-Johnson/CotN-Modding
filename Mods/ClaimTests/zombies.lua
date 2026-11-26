local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each scene plays Cadence in no-beat mode on an open floor, spawning Zombies
-- by hand; "up" is toward negative y. A Zombie's first direction is random,
-- so the scenes set it after the spawn. Direction codes: 1 right, 3 up,
-- 5 left, 7 down.

local RIGHT, UP, LEFT, DOWN = 1, 3, 5, 7
local STEP = { [RIGHT] = { 1, 0 }, [UP] = { 0, -1 }, [LEFT] = { -1, 0 }, [DOWN] = { 0, 1 } }

local assertAt = fixtures.assertAt
local health = fixtures.health

local function zombie(x, y, direction)
	local entity = fixtures.spawn("Zombie", x, y)
	entity.facingDirection.direction = direction
	return entity
end

local function assertFacing(entity, direction, what)
	local actual = entity.facingDirection.direction
	assert(actual == direction, string.format("%s: expected facing %d, got %d", what, direction, actual))
end

local function scene(name, setup, actions, checks)
	fixtures.scene({ name = name, radius = 12, setup = setup, actions = actions, checks = checks })
end

-- The first direction is one of the four straight ones, at random: 60 spawns
-- give every one of them and nothing else.
scene("zombieFirstDirectionIsRandom", function()
	local counts = {}
	for i = 0, 59 do
		local entity = fixtures.spawn("Zombie", -11 + (i % 12) * 2, -11 + math.floor(i / 12) * 2)
		local direction = entity.facingDirection.direction
		assert(STEP[direction], "a zombie faced " .. direction)
		counts[direction] = (counts[direction] or 0) + 1
	end
	for direction in pairs(STEP) do
		assert(counts[direction], "no zombie faced " .. direction)
	end
	return {}
end, { "idle" }, {})

-- A zombie steps every second beat. Blocked by a wall, an enemy or a chest, it
-- spends that move turning round in place and walks back on the next. In the
-- corridor of tiles x = 4..7 it makes 3 moves, turns, and makes 3 moves back.
-- Two zombies that meet head-on both turn round.
scene("zombieTurnsRoundWhenBlocked", function()
	Tile.setType(3, 6, "StoneWall")
	Tile.setType(8, 6, "StoneWall")
	fixtures.spawn("Slime", 8, -4)
	fixtures.spawn("ChestRed", 8, 2)
	return {
		corridor = zombie(4, 6, RIGHT),
		slime = zombie(5, -4, RIGHT),
		chest = zombie(5, 2, RIGHT),
		east = zombie(-8, -6, RIGHT),
		west = zombie(-3, -6, LEFT),
	}
end, fixtures.repeated("idle", 17), {
	[1] = function(s)
		assertAt(s.corridor, 5, 6, "first move")
	end,
	[2] = function(s)
		assertAt(s.corridor, 5, 6, "no move on the second beat")
	end,
	[3] = function(s)
		assertAt(s.east, -6, -6, "east zombie")
		assertAt(s.west, -5, -6, "west zombie, now face to face")
	end,
	[5] = function(s)
		assertAt(s.corridor, 7, 6, "third move, to the corridor's end")
		for _, name in ipairs({ "slime", "chest" }) do
			assertAt(s[name], 7, s[name].position.y, name .. ": stays put when blocked")
			assertFacing(s[name], LEFT, name .. ": turned round")
		end
		assertAt(s.east, -6, -6, "east zombie stays put")
		assertFacing(s.east, LEFT, "east zombie turned round")
		assertFacing(s.west, RIGHT, "west zombie turned round")
	end,
	[7] = function(s)
		assertAt(s.corridor, 7, 6, "corridor: stays put at the wall")
		assertFacing(s.corridor, LEFT, "corridor: turned round")
		for _, name in ipairs({ "slime", "chest" }) do
			assertAt(s[name], 6, s[name].position.y, name .. ": walks back")
		end
		assertAt(s.east, -7, -6, "east zombie walks back")
		assertAt(s.west, -4, -6, "west zombie walks back")
	end,
	[13] = function(s)
		assertAt(s.corridor, 4, 6, "three moves back")
	end,
	[15] = function(s)
		assertAt(s.corridor, 4, 6, "turns at the other end")
		assertFacing(s.corridor, RIGHT, "turned round again")
	end,
	[17] = function(s)
		assertAt(s.corridor, 5, 6, "and walks on")
	end,
})

-- Walking at the player, a zombie hits for 2 instead of stepping onto them,
-- every second beat, without moving. Once the player steps off its line it
-- walks on the same way, through the player's old tile.
scene("zombieHitsAlongItsLine", function()
	return zombie(3, 0, LEFT)
end, { "idle", "idle", "idle", "idle", "idle", "idle", "up", "idle", "idle" }, {
	[3] = function(z)
		assertAt(z, 1, 0, "next to the player")
		assert(health() == 12, "no hit on arrival")
	end,
	[4] = function()
		assert(health() == 12, "no hit on the beat after it arrives")
	end,
	[5] = function(z)
		assertAt(z, 1, 0, "stays put while it hits")
		assert(health() == 10, "hits for 2 on its next move")
	end,
	[6] = function()
		assert(health() == 10, "no hit on the next beat")
	end,
	[7] = function(z)
		assertAt(z, 0, 0, "walks on once the player leaves its line")
		assertFacing(z, LEFT, "same direction")
		assert(health() == 10, "no hit after the player left")
	end,
	[9] = function(z)
		assertAt(z, -1, 0, "keeps walking")
	end,
})

-- A zombie never turns toward the player: next to the player but facing away,
-- or walking along the line beside the player, or passing one tile away, it
-- walks straight on and never hits.
scene("zombieNeverChases", function()
	return {
		away = zombie(1, 0, RIGHT),
		beside = zombie(0, 1, RIGHT),
		passing = zombie(-4, -1, RIGHT),
	}
end, fixtures.repeated("idle", 12), {
	[1] = function(s)
		assertAt(s.away, 2, 0, "walks away")
		assertAt(s.beside, 1, 1, "walks along")
	end,
	[7] = function(s)
		assertAt(s.passing, 0, -1, "right beside the player")
	end,
	[12] = function(s)
		assertAt(s.away, 7, 0, "still walking away")
		assertAt(s.beside, 6, 1, "still walking along")
		assertAt(s.passing, 2, -1, "walked past")
		assert(health() == 12, "no zombie hit the player")
	end,
})

-- One dagger hit kills a zombie, here from its side.
scene("zombieDiesToOneHit", function()
	return zombie(1, 0, UP)
end, { "right" }, {
	[1] = function(z)
		assert(not Entities.entityExists(z.id), "one dagger hit kills a zombie")
	end,
})

-- A bounce trap pushes a zombie a tile sideways; it keeps walking the way it was.
scene("zombieKeepsItsWayAfterABounce", function()
	fixtures.spawn("BounceTrapRight", 5, 3)
	return zombie(5, 1, DOWN)
end, fixtures.repeated("idle", 5), {
	[3] = function(z)
		assertAt(z, 6, 3, "pushed right off the trap")
	end,
	[5] = function(z)
		assertAt(z, 6, 4, "still walking down")
		assertFacing(z, DOWN, "same direction")
	end,
})

local function bounceTrapAt(x, y)
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.position.x == x and entity.position.y == y and entity.name:find("BounceTrap", 1, true) then
			return true
		end
	end
	return false
end

-- Zombies that come with a level follow the same rules: they act from the first
-- beat, and each move is a step the way the zombie faces or a turn round in
-- place, except where a bounce trap pushes it.
testsApi.registerTest({
	name = "naturalZombieFollowsTheRules",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		-- Level 3 has zombies. A level change from the first level takes effect
		-- late, so go through level 2 and poll.
		GameSession.goToLevel(2)
		testsApi.afterTicks(400, function()
			GameSession.goToLevel(3)
			local function whenLoaded()
				if CurrentLevel.getNumber() ~= 3 then
					testsApi.afterTicks(10, whenLoaded)
					return
				end
				testsApi.afterTicks(300, function()
					local zombies = {}
					for entity in Entities.entitiesWithComponents({ "ai" }) do
						if entity.name == "Zombie" then
							local x, y = entity.position.x, entity.position.y
							local d = entity.facingDirection.direction
							table.insert(zombies, { entity = entity, x = x, y = y, d = d })
						end
					end
					assert(#zombies >= 2, "level 3 has zombies")
					local turns, steps = 0, 0
					testsApi.play(fixtures.repeated("idle", 6), function(index)
						if index % 2 == 0 then
							return
						end
						for _, z in ipairs(zombies) do
							local e = z.entity
							local x, y, d = e.position.x, e.position.y, e.facingDirection.direction
							local tx, ty = z.x + STEP[z.d][1], z.y + STEP[z.d][2]
							if x == z.x and y == z.y then
								assert(d == (z.d + 3) % 8 + 1, "a zombie that does not move turns round")
								turns = turns + 1
							elseif x == tx and y == ty then
								assert(d == z.d, "a zombie that steps keeps its way")
								steps = steps + 1
							else
								assert(bounceTrapAt(tx, ty), "a zombie left its line with no bounce trap")
								assert(d == z.d, "a bounced zombie keeps its way")
							end
							z.x, z.y, z.d = x, y, d
						end
					end, function()
						assert(turns > 0 and steps > 0, "saw both steps and turns")
						finish()
					end)
				end)
			end
			whenLoaded()
		end)
	end,
})
