local CurrentLevel = require "necro.game.level.CurrentLevel"
local Currency = require "necro.game.item.Currency"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Move = require "necro.game.system.Move"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test restarts the run with the first level's secret room forced to the
-- conjurer's (TravelRune6), then plays Cadence inside that room. Positions
-- are relative to the Conjurer; "up" is toward negative y. The conjured items
-- are random, so the tests check their slot and place, not the item.

local player = fixtures.player

local force = false
event.levelGenerate.add("ClaimTestsConjurerForce", { sequence = 7 }, function(ev)
	if force and ev.options and ev.options.type == "Necro" then
		ev.options.secretRoom = "TravelRune6"
	end
end)
event.levelSequenceUpdate.add("ClaimTestsConjurerForceSeq", { order = "secretRooms", sequence = 10 }, function(ev)
	if force then
		for index, level in ipairs(ev.sequence) do
			level.secretRoom = index == 1 and "TravelRune6" or nil
		end
	end
end)

local function findKeeper()
	for entity in Entities.entitiesWithComponents({ "secretShopkeeper" }) do
		if entity.name == "Conjurer" then
			return entity
		end
	end
end

-- Restarts the run until the level has the conjurer's room, then calls
-- andThen(keeper). A start issued while the framework's own run is still
-- loading can be lost, so it is retried.
local function withRoom(andThen)
	force = true
	local tries = 0
	local function wait()
		tries = tries + 1
		if CurrentLevel.isLoading() then
			testsApi.afterTicks(10, wait)
			return
		end
		local keeper = findKeeper()
		if not keeper then
			if tries % 50 == 0 then
				GameSession.start({ mode = GameSession.Mode.SingleZone })
			end
			if tries > 400 then
				force = false
				error("the level never got the conjurer's room")
			end
			testsApi.afterTicks(10, wait)
			return
		end
		force = false
		testsApi.afterTicks(100, function()
			andThen(keeper)
		end)
	end
	testsApi.afterTicks(10, function()
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		testsApi.afterTicks(50, wait)
	end)
end

local function gold()
	return Currency.get(player(), Currency.Type.GOLD)
end

-- Each tile's slot, its offset from the Conjurer, and where to stand and
-- which way to step onto it from outside the grid.
local TILES = {
	{ slot = "head", at = { 0, 2 }, from = { 0, 1 }, step = "down" },
	{ slot = "shield", at = { 1, 2 }, from = { 1, 1 }, step = "down" },
	{ slot = "ring", at = { 2, 2 }, from = { 2, 1 }, step = "down" },
	{ slot = "body", at = { 0, 3 }, from = { -1, 3 }, step = "right" },
	{ slot = "shovel", at = { 2, 3 }, from = { 3, 3 }, step = "left" },
	{ slot = "feet", at = { 0, 4 }, from = { -1, 4 }, step = "right" },
	{ slot = "torch", at = { 1, 4 }, from = { 1, 5 }, step = "up" },
	{ slot = "weapon", at = { 2, 4 }, from = { 3, 4 }, step = "left" },
}
local TORCH = TILES[7]

local RUNE = { 1, 6 }

local function itemIDs()
	local set = {}
	for entity in Entities.entitiesWithComponents({ "item" }) do
		set[entity.id] = true
	end
	return set
end

-- The item entities created since `before`.
local function newItems(before)
	local list = {}
	for entity in Entities.entitiesWithComponents({ "item" }) do
		if not before[entity.id] then
			list[#list + 1] = entity
		end
	end
	return list
end

local function relative(keeper, entity)
	return entity.position.x - keeper.position.x, entity.position.y - keeper.position.y
end

local function assertRel(keeper, entity, x, y, what)
	local rx, ry = relative(keeper, entity)
	assert(rx == x and ry == y, string.format("%s: expected (%d,%d), got (%d,%d)", what, x, y, rx, ry))
end

-- The unheld items lying on the tile at offset (x,y) from the Conjurer.
local function itemsAt(keeper, x, y)
	local list = {}
	for entity in Entities.entitiesWithComponents({ "item" }) do
		local rx, ry = relative(keeper, entity)
		if rx == x and ry == y and entity.item.holder == 0 then
			list[#list + 1] = entity
		end
	end
	return list
end

-- A no-beat test in the conjurer's room. Teleports Cadence to `from` (an
-- offset from the Conjurer) with `startGold`, idles once so the teleport
-- settles, then plays `actions`; checks[i](state) runs after action i.
local function roomScene(name, spec)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withRoom(function(keeper)
				local kx, ky = keeper.position.x, keeper.position.y
				Currency.set(player(), Currency.Type.GOLD, spec.gold)
				if spec.prepare then
					spec.prepare(keeper)
				end
				Move.absolute(player(), kx + spec.from[1], ky + spec.from[2], Move.Type.TELEPORT)
				local state = { keeper = keeper }
				local actions = { "idle" }
				for _, action in ipairs(spec.actions) do
					actions[#actions + 1] = action
				end
				testsApi.play(actions, function(index)
					if index == 1 then
						assertRel(keeper, player(), spec.from[1], spec.from[2], "teleported")
					end
					local check = spec.checks[index - 1]
					if check then
						check(state)
					end
					state.items = itemIDs()
					state.gold = gold()
				end, finish)
			end)
		end,
	})
