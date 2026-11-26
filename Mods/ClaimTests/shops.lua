local Currency = require "necro.game.item.Currency"
local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

local player = fixtures.player
local health = fixtures.health
local assertAt = fixtures.assertAt

local function gold()
	return Currency.get(player(), Currency.Type.GOLD)
end

local function priceTag(ware)
	return ware.sale.priceTag ~= 0 and Entities.getEntityByID(ware.sale.priceTag) or nil
end

-- The shopkeeper, and his wares from left to right.
local function findShop()
	local keeper
	for entity in Entities.entitiesWithComponents({ "shopkeeper" }) do
		if entity.name == "Shopkeeper" then
			keeper = entity
		end
	end
	assert(keeper, "the level has a shop")
	local wares = {}
	for entity in Entities.entitiesWithComponents({ "sale" }) do
		local p = entity.position
		if priceTag(entity) and p.y == keeper.position.y + 2 and math.abs(p.x - keeper.position.x) <= 1 then
			wares[p.x - keeper.position.x + 2] = entity
		end
	end
	return keeper, wares
end

-- Each zone's first floor has a shop: shop walls, the shopkeeper at the back,
-- and three wares priced in gold two tiles in front of him.
for zone = 1, 5 do
	testsApi.registerTest({
		name = "shopLayoutZone" .. zone,
		zone = zone,
		onLoad = function()
			local keeper, wares = findShop()
			local x, y = keeper.position.x, keeper.position.y
			for slot = 1, 3 do
				local tag = wares[slot] and priceTag(wares[slot])
				local priced = tag and tag.priceTagCostCurrency and tag.priceTagCostCurrency.cost > 0
				assert(priced, "ware " .. slot .. " has a gold price")
			end
			-- The room's edge, 3 tiles either side of him, from 3 tiles behind
			-- him to 5 in front, is shop wall but for at least one door.
			local doors = 0
			for dy = -3, 5 do
				for dx = -3, 3 do
					if math.abs(dx) == 3 or dy == -3 or dy == 5 then
						local tile = fixtures.tileName(x + dx, y + dy)
						if tile:find("Door", 1, true) then
							doors = doors + 1
						else
							assert(tile == "ShopWall", string.format("shop wall at (%d,%d), got %s", dx, dy, tile))
						end
					end
				end
			end
			assert(doors >= 1, "the shop has a door")
		end,
	})
end

-- On the test level (zone 1) the shop's door is at (-9,0), the shopkeeper at
-- (-9,-5) and the wares at (-10,-3), (-9,-3) and (-8,-3). A corridor is carved
-- from the start to below the door; the first move up opens the door.
local function carve(x, y)
	Tile.setType(x, y, "Floor")
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.position.x == x and entity.position.y == y and entity.name:find("Wall", 1, true) and not entity.item then
			Object.delete(entity)
		end
	end
end

local TO_DOOR = { "down", "left", "left", "left", "left", "left", "left", "left", "left", "left", "up" }

-- Inside the door, west to the shop's left column and up to beside the
-- middle ware's west neighbour, at (-10,-4); then a bomb beside the shopkeeper.
local TO_BOMB = { "up", "up", "left", "left", "up", "up", "up", "right", "bomb", "left", "down", "down", "down" }

local function cost(ware)
	return priceTag(ware).priceTagCostCurrency.cost
end

