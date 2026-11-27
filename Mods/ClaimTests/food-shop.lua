local CurrentLevel = require "necro.game.level.CurrentLevel"
local Currency = require "necro.game.item.Currency"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Move = require "necro.game.system.Move"
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

-- The fixed seed does not fix the level's secret room: the run's random seed
-- picks it, if any. So a test restarts the run with the first level's secret
-- room set to the food shop (TravelRune5) in the level sequence, after the
-- game has picked its own.
local forceFood = false
event.levelSequenceUpdate.add("ClaimTestsFoodShopForce", { order = "secretRooms", sequence = 10 }, function(ev)
	if forceFood and ev.sequence[1] then
		ev.sequence[1].secretRoom = "TravelRune5"
	end
end)

local FOODS = {
	Food1 = { "Apple", 10 },
	Food2 = { "Cheese", 25 },
	Food3 = { "Drumstick", 40 },
	Food4 = { "Ham", 65 },
	FoodCarrot = { "Carrot", 20 },
	FoodCookies = { "Cookies", 50 },
}

-- Name, price, and the max health and health each adds.
local HEARTS = {
	MiscHeartContainer = { "Heart Container", 50, 2, 2 },
	MiscHeartContainer2 = { "Double Heart Container", 200, 4, 4 },
	MiscHeartContainerEmpty = { "Empty Heart Container", 25, 2, 0 },
	MiscHeartContainerEmpty2 = { "Empty Double Heart Container", 100, 4, 0 },
}

local function priceTag(ware)
	return ware.sale.priceTag ~= 0 and Entities.getEntityByID(ware.sale.priceTag) or nil
end

local function forSale(ware)
	local tag = priceTag(ware)
	return tag ~= nil and tag.priceTag.active
end

local function cost(ware)
	return priceTag(ware).priceTagCostCurrency.cost
end

local function gold()
	return Currency.get(player(), Currency.Type.GOLD)
end

local function holds(item)
	return Entities.entityExists(item.id) and item.item.holder == player().id
end

local function findKeeper()
	for entity in Entities.entitiesWithComponents({ "shopkeeper" }) do
		if entity.name == "Shopkeeper4" then
			return entity
		end
	end
end

local function wareAt(x, y)
	for entity in Entities.entitiesWithComponents({ "sale" }) do
		if entity.item and entity.position.x == x and entity.position.y == y then
			return entity
		end
	end
end

