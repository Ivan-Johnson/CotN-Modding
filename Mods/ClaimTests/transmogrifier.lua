local Currency = require "necro.game.item.Currency"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local ItemBan = require "necro.game.item.ItemBan"
local Move = require "necro.game.system.Move"
local Object = require "necro.game.object.Object"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

local player = fixtures.player

local function gold()
	return Currency.get(player(), Currency.Type.GOLD)
end

-- The fixed seed does not fix the level's secret room: the run's random seed
-- picks it, if any. So a test restarts the run with the Transmogrifier's room
-- forced onto the first floor.
local forcing = false
event.levelSequenceUpdate.add("ClaimTestsTransmogrifierForce", { order = "secretRooms", sequence = 10 }, function(ev)
	if forcing then
		for index, level in ipairs(ev.sequence) do
			level.secretRoom = index == 1 and "TravelRune1" or nil
		end
	end
end)

local function findKeeper()
	for entity in Entities.entitiesWithComponents({ "secretShopkeeper" }) do
		if entity.name == "Transmogrifier" then
			return entity
		end
	end
end

-- Restarts the run (in the given zone, default 1) with the room on the first
-- floor, then calls andThen(keeper).
local function withRoom(zone, andThen)
	forcing = true
	-- GameSession.start is ignored while the framework's level load runs.
	testsApi.afterTicks(5, function()
		GameSession.start({ mode = GameSession.Mode.SingleZone, zone = zone })
	end)
	local tries = 0
	local function poll()
		tries = tries + 1
		local keeper = findKeeper()
		if keeper and player() then
			forcing = false
			player().health.maxHealth = 300
			player().health.health = 300
			andThen(keeper)
		else
			assert(tries < 60, "the Transmogrifier's room was generated")
			testsApi.afterTicks(100, poll)
		end
	end
	testsApi.afterTicks(100, poll)
end

local function cost(keeper)
	return keeper.priceTagCostCurrency.cost
end

local function priced(item)
	return item.sale ~= nil and item.sale.priceTag ~= 0
end

