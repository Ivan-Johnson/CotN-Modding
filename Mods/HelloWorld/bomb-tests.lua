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

-- Backs AuthoredDocs/Src/bombs.md. Each test plays Cadence in no-beat mode on
-- an open floor with 100 health, so a hit shows as a small drop. The player
-- starts at (0,0) with one bomb; "up" is toward negative y.

local RING = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }

local function player()
	return fixtures.player()
end

local function health()
	return player().health.health
end

local function bombCount()
	for entity in Entities.entitiesWithComponents({ "itemStack" }) do
		if entity.name == "Bomb" and entity.item.holder == player().id then
			return entity.itemStack.quantity
		end
	end
	return 0
end

local function litBombs()
	local count = 0
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name == "BombLit" then
			count = count + 1
		end
	end
	return count
end

local function exists(entity)
	return Entities.entityExists(entity.id)
end

local function tileName(x, y)
	return Tile.getInfo(x, y).name
end

-- An enemy that never acts, so a test can read what the blast alone did.
local function frozen(typeName, x, y, hp)
	local entity = fixtures.spawn(typeName, x, y)
	if entity.beatDelay then
		entity.beatDelay.interval = 100000
		entity.beatDelay.counter = 100000
	end
	if hp then
		entity.health.health = hp
		entity.health.maxHealth = hp
	end
	return entity
end

local function scene(name, setup, actions, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(8)
			player().health.health = 100
			player().health.maxHealth = 100
			local state = setup() or {}
			testsApi.play(actions, function(index, _, resolved)
				if checks[index] then
					checks[index](state, resolved)
				end
			end, finish)
		end,
	})
end

local FUSE = { "bomb", "idle", "idle", "idle" }

