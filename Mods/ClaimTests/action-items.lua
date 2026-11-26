local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence in no-beat mode on an open floor, holding the item
-- under test, with 100 health so a hit shows as a small drop. The player
-- starts at (0,0); "up" is toward negative y.

local RING = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }

local player = fixtures.player
local health = fixtures.health
local tileName = fixtures.tileName
local assertAt = fixtures.assertAt

local function chain()
	return player().grooveChain.multiplier
end

local function holds(typeName)
	for entity in Entities.entitiesWithComponents({ "item" }) do
		if entity.name == typeName and entity.item.holder == player().id then
			return true
		end
	end
	return false
end

local function exists(entity)
	return Entities.entityExists(entity.id)
end

-- An enemy that never acts, so a test can read what the item alone did.
local function frozen(typeName, x, y, hp)
	local entity = fixtures.spawn(typeName, x, y)
	entity.beatDelay.interval = 100000
	entity.beatDelay.counter = 100000
	if hp then
		entity.health.health = hp
		entity.health.maxHealth = hp
	end
	return entity
end

local function freezeTurns(entity)
	return entity.freezable.remainingTurns
end

-- Like fixtures.scene, but always as Cadence, whatever character the game
-- last used, and holding item.
local function scene(name, item, setup, actions, checks)
	testsApi.registerTest({
		name = name,
		file = "action-items.lua",
		character = "Cadence",
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			assert(player().name == "Cadence", "playing as " .. player().name)
			fixtures.openArena(8)
			player().health.health = 100
			player().health.maxHealth = 100
			Inventory.grant(item, player())
			local state = setup and setup() or {}
			testsApi.play(actions, function(index)
				if checks[index] then
					checks[index](state)
				end
			end, finish)
		end,
	})
end

-- The drum costs 1 health, stays held, and keeps the chain. The attack on the
-- next beat does 999 more to every enemy it hits; an idle beat in between
-- wastes it.
scene("bloodDrumNextAttack", "BloodDrum", function()
	Inventory.grant("WeaponBroadsword", player())
	fixtures.spawn("Slime", -1, 0)
	return { frozen("Skeleton", 1, -1, 2000), frozen("Skeleton", 1, 0, 2000), frozen("Skeleton", 1, 1, 2000) }
end, { "left", "item1", "right", "right", "item1", "idle", "right" }, {
	[2] = function()
		assert(health() == 99, "using the drum costs 1, got " .. (100 - health()))
		assert(holds("BloodDrum"), "the drum stays held")
		assert(chain() == 2, "the drum's cost keeps the chain")
	end,
	[3] = function(targets)
		for _, t in ipairs(targets) do
			assert(t.health.health == 1000, "the drummed swing did " .. (2000 - t.health.health))
		end
	end,
	[4] = function(targets)
		for _, t in ipairs(targets) do
			assert(t.health.health == 999, "the next swing is back to 1")
		end
	end,
	[7] = function(targets)
		for _, t in ipairs(targets) do
			assert(t.health.health == 998, "an idle beat after the drum wastes it")
		end
	end,
})

-- The dig on the next beat is 3 stronger: the basic shovel then digs stone,
-- catacomb and shop walls, but never an unbreakable wall.
scene("bloodDrumNextDig", "BloodDrum", function()
	Tile.setType(1, 0, "StoneWall")
	Tile.setType(0, -1, "CatacombWall")
	Tile.setType(-1, 0, "ShopWall")
	Tile.setType(0, 1, "UnbreakableWall")
end, { "item1", "right", "item1", "up", "item1", "left", "item1", "down" }, {
	[8] = function()
		assert(tileName(1, 0) == "Floor", "stone dug")
		assert(tileName(0, -1) == "Floor", "catacomb dug")
		assert(tileName(-1, 0) == "Floor", "shop wall dug")
		assert(tileName(0, 1) == "UnbreakableWall", "unbreakable stays")
	end,
})

-- An idle beat between the drum and the dig wastes it.
scene("bloodDrumDigWastedByIdle", "BloodDrum", function()
	Tile.setType(1, 0, "StoneWall")
end, { "item1", "idle", "right" }, {
	[3] = function()
		assert(tileName(1, 0) == "StoneWall", "the stone stays")
	end,
})

-- Using the drum at 1 health kills you.
scene("bloodDrumAtOneHealthKills", "BloodDrum", function()
	player().health.health = 1
end, { "item1" }, {
	[1] = function()
		assert(player().killable.dead, "the drum's cost killed the player")
	end,
})

