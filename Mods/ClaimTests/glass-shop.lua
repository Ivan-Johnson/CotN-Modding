local Action = require "necro.game.system.Action"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Currency = require "necro.game.item.Currency"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Input = require "necro.client.Input"
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
-- picks it, and sometimes picks the glass shop. So a test restarts the run
-- with the first level's secret room set to the glass shop (TravelRune4), in
-- the level sequence and in the level's options. Only these tests set
-- forceGlass, and each clears it once the shop has loaded.
local forceGlass = false
event.levelSequenceUpdate.add("ClaimTestsGlassShopForce", { order = "secretRooms", sequence = 10 }, function(ev)
	if forceGlass and ev.sequence[1] then
		ev.sequence[1].secretRoom = "TravelRune4"
	end
end)
event.levelGenerate.add("ClaimTestsGlassShopForceOptions", { sequence = 5 }, function(ev)
	if forceGlass and ev.options and ev.options.number == 1 then
		ev.options.secretRoom = "TravelRune4"
	end
end)

local function findKeeper(typeName)
	for entity in Entities.entitiesWithComponents({ "shopkeeper" }) do
		if entity.name == typeName then
			return entity
		end
	end
end

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

local function wareAt(x, y)
	for entity in Entities.entitiesWithComponents({ "sale" }) do
		if entity.item and entity.position.x == x and entity.position.y == y then
			return entity
		end
	end
end

-- The first entity named typeName on tile (x, y) that nobody holds.
local function lyingAt(typeName, x, y)
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local p = entity.position
		local held = entity.item and entity.item.holder ~= 0
		if entity.name == typeName and p.x == x and p.y == y and not held then
			return entity
		end
	end
end

-- Restarts the run with the glass shop forced, then calls andThen with the
-- shop: its keeper, his tile (kx, ky), and his wares from left to right.
local function withGlassShop(andThen)
	forceGlass = true
	local function wait()
		local keeper = not CurrentLevel.isLoading() and findKeeper("Shopkeeper3")
		if not keeper then
			testsApi.afterTicks(10, wait)
			return
		end
		forceGlass = false
		testsApi.afterTicks(100, function()
			local kx, ky = keeper.position.x, keeper.position.y
			andThen({
				keeper = keeper,
				kx = kx,
				ky = ky,
				wares = { wareAt(kx - 1, ky + 2), wareAt(kx, ky + 2), wareAt(kx + 1, ky + 2) },
			})
		end)
	end
	testsApi.afterTicks(10, function()
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		testsApi.afterTicks(50, wait)
	end)
end

