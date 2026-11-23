local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on HelloWorldTests; see tests.lua.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end
local fixtures = require "HelloWorldTests.fixtures"

-- Backs AuthoredDocs/Src/digging.md. Each test plays Cadence in no-beat mode on
-- an open floor; a wall sits on the tile to the right of the player, so one
-- "right" either digs it (it becomes Floor, the player stays) or leaves it.

local function tileName(x, y)
	local info = Tile.getInfo(x, y)
	return info and info.name or "nil"
end

local function equip(shovel)
	for _, item in ipairs(Inventory.getItemsInSlot(fixtures.player(), "shovel")) do
		Object.delete(item)
	end
	if shovel then
		Inventory.grant(shovel, fixtures.player())
	end
end

local function shovelCount()
	return #Inventory.getItemsInSlot(fixtures.player(), "shovel")
end

local function health()
	return fixtures.player().health.health
end

local function gold()
	return fixtures.player().goldCounter.amount
end

local function multiplier()
	return fixtures.player().grooveChain.multiplier
end

local function digTest(name, setup, actions, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(8)
			local scene = setup()
			testsApi.play(actions, function(index)
				if checks[index] then
					checks[index](scene)
				end
			end, finish)
		end,
	})
end

-- Runs one bump per trial against a wall on the tile to the right, with the
-- named shovel (nil: no shovel), and asserts whether the wall gave way. The
-- player never moves, since a bump either digs the wall or does nothing.
local function bumpTrials(name, trials)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(8)
			local trial = 0
			local function nextTrial()
				trial = trial + 1
				local spec = trials[trial]
				if not spec then
					finish()
					return
				end
				local shovel, wall, digs = spec[1], spec[2], spec[3]
				equip(shovel)
				Tile.setType(1, 0, wall)
				testsApi.play({ "right" }, function()
					local description = string.format("%s on %s", shovel or "no shovel", wall)
					assert(fixtures.player().position.x == 0, description .. ": a dig leaves the player in place")
					local dug = tileName(1, 0) == "Floor"
					assert(dug == digs, description .. (digs and ": expected the wall to be dug" or ": expected the wall to stand"))
				end, nextTrial)
			end
			nextTrial()
		end,
	})
end

-- Dirt 1, stone 2, catacomb 3, shop 4; a shovel digs walls up to its strength.
bumpTrials("digShovelStrength", {
	{ "ShovelBasic", "DirtWall", true },
	{ "ShovelBasic", "StoneWall", false },
	{ "ShovelShard", "DirtWall", true },
	{ "ShovelShard", "StoneWall", false },
	{ "ShovelCourage", "StoneWall", false },
	{ "ShovelTitanium", "StoneWall", true },
	{ "ShovelTitanium", "CatacombWall", false },
	{ "ShovelBattle", "StoneWall", true },
	{ "ShovelBattle", "CatacombWall", false },
	{ "ShovelStrength", "StoneWall", true },
	{ "ShovelStrength", "CatacombWall", false },
	{ "ShovelCrystal", "CatacombWall", true },
	{ "ShovelCrystal", "ShopWall", false },
	{ "ShovelGlass", "CatacombWall", true },
	{ "Pickaxe", "ShopWall", false },
})

-- Earth walls and doors open for any move, shovel or not. Nothing digs the
-- level border or a locked door.
bumpTrials("digDoorsEarthAndUndiggables", {
	{ nil, "DirtWall", false },
	{ nil, "EarthWall", true },
	{ nil, "DoorHorizontal", true },
	{ "ShovelBasic", "EarthWall", true },
	{ "ShovelCrystal", "LevelBorder", false },
	{ "ShovelCrystal", "LockedDoorHorizontal", false },
	{ "ShovelBlood", "LevelBorder", false },
	{ "ShovelBlood", "LockedDoorHorizontal", false },
})

-- A dig is one action; the next move walks into the gap.
digTest("digIsOneActionThenWalkThrough", function()
	Tile.setType(1, 0, "DirtWall")
end, { "right", "right" }, {
	[1] = function()
		assert(fixtures.player().position.x == 0 and tileName(1, 0) == "Floor", "the dig leaves the player in place")
	end,
	[2] = function()
		assert(fixtures.player().position.x == 1, "the next move steps into the gap")
	end,
})