-- The bomb goes off on the third turn after the one that placed it, hurts
-- everything in the 3 by 3 around it for 4, and nothing two tiles away.
scene("bombBlastIsThreeByThree", function()
	local targets = {}
	for dy = -2, 2 do
		for dx = -2, 2 do
			if dx ~= 0 or dy ~= 0 then
				targets[#targets + 1] = { dx, dy, frozen("Slime", dx, dy, 100) }
			end
		end
	end
	return targets
end, FUSE, {
	[1] = function()
		assert(bombCount() == 0, "placing spends the one bomb you start with")
		assert(litBombs() == 1, "a lit bomb is on the floor")
	end,
	[3] = function()
		assert(litBombs() == 1, "still burning after two turns")
		assert(health() == 100, "nothing has exploded yet")
	end,
	[4] = function(targets)
		assert(litBombs() == 0, "gone on the third turn after placing")
		assert(health() == 96, "the player on the bomb takes 4")
		for _, t in ipairs(targets) do
			local damage = 100 - t[3].health.health
			local near = math.abs(t[1]) <= 1 and math.abs(t[2]) <= 1
			assert(damage == (near and 4 or 0), string.format("slime at (%d,%d) took %d", t[1], t[2], damage))
		end
	end,
})

-- Standing one tile away, even diagonally, still costs 4; two tiles away is safe.
scene("bombHurtsPlayerOnlyWithinOneTile", function()
	Inventory.grant("Bomb", player())
	Inventory.grant("Bomb", player())
end, {
	"bomb", "right", "right", "idle", "idle",
	"bomb", "down", "right", "idle", "idle",
	"bomb", "right", "idle", "idle",
}, {
	[4] = function()
		assert(health() == 100, "two tiles away takes nothing")
	end,
	[9] = function()
		assert(health() == 96, "diagonally adjacent takes 4")
	end,
	[14] = function()
		assert(health() == 92, "orthogonally adjacent takes 4")
	end,
})

-- Armor takes off what it takes off any hit.
scene("bombArmorReducesDamage", function()
	Inventory.grant("Bomb", player())
	Inventory.grant("Bomb", player())
	Inventory.grant("ArmorLeather", player())
end, {
	"bomb", "idle", "idle", "idle", "idle", "idle",
	"bomb", "idle", "idle", "idle", "idle", "idle",
	"bomb", "idle", "idle", "idle",
}, {
	[4] = function()
		assert(health() == 97, "leather armor: 3, got " .. (100 - health()))
		Inventory.grant("ArmorChainmail", player())
	end,
	[10] = function()
		assert(health() == 95, "chainmail: 2, got " .. (97 - health()))
		Inventory.grant("ArmorPlatemail", player())
	end,
	[16] = function()
		assert(health() == 94, "platemail: 1, got " .. (95 - health()))
	end,
})

-- A hit on one beat protects against a hit on the next; two beats apart both land.
scene("bombsOnConsecutiveBeatsHurtOnce", function()
	Inventory.grant("Bomb", player())
	Inventory.grant("Bomb", player())
	Inventory.grant("Bomb", player())
end, {
	"bomb", "bomb", "idle", "idle", "idle", "idle", "idle",
	"bomb", "idle", "bomb", "idle", "idle", "idle", "idle",
}, {
	[5] = function()
		assert(health() == 96, "back-to-back blasts hurt once")
	end,
	[14] = function()
		assert(health() == 88, "blasts two beats apart hurt twice")
	end,
})

-- Using the bomb action with none left passes the beat and breaks the coin
-- multiplier; a bomb already burning keeps its fuse.
scene("bombActionWithNoneLosesMultiplier", function()
	frozen("Slime", 1, 0)
end, { "right", "bomb", "bomb", "idle", "idle" }, {
	[1] = function()
		assert(player().grooveChain.multiplier == 2, "the kill raised the multiplier")
	end,
	[3] = function()
		assert(litBombs() == 1, "no second bomb")
		assert(player().grooveChain.multiplier == 1, "the empty press broke the multiplier")
	end,
	[5] = function()
		assert(litBombs() == 0, "the empty press still passed a beat of the fuse")
	end,
})

-- A Bomb pickup adds one; a Bomb3 adds three.
scene("bombPickupsAddOneAndThree", function()
	fixtures.spawn("Bomb", 1, 0)
	fixtures.spawn("Bomb3", 2, 0)
end, { "right", "right" }, {
	[1] = function()
		assert(bombCount() == 2, "Bomb: 1 + 1, got " .. bombCount())
	end,
	[2] = function()
		assert(bombCount() == 5, "Bomb3: 2 + 3, got " .. bombCount())
	end,
})

-- A lit bomb does not block the tile: a second goes down on it and the player
-- steps back onto it.
scene("bombDoesNotBlockItsTile", function()
	Inventory.grant("Bomb", player())
end, { "bomb", "bomb", "right", "left" }, {
	[2] = function()
		assert(litBombs() == 2, "two lit bombs on one tile")
	end,
	[4] = function()
		assert(player().position.x == 0, "back on the bomb's tile")
	end,
})

-- A lit bomb inside another's blast is not set off by it.
scene("bombInsideAnotherBlastKeepsBurning", function()
	Inventory.grant("Bomb", player())
end, { "bomb", "right", "bomb", "right", "right", "idle", "idle" }, {
	[3] = function()
		assert(litBombs() == 2, "two lit bombs")
	end,
	[4] = function()
		assert(litBombs() == 1, "only the first went off")
	end,
	[5] = function()
		assert(litBombs() == 1, "the second still burns")
	end,
	[6] = function()
		assert(litBombs() == 0, "the second went off on its own fuse")
	end,
})

-- Walls: breakable kinds in the 3 by 3 become floor, even behind unbreakable
-- ones; the level border, unbreakable walls and anything two tiles out stay.
scene("bombWallsInThreeByThree", function()
	local layout = {
		{ 0, -1, "UnbreakableWall", "UnbreakableWall" },
		{ 1, -1, "DirtWall", "Floor" },
		{ 1, 0, "LevelBorder", "LevelBorder" },
		{ 1, 1, "StoneWall", "Floor" },
		{ 0, 1, "ShopWall", "Floor" },
		{ -1, 1, "DoorHorizontal", "Floor" },
		{ -1, 0, "CatacombWall", "Floor" },
		{ -1, -1, "DirtWall", "Floor" },
		{ 0, -2, "DirtWall", "DirtWall" },
		{ 2, 2, "StoneWall", "StoneWall" },
	}
	for _, l in ipairs(layout) do
		Tile.setType(l[1], l[2], l[3])
	end
	return layout
end, FUSE, {
	[4] = function(layout)
		for _, l in ipairs(layout) do
			local now = tileName(l[1], l[2])
			assert(now == l[4], string.format("%s at (%d,%d) became %s", l[3], l[1], l[2], now))
		end
	end,
})

-- Items and traps in the 3 by 3 are destroyed, wherever in it; chests are
-- untouched; two tiles out is safe. Everything is spawned once the player has
-- stepped away from the bomb.
scene("bombDestroysItemsAndTraps", function()
	return {}
end, { "bomb", "right", "right", "right", "idle" }, {
	[3] = function(state)
		local function put(typeName, x, y)
			state[#state + 1] = { typeName, x, y, fixtures.spawn(typeName, x, y) }
		end
		put("ResourceCoin10", 0, 0)
		put("Food1", 0, 0)
		put("WeaponGoldenDagger", 0, 0)
		put("ArmorLeather", 0, -1)
		put("MiscKey", 1, -1)
		put("ResourceDiamond", -1, -1)
		put("Bomb3", -1, 0)
		put("SpikeTrap", 1, 1)
		put("BounceTrapUp", 0, 1)
		put("Trapdoor", -1, 1)
		put("ChestBlack", 1, 0)
		put("ArmorLeather", -2, 0)
		put("ResourceCoin10", 2, 2)
	end,
	[5] = function(state)
		for _, s in ipairs(state) do
			local gone = not exists(s[4])
			local shouldGo = s[1] ~= "ChestBlack" and math.abs(s[2]) <= 1 and math.abs(s[3]) <= 1
			assert(gone == shouldGo, string.format("%s at (%d,%d): gone=%s", s[1], s[2], s[3], tostring(gone)))
		end
	end,
})

-- Crates break, except Crate3, which has 3 health and loses 1 per bomb.
scene("bombBreaksCrates", function()
	return {
		crate = fixtures.spawn("Crate", 0, -1),
		crate2 = fixtures.spawn("Crate2", 1, 0),
		crate3 = fixtures.spawn("Crate3", 0, 1),
		far = fixtures.spawn("Crate3", -2, 0),
	}
end, FUSE, {
	[4] = function(crates)
		assert(not exists(crates.crate), "Crate breaks")
		assert(not exists(crates.crate2), "Crate2 breaks")
		assert(crates.crate3.health.health == 2, "Crate3 lost 1, has " .. crates.crate3.health.health)
		assert(crates.far.health.health == 3, "a crate two tiles away is untouched")
	end,
})

-- Every enemy type in the blast takes 4.
scene("bombDoes4ToEveryEnemy", function()
	local types = { "Slime", "Skeleton3", "Bat3", "Zombie", "Monkey2", "Minotaur2", "Dragon2", "Trapchest" }
	local list = {}
	for k, typeName in ipairs(types) do
		list[#list + 1] = { typeName, frozen(typeName, RING[k][1], RING[k][2], 100) }
	end
	return list
end, FUSE, {
	[4] = function(list)
		for _, p in ipairs(list) do
			assert(100 - p[2].health.health == 4, p[1] .. " took " .. (100 - p[2].health.health))
		end
	end,
})

-- Enemies killed by the blast count as kills for the coin multiplier and
-- leave their coins, which the blast does not destroy.
scene("bombKillsCountAndLeaveCoins", function()
	local list = {}
	for k, typeName in ipairs({ "Slime", "Skeleton3", "Zombie", "Minotaur", "Dragon" }) do
		list[#list + 1] = frozen(typeName, RING[k][1], RING[k][2])
	end
	return list
end, FUSE, {
	[4] = function(list)
		for _, entity in ipairs(list) do
			assert(not exists(entity), entity.name .. " should have died")
		end
		assert(player().grooveChain.multiplier >= 2, "the kills raised the multiplier")
		local coins = 0
		for entity in Entities.entitiesWithComponents({ "position" }) do
			if entity.name:find("ResourceCoin", 1, true) then
				coins = coins + 1
			end
		end
		assert(coins >= 4, "coins from the kills lie on the floor, got " .. coins)
	end,
})

-- The blast goes off before enemies move on that turn: a charger must already
-- be within one tile of the bomb. The charger starts d tiles east of the bomb
-- and charges from the turn it is placed; the player retreats west.
for _, case in ipairs({
	{ "Minotaur", 4, true },
	{ "Minotaur", 5, false },
	{ "Dragon", 3, true },
	{ "Dragon", 4, false },
}) do
	local typeName, distance, dies = case[1], case[2], case[3]
	scene("bombCatches" .. typeName .. "At" .. distance, function()
		return fixtures.spawn(typeName, distance, 0)
	end, { "bomb", "left", "left", "idle" }, {
		[4] = function(charger)
			assert(health() == 100, "the player stays out of reach")
			assert(exists(charger) == not dies, typeName .. " from " .. distance .. " tiles: dies=" .. tostring(dies))
		end,
	})
end

-- The shop is at fixed tiles of the test level: the door at (-9,0), the shopkeeper
-- at (-9,-5) behind a counter, wares at (-10,-3), (-9,-3) and (-8,-3). The route
-- is carved across the level's rock, since the shop sits behind it.
local function carve(x, y)
	Tile.setType(x, y, "Floor")
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.position.x == x and entity.position.y == y and entity.name:find("Wall", 1, true) and not entity.item then
			Object.delete(entity)
		end
	end
end

local function shopScene(name, route, tail, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(3, "Shopkeeper")
			for x = -9, 0 do
				carve(x, 1)
			end
			player().health.health = 100
			player().health.maxHealth = 100
			Inventory.grant("Bomb", player())
			local keeper
			local wares = {}
			for entity in Entities.entitiesWithComponents({ "position" }) do
				local position = entity.position
				if position.x == -9 and position.y == -5 and entity.name == "Shopkeeper" then
					keeper = entity
				elseif position.y == -3 and position.x >= -10 and position.x <= -8 and entity.sale then
					wares[#wares + 1] = entity
				end
			end
			assert(keeper and #wares == 3, "the shop is where the test expects")
			local actions = { "down" }
			for _, a in ipairs({ "left", "left", "left", "left", "left", "left", "left", "left", "left" }) do
				actions[#actions + 1] = a
			end
			for _, a in ipairs(route) do
				actions[#actions + 1] = a
			end
			local placed = #actions + 1
			for _, a in ipairs(tail) do
				actions[#actions + 1] = a
			end
			testsApi.play(actions, function(index)
				if checks[index - placed + 1] then
					local remaining = 0
					for _, ware in ipairs(wares) do
						if exists(ware) then
							remaining = remaining + 1
						end
					end
					checks[index - placed + 1](keeper, remaining)
				end
			end, finish)
		end,
	})
end

-- A bomb that destroys wares but misses the shopkeeper angers nobody.
shopScene("bombBesideWaresLeavesShopkeeperAlone",
	{ "up", "up", "up", "up", "up" },
	{ "bomb", "left", "left", "idle", "idle", "idle", "idle", "idle", "idle" }, {
		[4] = function(keeper, wares)
			assert(wares == 0, "all three wares gone, got " .. wares)
			assert(keeper.health.health == 9, "the shopkeeper is unhurt")
		end,
		[9] = function()
			assert(health() == 100, "and does nothing to the player")
		end,
	})

-- A bomb that hurts the shopkeeper makes him leave his counter and hit for 20
-- every second beat.
shopScene("bombThatHurtsShopkeeperMakesHimAttack",
	{ "up", "up", "up", "up", "up", "right", "right", "up", "up", "left" },
	{ "bomb", "left", "left", "left", "idle", "idle", "idle", "idle", "idle", "idle" }, {
		[4] = function(keeper, wares)
			assert(keeper.health.health == 5, "the shopkeeper took 4")
			assert(wares == 1, "the two wares beside the bomb are gone; the far one is not")
		end,
		[10] = function()
			assert(health() == 100 - 3 * 20, "three hits of 20 in six beats, got " .. (100 - health()))
		end,
	})