-- prepare(shop) runs before the route; checks[i](shop) after the route's
-- action i. A "fight" action becomes an attack on the adjacent shopkeeper, or
-- idle if he is not adjacent; each one is recorded in shop.log as
-- { playerDamage, keeperDamage, attacked }.
local function shopScene(name, prepare, route, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(3, "Shopkeeper")
			for x = -9, 0 do
				carve(x, 1)
			end
			player().health.health = 300
			player().health.maxHealth = 300
			Currency.set(player(), Currency.Type.GOLD, 0)
			local keeper, wares = findShop()
			assertAt(keeper, -9, -5, "the shop is where the test expects")
			local shop = { keeper = keeper, wares = wares, log = {} }
			prepare(shop)
			local actions = {}
			for _, a in ipairs(TO_DOOR) do
				actions[#actions + 1] = a
			end
			for _, a in ipairs(route) do
				actions[#actions + 1] = a
			end
			local offset = #TO_DOOR
			local before
			testsApi.play(actions, function(index)
				if before then
					before.playerDamage = before.health - health()
					before.keeperDamage = Entities.entityExists(keeper.id) and before.keeperHealth - keeper.health.health
						or before.keeperHealth
					shop.log[#shop.log + 1] = before
					before = nil
				end
				local check = checks[index - offset]
				if check then
					check(shop)
				end
				if actions[index + 1] == "fight" then
					actions[index + 1] = "idle"
					if Entities.entityExists(keeper.id) then
						local dx = keeper.position.x - player().position.x
						local dy = keeper.position.y - player().position.y
						if math.abs(dx) + math.abs(dy) == 1 then
							actions[index + 1] = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
						end
						before = {
							health = health(),
							keeperHealth = keeper.health.health,
							attacked = actions[index + 1] ~= "idle",
							keeperX = keeper.position.x,
							keeperY = keeper.position.y,
						}
					end
				end
			end, finish)
		end,
	})
end

local function fights(count)
	local list = {}
	for index = 1, count do
		list[index] = "fight"
	end
	return list
end

-- Walking onto a ware with exactly its price buys it; a weapon bought swaps
-- with yours, which stays on the tile unpriced.
shopScene("shopBuyAtExactPrice", function(shop)
	Currency.set(player(), Currency.Type.GOLD, cost(shop.wares[2]))
end, { "up", "up", "up", "up" }, {
	[4] = function(shop)
		assertAt(player(), -9, -3, "on the ware's tile")
		assert(gold() == 0, "the price is spent, left " .. gold())
		local weapon = Inventory.getItemInSlot(player(), "weapon")
		assert(weapon.id == shop.wares[2].id, "holding the ware, got " .. weapon.name)
		local old
		for entity in Entities.entitiesWithComponents({ "item" }) do
			if entity.name == "WeaponDagger" and entity.position and entity.position.x == -9 and entity.position.y == -3 then
				old = entity
			end
		end
		assert(old and not priceTag(old), "the old dagger lies on the tile, free")
	end,
})

-- One gold short, the move fails and nothing is spent.
shopScene("shopTooLittleGoldBlocks", function(shop)
	shop.price = cost(shop.wares[2])
	Currency.set(player(), Currency.Type.GOLD, shop.price - 1)
end, { "up", "up", "up", "up", "up" }, {
	[5] = function(shop)
		assertAt(player(), -9, -2, "stopped in front of the ware")
		assert(gold() == shop.price - 1, "no gold spent")
		assert(Entities.entityExists(shop.wares[2].id), "the ware is still for sale")
		assert(Inventory.getItemInSlot(player(), "weapon").name == "WeaponDagger", "still holding the dagger")
	end,
})

-- Attacking an unprovoked shopkeeper does nothing, and he never attacks.
shopScene(
	"shopkeeperIgnoresAttacks",
	function() end,
	{ "up", "up", "left", "left", "up", "up", "up", "up", "right", "right", "right", "right", "right", "idle", "idle" },
	{
		[9] = function()
			assertAt(player(), -10, -5, "beside the shopkeeper")
		end,
		[15] = function(shop)
			assertAt(player(), -10, -5, "the attacks did not move the player")
			assert(shop.keeper.health.health == 9, "the shopkeeper took nothing")
			assert(not shop.keeper.provokable.active, "and is not provoked")
			assertAt(shop.keeper, -9, -5, "and stays at his counter")
			assert(health() == 300, "the player took nothing")
		end,
	}
)

-- Digging through the shop's wall does not provoke him.
shopScene("shopWallDigDoesNotProvoke", function()
	Inventory.grant("ShovelGlass", player())
end, { "idle", "right", "up", "up", "up", "idle", "idle" }, {
	[3] = function()
		assert(fixtures.tileName(-8, 0) == "Floor", "the shop wall is dug")
	end,
	[7] = function(shop)
		assert(not shop.keeper.provokable.active, "the shopkeeper is not provoked")
		assertAt(shop.keeper, -9, -5, "and stays at his counter")
	end,
})

-- A bomb that hurts him provokes him. He then chases and hits for 20 every
-- second beat; a dagger takes 1 per hit; dead, he drops his Crown of Greed and
-- the wares left are free.
local fightRoute = {}
for _, a in ipairs(TO_BOMB) do
	fightRoute[#fightRoute + 1] = a
end
for _, a in ipairs(fights(20)) do
	fightRoute[#fightRoute + 1] = a
end
local afterFight = #fightRoute
for _, a in ipairs({ "right", "right", "right", "up", "up" }) do
	fightRoute[#fightRoute + 1] = a
end

shopScene("shopkeeperProvokedByBomb", function(shop)
	Inventory.grant("Bomb", player())
	assert(shop.keeper.health.health == 9, "the shopkeeper has 9 health")
end, fightRoute, {
	[#TO_BOMB] = function(shop)
		assert(shop.keeper.provokable.active, "the bomb provoked him")
		assert(shop.keeper.health.health == 5, "the bomb took 4 of his 9")
	end,
	[afterFight] = function(shop)
		assert(not Entities.entityExists(shop.keeper.id), "the shopkeeper died")
		local hits, lastHit = 0, nil
		for index, turn in ipairs(shop.log) do
			if turn.attacked then
				assert(turn.keeperDamage == 1, "a dagger hit takes 1, took " .. turn.keeperDamage)
			end
			if turn.playerDamage > 0 then
				assert(turn.playerDamage == 20, "he hits for 20, hit " .. turn.playerDamage)
				assert(not lastHit or index - lastHit == 2, "a hit every second beat")
				hits, lastHit = hits + 1, index
			end
		end
		assert(hits >= 2, "he hit more than once, hit " .. hits)
		local last = shop.log[#shop.log]
		local crown
		for entity in Entities.entitiesWithComponents({ "item" }) do
			if entity.name == "HeadCrownOfGreed" and entity.position then
				crown = entity
			end
		end
		assert(crown, "he dropped his Crown of Greed")
		assertAt(crown, last.keeperX, last.keeperY, "where he died")
		assert(not priceTag(shop.wares[3]).priceTag.active, "the last ware is free")
	end,
	[afterFight + 5] = function(shop)
		assertAt(player(), -8, -3, "on the last ware's tile")
		assert(gold() == 0, "nothing paid")
		local head = Inventory.getItemInSlot(player(), "head")
		assert(head and head.id == shop.wares[3].id, "holding the ware")
	end,
})

-- Provoked, he follows the player out of the shop, and the wares are free
-- while he is outside it.
local leaveRoute = {}
for _, a in ipairs(TO_BOMB) do
	leaveRoute[#leaveRoute + 1] = a
end
for _, a in ipairs({ "right", "right", "down", "down", "right", "right", "right", "right", "right", "right" }) do
	leaveRoute[#leaveRoute + 1] = a
end
local leaveChecks = {}
for step = #TO_BOMB, #leaveRoute do
	leaveChecks[step] = function(shop)
		local outside = shop.keeper.position.y >= 1
		local free = not priceTag(shop.wares[3]).priceTag.active
		assert(free == outside, string.format("step %d: keeper outside=%s, ware free=%s", step, outside, free))
		if step == #leaveRoute then
			assert(outside, "he followed the player out")
		end
	end
end
shopScene("shopWaresFreeWhileKeeperOutside", function()
	Inventory.grant("Bomb", player())
end, leaveRoute, leaveChecks)