-- The lit bombs within radius tiles of (x, y), diagonals included.
local function litBombsNear(x, y, radius)
	local found = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local p = entity.position
		if entity.name == "BombLit" and math.abs(p.x - x) <= radius and math.abs(p.y - y) <= radius then
			found[#found + 1] = entity
		end
	end
	return found
end

-- Restarts the run with the food shop forced, then calls andThen with the
-- shop: its keeper, his tile (kx, ky), and his two wares.
local function withFoodShop(andThen)
	forceFood = true
	local function wait()
		local keeper = not CurrentLevel.isLoading() and findKeeper()
		if not keeper then
			testsApi.afterTicks(10, wait)
			return
		end
		forceFood = false
		testsApi.afterTicks(100, function()
			local kx, ky = keeper.position.x, keeper.position.y
			andThen({
				keeper = keeper,
				kx = kx,
				ky = ky,
				food = wareAt(kx - 1, ky + 2),
				heart = wareAt(kx + 1, ky + 2),
			})
		end)
	end
	testsApi.afterTicks(10, function()
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		testsApi.afterTicks(50, wait)
	end)
end

-- Each zone's first floor, with the food shop forced: a room of 7 by 9 floor
-- walled with shop wall, the Food Shopkeeper with 1 health, food two tiles
-- in front of him on the left and a heart container on the right, each
-- priced in gold at its usual price, and the way back 4 tiles in front of him.
for zone = 1, 5 do
	testsApi.registerTest({
		name = "foodShopRoomZone" .. zone,
		zone = zone,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withFoodShop(function(shop)
				local keeper = shop.keeper
				assert(keeper.health.health == 1 and keeper.health.maxHealth == 1, "he has 1 health")
				assert(shop.food and FOODS[shop.food.name], "food on the left, got " .. tostring(shop.food and shop.food.name))
				assert(shop.heart and HEARTS[shop.heart.name], "a heart container on the right")
				assert(cost(shop.food) == FOODS[shop.food.name][2], shop.food.name .. " costs " .. cost(shop.food))
				assert(cost(shop.heart) == HEARTS[shop.heart.name][2], shop.heart.name .. " costs " .. cost(shop.heart))
				local rune
				for entity in Entities.entitiesWithComponents({ "position" }) do
					if entity.name == "TravelRune5" and entity.position.y == shop.ky + 4 then
						rune = entity
					end
				end
				assert(rune, "a travel rune 4 tiles in front of him")
				assertAt(rune, shop.kx, shop.ky + 4, "the way back")
				for dy = -3, 7 do
					for dx = -4, 4 do
						local x, y = shop.kx + dx, shop.ky + dy
						local where = string.format("(%d,%d)", dx, dy)
						if math.abs(dx) == 4 or dy == -3 or dy == 7 then
							assert(fixtures.tileName(x, y) == "ShopWall", "shop wall at " .. where)
						else
							assert(not Tile.isSolid(x, y), "floor at " .. where)
						end
					end
				end
				finish()
			end)
		end,
	})
end

-- The food is one of the six ordinary foods and the heart container one of
-- four kinds, each at its usual price.
testsApi.registerTest({
	name = "foodShopPools",
	onLoad = function()
		for pool, items in pairs({ itemPoolFood = FOODS, itemPoolHearts = HEARTS }) do
			local seen = 0
			for _, typeName in ipairs(Entities.getEntityTypesWithComponents({ pool })) do
				local item = items[typeName]
				assert(item, typeName .. " is in " .. pool)
				local proto = Entities.getEntityPrototype(typeName)
				assert(proto.friendlyName.name == item[1], typeName .. " is " .. proto.friendlyName.name)
				assert(proto.itemPrice.coins == item[2], typeName .. " costs " .. proto.itemPrice.coins)
				seen = seen + 1
			end
			local expected = 0
			for _ in pairs(items) do
				expected = expected + 1
			end
			assert(seen == expected, pool .. " holds " .. seen)
		end
	end,
})

-- Each heart container's effect on max health and health.
testsApi.registerTest({
	name = "foodShopHeartContainers",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		fixtures.openArena(10)
		player().health.health = 4
		player().health.maxHealth = 6
		local order = { "MiscHeartContainer", "MiscHeartContainer2", "MiscHeartContainerEmpty", "MiscHeartContainerEmpty2" }
		for index, typeName in ipairs(order) do
			fixtures.spawn(typeName, index * 2, 0)
		end
		local before = { health(), player().health.maxHealth }
		testsApi.play(fixtures.repeated("right", 8), function(index)
			if index % 2 == 0 then
				local item = HEARTS[order[index / 2]]
				local now = { health(), player().health.maxHealth }
				local what = order[index / 2]
				assert(now[2] - before[2] == item[3], what .. " adds " .. (now[2] - before[2]) .. " max health")
				assert(now[1] - before[1] == item[4], what .. " adds " .. (now[1] - before[1]) .. " health")
				before = now
			end
		end, finish)
	end,
})

-- prepare(shop) returns the player's tile relative to the shopkeeper; checks[i](shop)
-- runs after action i. The player starts with 6 health and no gold.
local function shopScene(name, prepare, actions, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withFoodShop(function(shop)
				player().health.health = 6
				player().health.maxHealth = 6
				Currency.set(player(), Currency.Type.GOLD, 0)
				local dx, dy = prepare(shop)
				Move.absolute(player(), shop.kx + dx, shop.ky + dy, Move.Type.TELEPORT)
				testsApi.afterTicks(30, function()
					testsApi.play(actions, function(index)
						if checks[index] then
							checks[index](shop)
						end
					end, finish)
				end)
			end)
		end,
	})
end

-- Buying works as in the regular shop: food goes into the inventory.
shopScene("foodShopBuyFood", function(shop)
	Currency.set(player(), Currency.Type.GOLD, cost(shop.food))
	return -1, 3
end, { "up" }, {
	[1] = function(shop)
		assertAt(player(), shop.kx - 1, shop.ky + 2, "on the food's tile")
		assert(gold() == 0, "the price is spent, left " .. gold())
		assert(holds(shop.food), "holding the food")
	end,
})

-- A heart container takes effect at once.
shopScene("foodShopBuyHeart", function(shop)
	Currency.set(player(), Currency.Type.GOLD, cost(shop.heart))
	return 1, 3
end, { "up" }, {
	[1] = function(shop)
		local item = HEARTS[shop.heart.name]
		assert(gold() == 0, "the price is spent, left " .. gold())
		assert(player().health.maxHealth == 6 + item[3], "max health " .. player().health.maxHealth)
		assert(health() == 6 + item[4], "health " .. health())
	end,
})