-- Each zone's first floor, with the glass shop forced: 5 by 7 tiles of floor
-- walled with shop wall, the Glass Shopkeeper with 8 health one tile from the
-- back wall, three glass wares two tiles in front of him, each priced in gold
-- at half its regular price rounded up, and the way back 4 tiles in front of
-- him.
for zone = 1, 5 do
	testsApi.registerTest({
		name = "glassShopRoomZone" .. zone,
		zone = zone,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withGlassShop(function(shop)
				local keeper = shop.keeper
				assert(keeper.friendlyName.name == "Glass Shopkeeper", "he is the Glass Shopkeeper")
				assert(keeper.health.health == 8 and keeper.health.maxHealth == 8, "he has 8 health")
				for slot, ware in ipairs(shop.wares) do
					local name = ware.friendlyName.name
					assert(name:find("^Glass "), "ware " .. slot .. " is glass, got " .. name)
					local half = math.ceil(ware.itemPrice.coins / 2)
					local what = string.format("%s costs %d, half of %d", name, cost(ware), ware.itemPrice.coins)
					assert(cost(ware) == half, what)
				end
				assert(lyingAt("TravelRune4", shop.kx, shop.ky + 4), "a travel rune 4 tiles in front of him")
				for dy = -2, 6 do
					for dx = -3, 3 do
						local x, y = shop.kx + dx, shop.ky + dy
						local where = string.format("(%d,%d)", dx, dy)
						if math.abs(dx) == 3 or dy == -2 or dy == 6 then
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

-- The regular shop charges an item's full price, which the glass shop halves.
-- Its three wares lie two tiles in front of its shopkeeper; the level's secret
-- room, whichever one the run picked, may hold wares of its own.
testsApi.registerTest({
	name = "glassShopRegularShopFullPrice",
	onLoad = function()
		local keeper = assert(findKeeper("Shopkeeper"), "the level has a regular shop")
		local kx, ky = keeper.position.x, keeper.position.y
		for dx = -1, 1 do
			local ware = assert(wareAt(kx + dx, ky + 2), "a ware at " .. dx .. ",2 from the shopkeeper")
			assert(cost(ware) == ware.itemPrice.coins, ware.name .. " at full price")
		end
	end,
})

-- prepare(shop) returns the player's tile relative to the shopkeeper;
-- checks[i](shop) runs after action i. The player starts with 6 health and no
-- gold.
local function shopScene(name, prepare, actions, checks)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withGlassShop(function(shop)
				player().health.health = 6
				player().health.maxHealth = 6
				Currency.set(player(), Currency.Type.GOLD, 0)
				local dx, dy = prepare(shop)
				Move.absolute(player(), shop.kx + dx, shop.ky + dy, Move.Type.TELEPORT)
				local list = {}
				for index, action in ipairs(actions) do
					list[index] = action
				end
				testsApi.afterTicks(30, function()
					testsApi.play(list, function(index)
						if checks[index] then
							checks[index](shop)
						end
					end, finish)
				end)
			end)
		end,
	})
end

-- Walking onto a ware with exactly its price buys it; the dagger it replaces
-- stays on the tile, free.
shopScene("glassShopBuyAtExactPrice", function(shop)
	Currency.set(player(), Currency.Type.GOLD, cost(shop.wares[3]))
	return 1, 3
end, { "up" }, {
	[1] = function(shop)
		assertAt(player(), shop.kx + 1, shop.ky + 2, "on the ware's tile")
		assert(gold() == 0, "the price is spent, left " .. gold())
		assert(holds(shop.wares[3]), "holding the ware")
		local old = lyingAt("WeaponDagger", shop.kx + 1, shop.ky + 2)
		assert(old and not priceTag(old), "the old dagger lies on the tile, free")
	end,
})

-- One gold short, the move fails and nothing is spent.
shopScene("glassShopTooLittleGold", function(shop)
	Currency.set(player(), Currency.Type.GOLD, cost(shop.wares[2]) - 1)
	return 0, 3
end, { "up" }, {
	[1] = function(shop)
		assertAt(player(), shop.kx, shop.ky + 3, "stopped in front of the ware")
		assert(gold() == cost(shop.wares[2]) - 1, "no gold spent")
		assert(forSale(shop.wares[2]), "still for sale")
	end,
})

-- Buys the ware in slot, walks up beside the shopkeeper, lights a bomb and
-- stays in its blast; check(shop) runs on the beat it goes off, which
-- provokes him and before he can hit.
local function bombedWithWare(name, slot, check)
	local done = false
	local actions = { "up", "up", "up", "bomb", "idle", "idle", "idle" }
	local checks = {}
	local function watch(shop)
		if shop.keeper.provokable.active and not done then
			done = true
			check(shop)
		end
	end
	for index = 4, #actions - 1 do
		checks[index] = watch
	end
	checks[#actions] = function(shop)
		watch(shop)
		assert(done, "the bomb went off")
	end
	shopScene(name, function(shop)
		done = false
		Currency.set(player(), Currency.Type.GOLD, cost(shop.wares[slot]))
		Inventory.grant("Bomb", player())
		return slot - 2, 3
	end, actions, checks)
end

-- Glass armor takes the blast in your place and shatters.
bombedWithWare("glassShopGlassArmorShatters", 1, function(shop)
	assert(shop.wares[1].name == "ArmorGlass", "the left ware is Glass Armor here")
	assert(health() == 6, "the blast took nothing, left " .. health())
	assert(not holds(shop.wares[1]), "the armor is gone")
end)

-- Attacking an unprovoked shopkeeper does nothing, and he never attacks.
shopScene("glassShopKeeperIgnoresAttacks", function()
	return -1, 0
end, { "right", "right", "right", "idle", "idle" }, {
	[5] = function(shop)
		assertAt(player(), shop.kx - 1, shop.ky, "the attacks did not move the player")
		assert(shop.keeper.health.health == 8, "he took nothing")
		assert(not shop.keeper.provokable.active, "he is not provoked")
		assertAt(shop.keeper, shop.kx, shop.ky, "he stays put")
		assert(health() == 6, "the player took nothing")
	end,
})

-- A bomb that hurts him takes 4 and provokes him.
shopScene("glassShopKeeperBombed", function()
	Inventory.grant("Bomb", player())
	player().health.health = 300
	player().health.maxHealth = 300
	return -1, 0
end, { "bomb", "left", "left", "down" }, {
	[3] = function(shop)
		assert(not shop.keeper.provokable.active, "the bomb has not gone off yet")
	end,
	[4] = function(shop)
		assert(shop.keeper.provokable.active, "the bomb provoked him")
		assert(shop.keeper.health.health == 4, "the bomb took 4 of his 8, left " .. shop.keeper.health.health)
	end,
})

-- A thrown dagger provokes him and takes 1. He then hits for 20 every second
-- beat while beside the player, each dagger hit takes 1, and his wares keep
-- their price while he lives. Every tile but the middle column is dirt, so he
-- can only come at the player from the north; each hit sends him somewhere
-- else in the column, so the player waits as many beats as the room is long
-- before striking again.
local ROOM_LENGTH = 7
testsApi.registerTest({
	name = "glassShopKeeperProvoked",
	noBeat = true,
	async = true,
	timeoutTicks = 60000,
	onLoad = function(_, finish)
		withGlassShop(function(shop)
			local keeper = shop.keeper
			for dy = -1, 5 do
				for dx = -2, 2 do
					if dx ~= 0 then
						Tile.setType(shop.kx + dx, shop.ky + dy, "DirtWall")
					end
				end
			end
			player().health.maxHealth = 1000
			player().health.health = 1000
			Move.absolute(player(), shop.kx, shop.ky + 5, Move.Type.TELEPORT)
			-- He is beside the player only on the tile north of them.
			local function beside()
				return keeper.position.x == shop.kx and keeper.position.y == shop.ky + 4
			end
			local actions = {}
			for _ = 1, 3 do
				for _ = 1, ROOM_LENGTH do
					actions[#actions + 1] = "idle"
				end
				actions[#actions + 1] = "up"
			end
			-- What the previous action left: whether he was beside the
			-- player, both healths, and whether he hit on it.
			local wasBeside = false
			local playerHealth = 0
			local keeperHealth = 0
			local hitLast = false
			local function remember()
				wasBeside = beside()
				playerHealth = player().health.health
				keeperHealth = keeper.health.health
			end
			local function check(index)
				local action = actions[index]
				local where = "after action " .. index .. " (" .. action .. ")"
				assert(Entities.entityExists(keeper.id), "he is alive " .. where)
				for _, ware in ipairs(shop.wares) do
					assert(forSale(ware), ware.name .. " keeps its price " .. where)
				end
				local taken = playerHealth - player().health.health
				local hit = taken > 0
				if hit then
					assert(taken == 20, "he hits for 20, hit " .. taken .. " " .. where)
					assert(wasBeside, "he hits only from beside the player " .. where)
					assert(not hitLast, "he hits every second beat, not two in a row " .. where)
				elseif action == "idle" and wasBeside then
					assert(hitLast, "he hits every second beat while beside the player " .. where)
				end
				if action == "up" then
					assert(wasBeside, "he came back beside the player within " .. ROOM_LENGTH .. " beats")
					local struck = keeperHealth - keeper.health.health
					assert(struck == 1, "a dagger hit takes 1, took " .. struck .. " " .. where)
				end
				hitLast = hit and action == "idle"
				remember()
			end
			testsApi.afterTicks(30, function()
				Input.add(Action.Special.THROW, 1)
				testsApi.afterTicks(100, function()
					Input.add(Action.Direction.UP, 1)
					testsApi.afterTicks(300, function()
						assert(keeper.provokable.active, "the thrown dagger provoked him")
						assert(keeper.health.health == 7, "the thrown dagger took 1 of his 8")
						Inventory.grant("WeaponDagger", player())
						remember()
						testsApi.play(actions, check, finish)
					end)
				end)
			end)
		end)
	end,
})

-- Killed, he drops his Glass Jaw where he stood, and the wares turn free.
shopScene("glassShopKeeperDrops", function(shop)
	Inventory.grant("Bomb", player())
	shop.keeper.health.health = 4
	return -1, 0
end, { "bomb", "left", "left", "down", "idle", "idle" }, {
	[6] = function(shop)
		assert(not Entities.entityExists(shop.keeper.id), "he died")
		assert(lyingAt("HeadGlassJaw", shop.kx, shop.ky), "his Glass Jaw where he stood")
		for _, ware in ipairs(shop.wares) do
			assert(not forSale(ware), ware.name .. " is free")
		end
	end,
})