-- Holy Water does 5 to each enemy in the 3 by 3 around you and nothing
-- farther, heals you 2 per enemy hit up to your maximum, and is used up.
scene("holyWaterHitsThreeByThree", "HolyWater", function()
	player().health.maxHealth = 10
	player().health.health = 2
	local targets = {}
	for dy = -2, 2 do
		for dx = -2, 2 do
			if dx ~= 0 or dy ~= 0 then
				targets[#targets + 1] = { dx, dy, frozen("Skeleton", dx, dy, 100) }
			end
		end
	end
	return targets
end, { "item1" }, {
	[1] = function(targets)
		for _, t in ipairs(targets) do
			local damage = 100 - t[3].health.health
			local near = math.abs(t[1]) <= 1 and math.abs(t[2]) <= 1
			assert(damage == (near and 5 or 0), string.format("skeleton at (%d,%d) took %d", t[1], t[2], damage))
		end
		assert(health() == 10, "eight hits heal up to the maximum, got " .. health())
		assert(not holds("HolyWater"), "used up")
	end,
})

scene("holyWaterHeals2PerEnemy", "HolyWater", function()
	player().health.maxHealth = 10
	player().health.health = 2
	for k = 1, 3 do
		frozen("Skeleton", RING[k][1], RING[k][2], 100)
	end
end, { "item1" }, {
	[1] = function()
		assert(health() == 8, "three enemies heal 6, got " .. (health() - 2))
	end,
})

-- Its kills are yours: eight in one use take the chain to x3.
scene("holyWaterKillsCount", "HolyWater", function()
	local list = {}
	for k, typeName in ipairs({ "Skeleton3", "Zombie", "Monkey2", "Slime2", "Slime3", "Slime", "Bat", "Minotaur" }) do
		list[k] = frozen(typeName, RING[k][1], RING[k][2])
	end
	return list
end, { "item1" }, {
	[1] = function(list)
		for _, entity in ipairs(list) do
			assert(not exists(entity), entity.name .. " survived")
		end
		assert(chain() == 3, "eight kills take the chain to x3, got " .. chain())
	end,
})

-- With nobody in range it is still used up.
scene("holyWaterWastedWithNoEnemyNear", "HolyWater", function()
	return frozen("Skeleton", 2, 0, 100)
end, { "item1" }, {
	[1] = function(skeleton)
		assert(skeleton.health.health == 100, "two tiles away is out of range")
		assert(not holds("HolyWater"), "used up anyway")
	end,
})

local function snowbro()
	for entity in Entities.entitiesWithComponents({ "follower" }) do
		if entity.name == "FollowerSnowbro" then
			return entity
		end
	end
end

-- The item, then a direction, puts the snowman on that tile without moving
-- you, and spends the item. After that it moves in step with you.
scene("iceSpiritPlacesSnowbro", "FamiliarIceSpirit", nil, { "item1", "right", "left", "up" }, {
	[1] = function()
		assert(snowbro() == nil, "the item alone places nothing")
	end,
	[2] = function()
		assertAt(player(), 0, 0, "the player")
		assertAt(snowbro(), 1, 0, "the snowman")
		assert(not holds("FamiliarIceSpirit"), "the item is spent")
	end,
	[3] = function()
		assertAt(snowbro(), 0, 0, "the snowman after a step left")
	end,
	[4] = function()
		assertAt(snowbro(), 0, -1, "the snowman after a step up")
	end,
})

-- An enemy that walks into the snowman is frozen for 3 beats: it does not
-- attack, then it does.
scene("snowbroFreezesEnemyThatWalksIn", "FamiliarIceSpirit", function()
	return fixtures.spawn("Skeleton", 3, 0)
end, { "item1", "right", "idle", "idle", "idle", "idle", "idle", "idle", "idle" }, {
	[3] = function(skeleton)
		assertAt(skeleton, 1, 0, "the skeleton on the snowman's tile")
		assert(freezeTurns(skeleton) == 3, "frozen for 3, got " .. freezeTurns(skeleton))
	end,
	[6] = function(skeleton)
		assert(freezeTurns(skeleton) == 0, "thawed")
		assert(health() == 100, "no attack while frozen")
	end,
	[9] = function()
		assert(health() < 100, "the thawed skeleton attacks")
	end,
})

-- The snowman moving onto an enemy freezes it too, and the frozen enemy still
-- takes your hits.
scene("snowbroFreezesEnemyItMovesOnto", "FamiliarIceSpirit", function()
	return frozen("Dragon", 1, -1, 50)
end, { "item1", "up", "right", "up", "up" }, {
	[3] = function(dragon)
		assertAt(snowbro(), 1, -1, "the snowman on the dragon")
		assert(freezeTurns(dragon) == 3, "frozen for 3, got " .. freezeTurns(dragon))
	end,
	[5] = function(dragon)
		assert(dragon.health.health == 48, "two dagger hits land, got " .. (50 - dragon.health.health))
	end,
})

-- Earth walls go on the floor tiles around you; other walls stay. An enemy on
-- one is pushed a tile out, unhurt, or dies if that tile is blocked, and the
-- death counts as your kill. The walls keep a live enemy out.
scene("earthSpellRaisesWalls", "SpellEarth", function()
	Tile.setType(-1, -1, "StoneWall")
	Tile.setType(1, 1, "UnbreakableWall")
	Tile.setType(0, 2, "StoneWall")
	return {
		pushed = fixtures.spawn("Skeleton", 1, 0),
		walled = frozen("Skeleton", 0, 1, 100),
		crowded = frozen("Minotaur", -1, 0, 100),
		behind = frozen("Skeleton", -2, 0, 100),
	}
end, (function()
	local actions = fixtures.repeated("idle", 31)
	actions[1] = "spell1"
	return actions
end)(), {
	[1] = function(s)
		for _, offset in ipairs(RING) do
			local expected = "EarthWall"
			if offset[1] == -1 and offset[2] == -1 then
				expected = "StoneWall"
			elseif offset[1] == 1 and offset[2] == 1 then
				expected = "UnbreakableWall"
			end
			local now = tileName(offset[1], offset[2])
			assert(now == expected, string.format("(%d,%d) is %s", offset[1], offset[2], now))
		end
		assertAt(s.pushed, 2, 0, "the pushed skeleton")
		assert(s.pushed.health.health == 1, "pushed unhurt")
		assert(not exists(s.walled), "a wall behind kills")
		assert(not exists(s.crowded), "an enemy behind kills")
		assert(s.behind.health.health == 100, "the enemy behind is unhurt")
		assert(chain() == 2, "the two deaths are your kills")
	end,
	[31] = function(s)
		assert(health() == 100, "the walls kept the skeleton out")
		assert(exists(s.pushed), "the skeleton is still outside")
		assert(tileName(1, 0) == "EarthWall", "the walls still stand")
	end,
})