-- The Blood Shovel (strength 1) digs anything diggable, and each wall tougher
-- than dirt costs 1 health; shop walls leave 10 gold on their tile.
digTest("digBloodShovelCostsHealth", function()
	equip("ShovelBlood")
	for i, wall in ipairs({ "DirtWall", "StoneWall", "CatacombWall", "ShopWall" }) do
		Tile.setType(2 * i - 1, 0, wall)
	end
end, { "right", "right", "right", "right", "right", "right", "right", "right", "right", "right", "right" }, {
	[1] = function()
		assert(health() == 12, "a dirt wall is free")
	end,
	[4] = function()
		assert(health() == 11 and tileName(3, 0) == "Floor", "a stone wall costs 1 health")
	end,
	[7] = function()
		assert(health() == 10 and tileName(5, 0) == "Floor", "a catacomb wall costs 1 health")
	end,
	[10] = function()
		assert(health() == 9 and tileName(7, 0) == "Floor", "a shop wall costs 1 health")
	end,
	[11] = function()
		assert(gold() == 10, "a shop wall leaves 10 gold")
	end,
})

-- The Glass Shovel (strength 3) shatters on the first wall tougher than that.
digTest("digGlassShovelShattersOnShopWall", function()
	equip("ShovelGlass")
	Tile.setType(1, 0, "CatacombWall")
	Tile.setType(3, 0, "ShopWall")
	Tile.setType(5, 0, "DirtWall")
end, { "right", "right", "right", "right", "right", "right", "right" }, {
	[1] = function()
		assert(tileName(1, 0) == "Floor" and shovelCount() == 1, "a catacomb wall does not break it")
	end,
	[4] = function()
		assert(tileName(3, 0) == "Floor", "it digs the shop wall once")
		assert(shovelCount() == 0, "and then shatters")
	end,
	[7] = function()
		assert(tileName(5, 0) == "DirtWall", "with no shovel left, dirt stands")
	end,
})

-- The Obsidian Shovel digs as deep as the coin multiplier: x1 dirt, x2 stone,
-- x3 catacomb, and never a shop wall.
local function obsidianTrial(kills, wall, digs)
	digTest("digObsidianAtMultiplier" .. (kills == 0 and 1 or kills == 1 and 2 or 3) .. wall, function()
		equip("ShovelObsidian")
		for x = 1, kills do
			fixtures.spawn("Slime", x, 0)
		end
		Tile.setType(kills + 1, 0, wall)
	end, (function()
		local actions = {}
		for _ = 1, kills * 2 + 1 do
			table.insert(actions, "right")
		end
		return actions
	end)(), {
		[kills * 2 + 1] = function()
			assert((tileName(kills + 1, 0) == "Floor") == digs, wall .. " at x" .. multiplier())
		end,
	})
end

obsidianTrial(0, "DirtWall", true)
obsidianTrial(0, "StoneWall", false)
obsidianTrial(1, "StoneWall", true)
obsidianTrial(1, "CatacombWall", false)
obsidianTrial(5, "CatacombWall", true)
obsidianTrial(5, "ShopWall", false)

-- The Pickaxe takes one hit per point of toughness.
digTest("digPickaxeHitsPerToughness", function()
	equip("Pickaxe")
	Tile.setType(1, 0, "DirtWall")
	Tile.setType(3, 0, "StoneWall")
	Tile.setType(6, 0, "CatacombWall")
end, { "right", "right", "right", "right", "right", "right", "right", "right", "right", "right", "right" }, {
	[1] = function()
		assert(tileName(1, 0) == "Floor", "dirt: one hit")
	end,
	[4] = function()
		assert(tileName(3, 0) ~= "Floor", "stone: still standing after one hit")
	end,
	[5] = function()
		assert(tileName(3, 0) == "Floor", "stone: gone after two hits")
	end,
	[9] = function()
		assert(tileName(6, 0) ~= "Floor", "catacomb: standing after one hit")
	end,
	[10] = function()
		assert(tileName(6, 0) ~= "Floor", "catacomb: standing after two hits")
	end,
	[11] = function()
		assert(tileName(6, 0) == "Floor", "catacomb: gone after three hits")
	end,
})