end

-- The room: the Conjurer at the top of a shop-walled room, five tiles wide
-- and eight deep, closed off by the level border; a 3-by-3 grid of slot
-- tiles below him with a blocked centre; the travel rune at the bottom.
roomScene("conjurerRoomLayout", {
	gold = 0,
	from = RUNE,
	actions = {},
	checks = {
		[0] = function(state)
			local keeper = state.keeper
			local kx, ky = keeper.position.x, keeper.position.y
			for dy = -1, 8 do
				for dx = -2, 4 do
					local tile = fixtures.tileName(kx + dx, ky + dy)
					local edge = dx == -2 or dx == 4 or dy == -1 or dy == 8
					local want = edge and "ShopWall" or "Floor"
					assert(tile == want, string.format("(%d,%d) is %s, want %s", dx, dy, tile, want))
					if edge then
						local ox = dx == -2 and -1 or dx == 4 and 1 or 0
						local oy = dy == -1 and -1 or dy == 8 and 1 or 0
						local outside = fixtures.tileName(kx + dx + ox, ky + dy + oy)
						assert(outside == "LevelBorder", string.format("beyond (%d,%d) is %s", dx, dy, outside))
					end
				end
			end
			local seen = 0
			for entity in Entities.entitiesWithComponents({ "trapTransaction" }) do
				for _, tile in ipairs(TILES) do
					if tile.slot == entity.trapTransaction.slot then
						assertRel(keeper, entity, tile.at[1], tile.at[2], tile.slot .. " tile")
						seen = seen + 1
					end
				end
			end
			assert(seen == #TILES, "slot tiles: " .. seen)
			local runes = 0
			for entity in Entities.entitiesWithComponents({ "trapTravel" }) do
				local rx, ry = relative(keeper, entity)
				if rx == RUNE[1] and ry == RUNE[2] then
					runes = runes + 1
				end
			end
			assert(runes == 1, "a travel rune at the bottom")
		end,
	},
})

-- Stepping onto a tile with the price conjures a new item of that slot onto
-- the floor just above the rune, free, and puts you on the rune. Cadence
-- holds no torch, so the slot need not hold anything. The next step up picks
-- the item up.
roomScene("conjurerConjuresOntoFloor", {
	gold = 40,
	from = TORCH.from,
	actions = { TORCH.step, "idle", "up" },
	checks = {
		[1] = function(state)
			local keeper = state.keeper
			assert(gold() == 0, "40 gold spent, left " .. gold())
			assertRel(keeper, player(), RUNE[1], RUNE[2], "sent to the rune")
			assert(not Inventory.getItemInSlot(player(), "torch"), "nothing added to the torch slot")
			local made = newItems(state.items)
			assert(#made == 1, "one new item, got " .. #made)
			assert(made[1].itemSlot.name == "torch", "a torch, got " .. made[1].name)
			local lying = itemsAt(keeper, TORCH.from[1], TORCH.from[2])
			assert(#lying == 1 and lying[1].id == made[1].id, "it lies above the rune")
			assert(not (made[1].sale and made[1].sale.priceTag ~= 0), "it is free")
			state.made = made[1]
		end,
		[2] = function(state)
			assertRel(state.keeper, player(), RUNE[1], RUNE[2], "still on the rune")
		end,
		[3] = function(state)
			local torch = Inventory.getItemInSlot(player(), "torch")
			assert(torch and torch.id == state.made.id, "picked up the conjured torch")
		end,
	},
})

-- Each tile conjures its own slot. The price starts at 40 gold and doubles
-- after every purchase, across all the tiles.
testsApi.registerTest({
	name = "conjurerEachTileItsSlotPriceDoubles",
	noBeat = true,
	async = true,
	timeoutTicks = 30000,
	onLoad = function(_, finish)
		withRoom(function(keeper)
			local kx, ky = keeper.position.x, keeper.position.y
			Currency.set(player(), Currency.Type.GOLD, 40 * (2 ^ #TILES - 1))
			local index = 0
			local function nextTile()
				index = index + 1
				local tile = TILES[index]
				if not tile then
					assert(gold() == 0, "every tile used, gold left " .. gold())
					finish()
					return
				end
				Move.absolute(player(), kx + tile.from[1], ky + tile.from[2], Move.Type.TELEPORT)
				testsApi.play({ "idle" }, nil, function()
					assertRel(keeper, player(), tile.from[1], tile.from[2], "teleported")
					local state = { gold = gold(), items = itemIDs() }
					testsApi.play({ tile.step }, nil, function()
						local paid = state.gold - gold()
						local price = 40 * 2 ^ (index - 1)
						assert(paid == price, string.format("%s cost %d, want %d", tile.slot, paid, price))
						local made = newItems(state.items)
						assert(#made == 1, tile.slot .. ": one new item, got " .. #made)
						assert(made[1].itemSlot.name == tile.slot, tile.slot .. ": got " .. made[1].name)
						nextTile()
					end)
				end)
			end
			nextTile()
		end)
	end,
})

-- The item you hold in that slot stays yours: a conjured body armor lands on
-- the floor, and Cadence keeps her leather armor.
roomScene("conjurerKeepsYourItem", {
	gold = 40,
	from = TILES[4].from,
	prepare = function()
		Inventory.grant("ArmorLeather", player())
	end,
	actions = { TILES[4].step },
	checks = {
		[1] = function(state)
			assert(gold() == 0, "40 gold spent")
			local armor = Inventory.getItemInSlot(player(), "body")
			assert(armor and armor.name == "ArmorLeather", "still wearing leather armor")
			local made = newItems(state.items)
			assert(#made == 1 and made[1].itemSlot.name == "body", "a new body armor")
			assert(made[1].item.holder == 0, "lying on the floor")
		end,
	},
})

-- One gold short, the step fails: Cadence stays put and nothing is spent.
roomScene("conjurerTooLittleGoldBlocks", {
	gold = 39,
	from = TORCH.from,
	actions = { TORCH.step },
	checks = {
		[1] = function(state)
			assertRel(state.keeper, player(), TORCH.from[1], TORCH.from[2], "stayed put")
			assert(gold() == 39, "no gold spent")
			assert(#newItems(state.items) == 0, "nothing conjured")
		end,
	},
})

-- Your weapon cannot hurt him: attacking does nothing, and he never fights
-- back.
roomScene("conjurerIgnoresAttacks", {
	gold = 0,
	from = { 0, 1 },
	actions = { "up", "up", "idle", "idle" },
	checks = {
		[2] = function(state)
			assert(state.keeper.health.health == 1, "unhurt")
			assertRel(state.keeper, player(), 0, 1, "attacking moves nothing")
		end,
		[4] = function(state)
			assert(Entities.entityExists(state.keeper.id), "still there")
			assert(fixtures.health() == player().health.maxHealth, "never hit back")
		end,
	},
})

-- A bomb kills him (he has 1 health), and the tiles then do nothing: stepping
-- on one costs no gold and conjures nothing.
roomScene("conjurerBombKillsAndTilesStop", {
	gold = 100,
	from = { 1, 1 },
	actions = { "bomb", "right", "right", "idle", "idle", "idle", "left", "down" },
	checks = {
		[6] = function(state)
			assert(not Entities.entityExists(state.keeper.id), "the bomb killed him")
		end,
		[8] = function(state)
			assertRel(state.keeper, player(), 2, 2, "standing on the ring tile")
			assert(gold() == 100, "no gold spent")
			assert(#newItems(state.items) == 0, "nothing conjured")
		end,
	},
})

-- To the beat, the rune a purchase puts you on does not send you anywhere;
-- stepping off it and back on takes you out of the room.
testsApi.registerTest({
	name = "conjurerRuneWaitsAfterPurchase",
	async = true,
	timeoutTicks = 30000,
	onLoad = function(_, finish)
		withRoom(function(keeper)
			local kx, ky = keeper.position.x, keeper.position.y
			Currency.set(player(), Currency.Type.GOLD, 40)
			Move.absolute(player(), kx + TORCH.from[1], ky + TORCH.from[2], Move.Type.TELEPORT)
			local tries = 0
			-- An input can miss its beat, so step until the purchase lands.
			local function buy()
				tries = tries + 1
				assert(tries < 40, "the purchase never happened")
				if gold() == 0 then
					assertRel(keeper, player(), RUNE[1], RUNE[2], "sent to the rune")
					testsApi.afterTicks(3000, function()
						assertRel(keeper, player(), RUNE[1], RUNE[2], "still on the rune after a few beats")
						local leaveTries = 0
						-- Off the rune, then back on; a missed beat repeats the step.
						local function leave()
							leaveTries = leaveTries + 1
							assert(leaveTries < 40, "never left the room")
							local rx, ry = relative(keeper, player())
							if math.abs(rx) > 8 or math.abs(ry) > 8 then
								finish()
								return
							end
							local step = (rx == RUNE[1] and ry == RUNE[2]) and "up" or "down"
							testsApi.play({ step }, nil, function()
								testsApi.afterTicks(300, leave)
							end)
						end
						leave()
					end)
					return
				end
				testsApi.play({ TORCH.step }, nil, function()
					testsApi.afterTicks(100, buy)
				end)
			end
			testsApi.afterTicks(600, buy)
		end)
	end,
})