-- Loose items on the tile.
local function itemsAt(x, y)
	local list = {}
	for entity in Entities.entitiesWithComponents({ "item" }) do
		local p = entity.position
		if p and p.x == x and p.y == y and entity.item.holder == 0 then
			list[#list + 1] = entity
		end
	end
	return list
end

-- Each slot's tile, relative to the Transmogrifier, and where a player steps
-- onto it from: the row above him from above, his row from the side, the row
-- below from below.
local TILES = {
	{ slot = "head", x = -1, y = -1, from = { -1, -2, "down" }, item = "HeadMinersCap" },
	{ slot = "shield", x = 0, y = -1, from = { 0, -2, "down" }, item = "Sync_ShieldHeavy" },
	{ slot = "ring", x = 1, y = -1, from = { 1, -2, "down" }, item = "RingCourage" },
	{ slot = "body", x = -1, y = 0, from = { -2, 0, "right" }, item = "ArmorLeather" },
	{ slot = "shovel", x = 1, y = 0, from = { 2, 0, "left" }, item = "ShovelBasic" },
	{ slot = "feet", x = -1, y = 1, from = { -1, 2, "up" }, item = "FeetBootsExplorers" },
	{ slot = "torch", x = 0, y = 1, from = { 0, 2, "up" }, item = "Torch1" },
	{ slot = "weapon", x = 1, y = 1, from = { 1, 2, "up" }, item = "WeaponDagger" },
}
local TILE_OF = {}
for _, tile in ipairs(TILES) do
	TILE_OF[tile.slot] = tile
end

-- The new item lands here, between his torch tile and the rune; the player
-- lands on the rune.
local DROP = { 0, 2 }
local RUNE = { 0, 3 }

-- Teleports the player to the tile's approach, sets their gold, and steps
-- onto the tile; calls andThen(before) with the state before the step.
local function stepOnto(keeper, slot, goldAmount, andThen)
	local kx, ky = keeper.position.x, keeper.position.y
	local from = TILE_OF[slot].from
	for _, item in ipairs(itemsAt(kx + DROP[1], ky + DROP[2])) do
		Object.delete(item)
	end
	Move.absolute(player(), kx + from[1], ky + from[2], Move.Type.TELEPORT)
	Currency.set(player(), Currency.Type.GOLD, goldAmount)
	local held = Inventory.getItemInSlot(player(), slot)
	local before = {
		gold = goldAmount,
		cost = cost(keeper),
		held = held and held.name,
		x = kx + from[1],
		y = ky + from[2],
	}
	testsApi.play({ from[3] }, nil, function()
		andThen(before)
	end)
end

-- A successful transmogrification: the price paid, the slot emptied, a
-- different free item for that slot left on the drop tile, the player on the
-- rune, and the price doubled. Returns the new item.
local function assertTransmogrified(keeper, slot, before)
	local kx, ky = keeper.position.x, keeper.position.y
	fixtures.assertAt(player(), kx + RUNE[1], ky + RUNE[2], slot .. ": the player lands on the rune")
	assert(gold() == before.gold - before.cost, slot .. ": paid " .. before.cost .. ", gold left " .. gold())
	assert(Inventory.getItemInSlot(player(), slot) == nil, slot .. ": the slot is emptied")
	local dropped = itemsAt(kx + DROP[1], ky + DROP[2])
	assert(#dropped == 1, slot .. ": one new item on the drop tile, got " .. #dropped)
	local new = dropped[1]
	assert(new.itemSlot and new.itemSlot.name == slot, slot .. ": the new item is for the same slot, got " .. new.name)
	assert(new.name ~= before.held, slot .. ": the new item differs from " .. before.held)
	assert(not priced(new), slot .. ": the new item is free")
	assert(cost(keeper) == before.cost * 2, slot .. ": the price doubles, got " .. cost(keeper))
	return new
end

-- The room: a floor 5 wide and 8 tall walled in shop wall, the Transmogrifier
-- on its middle column, 3 rows down, ringed by his eight slot tiles, and the
-- rune 3 tiles below him, which leads to a cracked stone wall in the level. His label states his price.
testsApi.registerTest({
	name = "transmogrifierRoomLayout",
	async = true,
	noBeat = true,
	onLoad = function(_, finish)
		withRoom(nil, function(keeper)
			local kx, ky = keeper.position.x, keeper.position.y
			for dy = -4, 5 do
				for dx = -3, 3 do
					local tile = fixtures.tileName(kx + dx, ky + dy)
					local edge = math.abs(dx) == 3 or dy == -4 or dy == 5
					local want = edge and "ShopWall" or "Floor"
					assert(tile == want, string.format("%s at (%d,%d), got %s", want, dx, dy, tile))
				end
			end
			local tiles = 0
			for entity in Entities.entitiesWithComponents({ "trapTransaction" }) do
				local spec = TILE_OF[entity.trapTransaction.slot]
				assert(spec, "a tile for a known slot: " .. entity.trapTransaction.slot)
				fixtures.assertAt(entity, kx + spec.x, ky + spec.y, spec.slot .. " tile")
				tiles = tiles + 1
			end
			assert(tiles == 8, "eight slot tiles, got " .. tiles)
			local inner, outer
			for entity in Entities.entitiesWithComponents({ "trapTravel" }) do
				if entity.name == "TravelRune1" then
					if fixtures.tileName(entity.position.x, entity.position.y) == "Floor" then
						inner = entity
					else
						outer = entity
					end
				end
			end
			assert(inner and outer, "a rune inside the room and one in the level")
			fixtures.assertAt(inner, kx + RUNE[1], ky + RUNE[2], "the room's rune")
			local outerTile = fixtures.tileName(outer.position.x, outer.position.y)
			assert(outerTile == "StoneWallCracked", "the level's rune is in a cracked stone wall, got " .. outerTile)
			local label = keeper.secretShopLabel.text
			assert(label:find("Transmogrify one of your items?", 1, true), "label: " .. label)
			assert(label:find("Cost: %d coins", 1, true), "the label shows the price: " .. label)
			finish()
		end)
	end,
})

-- Every slot's tile swaps the item in that slot for a new one; the price
-- starts at 10 and doubles after each use, whichever tile.
testsApi.registerTest({
	name = "transmogrifierEverySlot",
	async = true,
	noBeat = true,
	onLoad = function(_, finish)
		withRoom(nil, function(keeper)
			assert(cost(keeper) == 10, "the first use costs 10, got " .. cost(keeper))
			local index = 0
			local function nextSlot()
				index = index + 1
				local tile = TILES[index]
				if not tile then
					finish()
					return
				end
				if not Inventory.getItemInSlot(player(), tile.slot) then
					Inventory.grant(tile.item, player())
				end
				stepOnto(keeper, tile.slot, 1000000, function(before)
					assertTransmogrified(keeper, tile.slot, before)
					nextSlot()
				end)
			end
			nextSlot()
		end)
	end,
})

-- Exactly the price is enough; one gold short, or with nothing in the slot,
-- the step fails and nothing is spent.
testsApi.registerTest({
	name = "transmogrifierNeedsPriceAndItem",
	async = true,
	noBeat = true,
	onLoad = function(_, finish)
		withRoom(nil, function(keeper)
			stepOnto(keeper, "weapon", cost(keeper) - 1, function(short)
				fixtures.assertAt(player(), short.x, short.y, "one gold short: the step fails")
				assert(gold() == short.gold, "one gold short: nothing spent")
				assert(Inventory.getItemInSlot(player(), "weapon").name == "WeaponDagger", "one gold short: dagger kept")
				assert(cost(keeper) == short.cost, "one gold short: the price stays")
				assert(Inventory.getItemInSlot(player(), "body") == nil, "Cadence starts without body armor")
				stepOnto(keeper, "body", 1000, function(empty)
					fixtures.assertAt(player(), empty.x, empty.y, "empty slot: the step fails")
					assert(gold() == 1000, "empty slot: nothing spent")
					assert(cost(keeper) == empty.cost, "empty slot: the price stays")
					stepOnto(keeper, "weapon", cost(keeper), function(exact)
						assertTransmogrified(keeper, "weapon", exact)
						assert(gold() == 0, "exactly the price: gold left 0")
						finish()
					end)
				end)
			end)
		end)
	end,
})

-- The new item is never the starting Dagger or Shovel.
testsApi.registerTest({
	name = "transmogrifierNeverGivesStartingKit",
	async = true,
	noBeat = true,
	timeoutTicks = 40000,
	onLoad = function(_, finish)
		withRoom(nil, function(keeper)
			local trial = 0
			local function nextTrial()
				trial = trial + 1
				if trial > 15 then
					finish()
					return
				end
				local slot = trial % 3 == 0 and "shovel" or "weapon"
				local starting = slot == "shovel" and "ShovelBasic" or "WeaponDagger"
				if not Inventory.getItemInSlot(player(), slot) then
					Inventory.grant(starting, player())
				end
				assert(Inventory.getItemInSlot(player(), slot).name == starting, "holding " .. starting)
				stepOnto(keeper, slot, cost(keeper), function(before)
					local new = assertTransmogrified(keeper, slot, before)
					assert(new.name ~= starting, "trial " .. trial .. " gave back " .. starting)
					nextTrial()
				end)
			end
			nextTrial()
		end)
	end,
})

-- The first use costs 10 on the first floor of every zone.
for zone = 1, 5 do
	testsApi.registerTest({
		name = "transmogrifierPriceZone" .. zone,
		async = true,
		noBeat = true,
		onLoad = function(_, finish)
			withRoom(zone, function(keeper)
				stepOnto(keeper, "weapon", 1000, function(before)
					assert(before.cost == 10, "zone " .. zone .. ": the first use costs 10, got " .. before.cost)
					assertTransmogrified(keeper, "weapon", before)
					finish()
				end)
			end)
		end,
	})
end

-- His tiles keep the player two tiles away: a spear's reach and a bomb set off
-- below his tiles leave him unhurt and unprovoked.
testsApi.registerTest({
	name = "transmogrifierOutOfReach",
	async = true,
	noBeat = true,
	onLoad = function(_, finish)
		withRoom(nil, function(keeper)
			local kx, ky = keeper.position.x, keeper.position.y
			Inventory.grant("WeaponSpear", player())
			Inventory.grant("Bomb", player())
			Move.absolute(player(), kx, ky + 2, Move.Type.TELEPORT)
			Currency.set(player(), Currency.Type.GOLD, 1000)
			testsApi.play({ "up", "bomb", "idle", "idle", "idle", "idle" }, nil, function()
				assert(Entities.entityExists(keeper.id), "he survives")
				assert(keeper.health.health == keeper.health.maxHealth, "he is unhurt")
				assert(not keeper.provokable.active, "he is not provoked")
				finish()
			end)
		end)
	end,
})

-- He accepts every item Cadence can carry in his eight slots.
testsApi.registerTest({
	name = "transmogrifierAcceptsEveryItem",
	onLoad = function()
		local checked = 0
		for _, typeName in ipairs(Entities.getEntityTypesWithComponents({ "itemSlot" })) do
			local prototype = Entities.getEntityPrototype(typeName)
			if TILE_OF[prototype.itemSlot.name] then
				checked = checked + 1
				local banned = ItemBan.isBanned(player(), prototype, ItemBan.Flag.CONVERT_TRANSACTION)
				assert(not banned, typeName .. " is refused")
			end
		end
		assert(checked > 100, "checked the slot items, got " .. checked)
	end,
})