-- The Shovel of Strength also digs every wall touching the one you hit that it
-- could dig on its own.
digTest("digStrengthShovelDigsNeighbours", function()
	equip("ShovelStrength")
	for y = -1, 1 do
		for x = 1, 2 do
			Tile.setType(x, y, "DirtWall")
		end
	end
	Tile.setType(2, 0, "StoneWall")
	Tile.setType(2, 1, "CatacombWall")
end, { "right" }, {
	[1] = function()
		for _, tile in ipairs({ { 1, 0 }, { 1, -1 }, { 1, 1 }, { 2, 0 }, { 2, -1 } }) do
			assert(tileName(tile[1], tile[2]) == "Floor", string.format("(%d,%d) is dug", tile[1], tile[2]))
		end
		assert(tileName(2, 1) == "CatacombWall", "a wall it could not dig alone stands")
	end,
})

-- A dig keeps the coin multiplier; a failed dig breaks it.
digTest("digKeepsMultiplierFailureBreaksIt", function()
	fixtures.spawn("Slime", 1, 0)
	Tile.setType(2, 0, "DirtWall")
	Tile.setType(4, 0, "StoneWall")
end, { "right", "right", "right", "right", "right", "right" }, {
	[1] = function()
		assert(multiplier() == 2, "a kill raises the multiplier")
	end,
	[3] = function()
		assert(tileName(2, 0) == "Floor" and multiplier() == 2, "a dig keeps it")
	end,
	[6] = function()
		assert(tileName(4, 0) == "StoneWall" and multiplier() == 1, "a failed dig breaks it")
	end,
})

-- The Battle Shovel makes the attack on the action right after a dig lethal.
digTest("digBattleShovelAttackAfterDig", function()
	equip("ShovelBattle")
	Tile.setType(0, -1, "DirtWall")
	local slime = fixtures.spawn("Slime", 1, 0)
	slime.health.health = 1000
	slime.health.maxHealth = 1000
	return slime
end, { "up", "right" }, {
	[1] = function(slime)
		assert(slime.health.health == 1000, "digging is not an attack")
	end,
	[2] = function(slime)
		assert(not Entities.entityExists(slime.id), "the attack right after a dig kills a 1000-health Slime")
	end,
})

digTest("digBattleShovelAttackLaterIsNormal", function()
	equip("ShovelBattle")
	Tile.setType(0, -1, "DirtWall")
	local slime = fixtures.spawn("Slime", 1, 0)
	slime.health.health = 1000
	slime.health.maxHealth = 1000
	return slime
end, { "up", "idle", "right" }, {
	[3] = function(slime)
		assert(slime.health.health == 999, "an attack after a pause does 1 damage")
	end,
})

-- The Shovel of Courage carries the player into the tile it digs.
digTest("digCourageShovelDashes", function()
	equip("ShovelCourage")
	Tile.setType(1, 0, "DirtWall")
end, { "right" }, {
	[1] = function()
		assert(fixtures.player().position.x == 1, "the dig moves the player into the gap")
	end,
})

-- Digging leaves loot, removes a wall torch, and sets off a wall spike.
digTest("digWallContents", function()
	equip("ShovelBlood")
	Tile.setType(1, 0, "DirtWallWithGold")
	Tile.setType(3, 0, "DirtWallWithDiamonds")
	Tile.setType(5, 0, "DirtWall")
	Tile.setType(7, 0, "DirtWall")
	return {
		torch = fixtures.spawn("WallTorch", 5, 0),
		spike = fixtures.spawn("Sync_WallSpike", 7, 0),
	}
end, { "right", "right", "right", "right", "right", "right", "right", "right", "right", "right", "right" }, {
	[2] = function()
		assert(gold() == 25, "a dirt wall with gold leaves 25 gold")
	end,
	[4] = function()
		local diamonds = 0
		for entity in Entities.entitiesWithComponents({ "position" }) do
			if entity.name == "ResourceDiamond" and entity.position.x == 3 and entity.position.y == 0 then
				diamonds = diamonds + 1
			end
		end
		assert(diamonds == 1, "a dirt wall with diamonds leaves a diamond on its tile")
	end,
	[7] = function(scene)
		assert(not Entities.entityExists(scene.torch.id), "a wall torch goes with its wall")
		assert(health() == 12, "a torch does no harm")
	end,
	[10] = function(scene)
		assert(not Entities.entityExists(scene.spike.id), "a wall spike goes with its wall")
		assert(health() == 11, "digging into a wall spike costs 1 health")
	end,
})