shopScene("foodShopTooLittleGold", function(shop)
	Currency.set(player(), Currency.Type.GOLD, cost(shop.heart) - 1)
	return 1, 3
end, { "up" }, {
	[1] = function(shop)
		assertAt(player(), shop.kx + 1, shop.ky + 3, "stopped in front of the ware")
		assert(gold() == cost(shop.heart) - 1, "no gold spent")
		assert(forSale(shop.heart), "still for sale")
	end,
})

-- Unprovoked, the weapon cannot hurt him and he never attacks.
shopScene("foodShopKeeperIgnoresAttacks", function()
	return -1, 0
end, { "right", "right", "right", "idle", "idle", "idle" }, {
	[6] = function(shop)
		assertAt(player(), shop.kx - 1, shop.ky, "the attacks did not move the player")
		assert(shop.keeper.health.health == 1, "he took nothing")
		assert(not shop.keeper.provokable.active, "he is not provoked")
		assertAt(shop.keeper, shop.kx, shop.ky, "he stays put")
		assert(health() == 6, "the player took nothing")
	end,
})

-- A bomb whose blast misses him leaves him alone.
shopScene("foodShopBombMissLeavesHimAlone", function()
	Inventory.grant("Bomb", player())
	return 3, 6
end, { "bomb", "up", "up", "up", "idle", "idle" }, {
	[6] = function(shop)
		assert(Entities.entityExists(shop.keeper.id), "he is alive")
		assert(not shop.keeper.provokable.active, "and not provoked")
		assert(forSale(shop.food) and forSale(shop.heart), "the wares are still for sale")
		assert(health() == 6, "the player took nothing")
	end,
})

-- A bomb that hurts him kills him: he leaves the Gluttony Charm where he
-- stood, the wares turn free, and one or two lit bombs land on or beside the
-- player and go off within two beats, taking 4 if the player stays.
-- Each case: the player's start, the moves after the bomb (the third is the
-- beat it goes off).
local BOMB_CASES = {
	{ -1, -1, { "left", "left", "idle" } },
	{ -1, -1, { "left", "left", "down" } },
	{ -1, -1, { "left", "left", "up" } },
	{ -1, -1, { "right", "right", "right" } },
	{ 1, -1, { "right", "right", "up" } },
	{ 1, 1, { "right", "right", "down" } },
	{ 0, 1, { "down", "down", "left" } },
}
for index, case in ipairs(BOMB_CASES) do
	local actions = { "bomb", case[3][1], case[3][2], case[3][3], "idle", "idle", "idle" }
	shopScene("foodShopBombKillsHim" .. index, function()
		Inventory.grant("Bomb", player())
		return case[1], case[2]
	end, actions, {
		[4] = function(shop)
			assert(not Entities.entityExists(shop.keeper.id), "he died")
			local charm
			for entity in Entities.entitiesWithComponents({ "item" }) do
				if entity.name == "CharmGluttony" and entity.position then
					charm = entity
				end
			end
			assert(charm, "he dropped the Gluttony Charm")
			assertAt(charm, shop.kx, shop.ky, "where he stood")
			for _, ware in ipairs({ shop.food, shop.heart }) do
				assert(not Entities.entityExists(ware.id) or not forSale(ware), ware.name .. " is free")
			end
			local p = player().position
			local near = #litBombsNear(p.x, p.y, 1)
			local all = #litBombsNear(p.x, p.y, 100)
			assert(near >= 1 and near <= 2, "one or two bombs by the player, got " .. near)
			assert(all == near, "no bomb elsewhere, " .. all .. " in all")
		end,
		[6] = function()
			local p = player().position
			assert(#litBombsNear(p.x, p.y, 100) == 0, "the bombs went off within two beats")
			assert(health() == 2, "they took 4, left " .. health())
		end,
	})
end

-- Free after his death: walking onto a ware takes it without gold.
shopScene("foodShopWaresFreeAfterDeath", function()
	Inventory.grant("Bomb", player())
	return -1, -1
end, { "bomb", "left", "left", "down", "idle", "right", "right", "down", "down" }, {
	[9] = function(shop)
		assertAt(player(), shop.kx - 1, shop.ky + 2, "on the food's tile")
		assert(holds(shop.food), "holding the food, for no gold")
	end,
})

-- Stepping away from his bomb on the next beat is enough.
shopScene("foodShopBombCanBeEscaped", function()
	Inventory.grant("Bomb", player())
	return 1, 1
end, { "bomb", "right", "right", "down", "up", "idle", "idle" }, {
	[4] = function()
		local p = player().position
		assert(#litBombsNear(p.x, p.y, 0) == 0 and #litBombsNear(p.x, p.y, 1) == 1, "one bomb beside the player")
	end,
	[7] = function()
		assert(health() == 6, "stepping away dodged it, left " .. health())
	end,
})