-- Enemies dig too: a Minotaur digs up to stone (and doors) but not catacomb or
-- shop walls, a Dragon digs everything except the level border. A dig takes
-- the enemy's action.
local function enemyDigs(name, enemyType, wall, digs, spawnX)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(8)
			Tile.setType(2, 0, wall)
			local enemy = fixtures.spawn(enemyType, spawnX, 0)
			local actions = {}
			for _ = 1, 8 do
				table.insert(actions, "idle")
			end
			testsApi.play(actions, nil, function()
				assert((tileName(2, 0) == "Floor") == digs, enemyType .. " vs " .. wall)
				if digs then
					assert(enemy.position.x <= 2, enemyType .. " came through")
				else
					assert(enemy.position.x >= 3, enemyType .. " stayed behind the wall")
				end
				finish()
			end)
		end,
	})
end

enemyDigs("digMinotaurDigsStone", "Minotaur", "StoneWall", true, 5)
enemyDigs("digMinotaurStopsAtCatacomb", "Minotaur", "CatacombWall", false, 5)
enemyDigs("digMinotaurStopsAtShopWall", "Minotaur2", "ShopWall", false, 5)
-- A dig takes the Minotaur's move: it stands still for the beat that digs.
digTest("digMinotaurDigSpendsItsMove", function()
	Tile.setType(2, 0, "StoneWall")
	return fixtures.spawn("Minotaur", 5, 0)
end, { "idle", "idle", "idle", "idle" }, {
	[2] = function(minotaur)
		assert(minotaur.position.x == 3 and tileName(2, 0) == "StoneWall", "it walks up to the wall")
	end,
	[3] = function(minotaur)
		assert(minotaur.position.x == 3 and tileName(2, 0) == "Floor", "it digs instead of moving")
	end,
	[4] = function(minotaur)
		assert(minotaur.position.x == 2, "and walks through the next beat")
	end,
})

enemyDigs("digMinotaurDigsDoors", "Minotaur", "DoorHorizontal", true, 5)
enemyDigs("digMinotaurDigsDirt", "Minotaur", "DirtWall", true, 5)
enemyDigs("digMinotaurDigsEarthWall", "Minotaur", "EarthWall", true, 5)
enemyDigs("digMinotaur2DigsStone", "Minotaur2", "StoneWall", true, 5)

-- A sleeping Dragon wakes when the player is within three tiles with a clear
-- line, so the wall goes up after the first beat, when it has woken and
-- stepped next to where the wall will be.
local function dragonVersus(name, wall, digs)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(8)
			local dragon = fixtures.spawn("Dragon", 3, 0)
			local actions = {}
			for _ = 1, 9 do
				table.insert(actions, "idle")
			end
			testsApi.play(actions, function(index)
				if index == 1 then
					assert(dragon.aggro.active, "the dragon is awake")
					Tile.setType(1, 0, wall)
				end
			end, function()
				assert((tileName(1, 0) == "Floor") == digs, "Dragon vs " .. wall)
				assert((dragon.position.x == 1) == digs, "the dragon walks through only a wall it dug")
				finish()
			end)
		end,
	})
end

dragonVersus("digDragonDigsDirtWall", "DirtWall", true)
dragonVersus("digDragonDigsStoneWall", "StoneWall", true)
dragonVersus("digDragonDigsCatacombWall", "CatacombWall", true)
dragonVersus("digDragonDigsShopWall", "ShopWall", true)
dragonVersus("digDragonCannotDigTheBorder", "LevelBorder", false)
