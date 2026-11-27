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

local player = fixtures.player

-- Each test restarts its run with the pawnbroker's room (TravelRune8) forced
-- onto the first level, then teleports the player into the room. Positions
-- below are offsets from the Pawnbroker, y growing downward.

local forcePawnbroker = false
event.levelSequenceUpdate.add("ClaimTestsPawnbrokerForce", { order = "secretRooms", sequence = 10 }, function(ev)
	if forcePawnbroker then
		for _, level in ipairs(ev.sequence) do
			level.secretRoom = "TravelRune8"
		end
	end
end)

event.levelGenerate.add("ClaimTestsPawnbrokerForceLevel", { sequence = 7 }, function(ev)
	if forcePawnbroker and ev.options and ev.options.type == "Necro" then
		ev.options.secretRoom = "TravelRune8"
	end
end)

local levelLoads = 0
event.levelLoad.add("ClaimTestsPawnbrokerLoads", { order = "extraEntities", sequence = 21 }, function()
	levelLoads = levelLoads + 1
end)

local function findKeeper()
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name == "Pawnbroker" then
			return entity
		end
	end
end

-- Restarts the run with the pawnbroker's room on the level, then calls
-- andThen(keeper).
local function withPawnbroker(andThen)
	forcePawnbroker = true
	-- Counted from the restart, not from onLoad: the test level's own load
	-- reaches the counter after onLoad runs, and the run's random seed can
	-- give that level a Pawnbroker of its own.
	local loadsBefore
	testsApi.afterTicks(30, function()
		loadsBefore = levelLoads
		GameSession.start({ mode = GameSession.Mode.SingleZone })
	end)
	local tries = 0
	local function poll()
		tries = tries + 1
		local keeper = levelLoads > loadsBefore and findKeeper()
		if keeper and player() then
			-- Act only once no further level load follows: an input right
			-- after a load can be lost, and a second load would undo the setup.
			local loadsSeen = levelLoads
			testsApi.afterTicks(60, function()
				if levelLoads ~= loadsSeen or not Entities.entityExists(keeper.id) then
					poll()
					return
				end
				forcePawnbroker = false
				andThen(keeper)
			end)
		elseif tries > 60 then
			forcePawnbroker = false
			error("the forced run has no Pawnbroker")
		else
			testsApi.afterTicks(50, poll)
		end
	end
	testsApi.afterTicks(50, poll)
end

local function gold()
	return Currency.get(player(), Currency.Type.GOLD)
end

local function holding(slot)
	local item = Inventory.getItemInSlot(player(), slot, 1)
	return item and item.name or nil
end

local function relative(keeper, entity)
	return entity.position.x - keeper.position.x, entity.position.y - keeper.position.y
end

-- The items for sale in the room, as "Name$price" sorted by column.
local function wares(keeper)
	local list = {}
	for entity in Entities.entitiesWithComponents({ "sale" }) do
		local tag = entity.sale.priceTag ~= 0 and Entities.getEntityByID(entity.sale.priceTag)
		local dx, dy = relative(keeper, entity)
		local inRoom = math.abs(dx) <= 2 and dy >= 0 and dy <= 9
		if inRoom and tag and tag.priceTagCostCurrency and entity.item and entity.item.holder == 0 then
			list[#list + 1] = { dx = dx, dy = dy, text = entity.name .. "$" .. tag.priceTagCostCurrency.cost }
		end
	end
	table.sort(list, function(a, b)
		return a.dx < b.dx
	end)
	local out = {}
	for _, ware in ipairs(list) do
		out[#out + 1] = ware.text
		assert(ware.dy == 6, ware.text .. " is 6 rows below the Pawnbroker")
	end
	return table.concat(out, " ")
end

--[[
Registers a no-beat test in the pawnbroker's room. Fields: name, items (granted
before the first action), actions, checks ({[index] = function(room)} after
that action; [0] before the first), start (offset to teleport the player to,
default {0, 5}), gold (default 0), health, zone, setup (function(keeper)
before the first action), after (function(room, index, name) after each
action, before its check). room is {keeper, kx, ky (his starting tile),
log = {gold after each action}}. A "fight" action becomes
an attack on the adjacent Pawnbroker, or idle if he is not adjacent.
]]
local function pawnScene(spec)
	testsApi.registerTest({
		name = spec.name,
		zone = spec.zone,
		async = true,
		noBeat = true,
		timeoutTicks = 20000,
		onLoad = function(_, finish)
			withPawnbroker(function(keeper)
				local kx, ky = keeper.position.x, keeper.position.y
				local start = spec.start or { 0, 5 }
				Move.absolute(player(), kx + start[1], ky + start[2], Move.Type.TELEPORT)
				Currency.set(player(), Currency.Type.GOLD, spec.gold or 0)
				if spec.setup then
					spec.setup(keeper)
				end
				if spec.health then
					player().health.maxHealth = spec.health
					player().health.health = spec.health
				end
				for _, item in ipairs(spec.items or {}) do
					Inventory.grant(item, player())
				end
				local room = { keeper = keeper, kx = kx, ky = ky, log = {} }
				local checks = spec.checks or {}
				if checks[0] then
					checks[0](room)
				end
				local actions = {}
				for index, name in ipairs(spec.actions) do
					actions[index] = name
				end
				testsApi.play(actions, function(index, name, resolved)
					assert(resolved, "action " .. index .. " (" .. name .. ") never took a turn")
					room.log[index] = gold()
					if spec.after then
						spec.after(room, index, name)
					end
					if checks[index] then
						checks[index](room)
					end
					if actions[index + 1] == "fight" then
						actions[index + 1] = "idle"
						if Entities.entityExists(keeper.id) then
							local dx = keeper.position.x - player().position.x
							local dy = keeper.position.y - player().position.y
							if math.abs(dx) + math.abs(dy) == 1 then
								actions[index + 1] = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
							end
						end
					end
				end, function()
					finish()
				end)
			end)
		end,
	})
end

local function assertPlayerAt(room, dx, dy, what)
	fixtures.assertAt(player(), room.kx + dx, room.ky + dy, what)
end

-- The room: the Pawnbroker at the top, a 3x3 block of slot tiles two rows
-- below him with a blocker in its middle, and the exit rune below that.
local SLOT_TILES = {
	TransactionTileHead = { -1, 2, "head" },
	TransactionTileShield = { 0, 2, "shield" },
	TransactionTileRing = { 1, 2, "ring" },
	TransactionTileBody = { -1, 3, "body" },
	TransactionTileShovel = { 1, 3, "shovel" },
	TransactionTileFeet = { -1, 4, "feet" },
	TransactionTileTorch = { 0, 4, "torch" },
	TransactionTileWeapon = { 1, 4, "weapon" },
}

pawnScene({
	name = "pawnbrokerRoom",
	actions = { "idle" },
	checks = {
		[0] = function(room)
			for typeName, where in pairs(SLOT_TILES) do
				local tiles = Entities.getEntitiesByType(typeName)
				assert(#tiles == 1, "one " .. typeName)
				local dx, dy = relative(room.keeper, tiles[1])
				assert(dx == where[1] and dy == where[2], typeName .. " at its place")
				assert(tiles[1].trapTransaction.slot == where[3], typeName .. " sells the " .. where[3] .. " slot")
			end
			local blocker = Entities.getEntitiesByType("TransactionCollisionDummy")[1]
			local bx, by = relative(room.keeper, blocker)
			assert(bx == 0 and by == 3, "the middle of the block is blocked")
			local rune = Entities.getEntitiesByType("TravelRune8")[1]
			local rx, ry = relative(room.keeper, rune)
			assert(rx == 0 and ry == 6, "the exit rune is 6 rows below him")
			for dx = -3, 3 do
				local want = math.abs(dx) == 3 and "ShopWall" or "Floor"
				local got = fixtures.tileName(room.kx + dx, room.ky)
				assert(got == want, string.format("%s at (%d,0), got %s", want, dx, got))
				assert(fixtures.tileName(room.kx + dx, room.ky - 1) == "ShopWall", "shop wall above him")
			end
			assert(wares(room.keeper) == "", "nothing is for sale yet")
			assert(room.keeper.secretShopLabel.text == "Sell one of your items?", "his label")
			local entrance = Entities.getEntityPrototype("TravelRune8").generateSecretRoom.wallType
			assert(entrance == "CatacombWallCracked", "the rune hides in a cracked catacomb wall")
		end,
	},
})

-- Selling all eight slots, one tile each: half the item's shop price,
-- rounded down. The wares appear after the second sale and change with each
-- sale; the seventh brings a single special offer. A tile whose slot is empty
-- does nothing.
local EIGHT = { "HeadMinersCap", "RingGold", "ArmorLeather", "ShovelTitanium", "FeetBootsExplorers", "Torch2" }
EIGHT[#EIGHT + 1] = "WeaponLongsword"
EIGHT[#EIGHT + 1] = "Sync_ShieldWooden"
-- Shop prices: Torch2 15, WeaponLongsword 50, ShovelTitanium 40, RingGold 30,
-- Sync_ShieldWooden 10, HeadMinersCap 40, ArmorLeather 20, FeetBootsExplorers 15.
local EIGHT_GOLD = { 7, 32, 52, 67, 72, 92, 102, 109 }
local EIGHT_SLOTS = { "torch", "weapon", "shovel", "ring", "shield", "head", "body", "feet" }
local eightWares, eightHeld = {}, {}
pawnScene({
	name = "pawnbrokerSellsEachSlot",
	items = EIGHT,
	actions = { "up", "right", "up", "up", "left", "left", "down", "down", "up", "down", "down", "right" },
	after = function(room, index)
		if index <= 8 then
			local slot = EIGHT_SLOTS[index]
			assert(room.log[index] == EIGHT_GOLD[index], string.format("gold after sale %d: %d", index, room.log[index]))
			assert(holding(slot) == nil, slot .. " sold")
			for _, where in pairs(SLOT_TILES) do
				if where[3] == slot then
					assertPlayerAt(room, where[1], where[2], "on the " .. slot .. " tile")
				end
			end
			for entity in Entities.entitiesWithComponents({ "item" }) do
				assert(entity.name ~= eightHeld[slot], "a sold item is gone, not dropped")
			end
			eightWares[index] = wares(room.keeper)
		end
	end,
	checks = {
		[0] = function()
			for _, slot in ipairs(EIGHT_SLOTS) do
				eightHeld[slot] = holding(slot)
			end
		end,
		[1] = function()
			assert(eightWares[1] == "", "one sale shows no wares")
		end,
		[2] = function(room)
			local _, wareCount = eightWares[2]:gsub("%$", "")
			assert(wareCount == 3, "the second sale shows three wares: " .. eightWares[2])
			local rune = Entities.getEntitiesByType("TravelRune8")[1]
			local _, ry = relative(room.keeper, rune)
			assert(ry == 8, "the exit rune moves two rows down")
		end,
		[6] = function()
			for index = 3, 6 do
				local _, wareCount = eightWares[index]:gsub("%$", "")
				assert(wareCount == 3, "three wares after sale " .. index)
				assert(eightWares[index] ~= eightWares[index - 1], "sale " .. index .. " changes the wares")
			end
		end,
		[7] = function()
			local name, price = eightWares[7]:match("^(%S+)%$(%d+)$")
			assert(name, "the seventh sale leaves a single ware: " .. eightWares[7])
			assert(tonumber(price) == EIGHT_GOLD[7] - 1, "the special offer costs all your gold but 1: " .. eightWares[7])
		end,
		[8] = function(room)
			local _, price = eightWares[8]:match("^(%S+)%$(%d+)$")
			assert(tonumber(price) == EIGHT_GOLD[8] - 1, "the next special offer costs all your gold but 1")
			assert(eightWares[8] ~= eightWares[7], "the special offer changes with the next sale")
			assert(room.keeper.transactionLimitedUses.remainingUses == 24 - 8, "each sale uses one of 24")
		end,
		[9] = function(room)
			assert(room.log[9] == EIGHT_GOLD[8], "an empty slot's tile pays nothing")
			assertPlayerAt(room, -1, 4, "an empty slot's tile cannot be stepped on")
		end,
		[12] = function(room)
			assertPlayerAt(room, 0, 6, "on the special offer's tile")
			assert(room.log[12] == 1, "buying the special offer leaves 1 gold")
			local offer = eightWares[8]:match("^(%S+)%$")
			local got = false
			for _, item in ipairs(Inventory.getItems(player())) do
				got = got or item.name == offer
			end
			assert(got, "and gives " .. offer)
		end,
	},
})

-- The price does not depend on the zone.
for _, zone in ipairs({ 2, 3, 4, 5 }) do
	pawnScene({
		name = "pawnbrokerPriceZone" .. zone,
		zone = zone,
		items = { "Torch2" },
		actions = { "up" },
		checks = {
			[1] = function(room)
				local p = player().position
				local where = (p.x - room.kx) .. "," .. (p.y - room.ky)
				local got = room.log[1] .. " at " .. where .. " holding " .. tostring(holding("torch"))
				assert(room.log[1] == 7, "a Torch2 (15) sells for 7 in zone " .. zone .. ", got " .. got)
			end,
		},
	})
end

-- Buying a ware: the others vanish, the bought item cannot be sold back, and
-- later sales bring no more wares.
local afterBuy
pawnScene({
	name = "pawnbrokerBuyOnce",
	items = { "Torch2", "WeaponLongsword", "RingGold" },
	actions = { "up", "right", "down", "down", "up", "up", "right", "up", "up", "up", "left" },
	checks = {
		[2] = function(room)
			afterBuy = wares(room.keeper)
		end,
		[4] = function(room)
			local price = tonumber(afterBuy:match("(%d+)$"))
			local bought = afterBuy:match("(%S+)%$%d+$")
			local held = tostring(holding("weapon"))
			assert(held == bought, "bought the right-hand ware: " .. afterBuy .. "; holding " .. held)
			assert(room.log[4] == 32 - price, "paid its price")
			assert(wares(room.keeper) == "", "the other wares vanish")
		end,
		[6] = function(room)
			assert(room.log[6] == room.log[4], "no refunds: the bought weapon does not sell")
			assertPlayerAt(room, 1, 5, "the weapon tile refused")
		end,
		[11] = function(room)
			assert(room.log[11] == room.log[4] + 15, "the ring still sells")
			assert(wares(room.keeper) == "", "no new wares after a purchase")
		end,
	},
})

-- He buys 24 items per room: the count starts at 24 and each sale takes
-- one. Playing out 24 sales takes over 50 inputs, which the shared test game
-- sometimes drops, so the test starts the count at 1 instead and checks
-- that a tile does nothing once it runs out.
pawnScene({
	name = "pawnbrokerTwentyFourSales",
	items = { "Torch3" },
	actions = { "up", "down", "up" },
	setup = function(keeper)
		assert(keeper.transactionLimitedUses.remainingUses == 24, "24 sales per room")
		keeper.transactionLimitedUses.remainingUses = 1
	end,
	after = function(_, _, name)
		if name == "down" then
			Inventory.grant("Torch3", player())
		end
	end,
	checks = {
		[1] = function(room)
			assert(room.log[1] == 20, "the last sale pays")
			assert(room.keeper.transactionLimitedUses.remainingUses == 0, "and uses one")
		end,
		[3] = function(room)
			assert(room.log[3] == 20, "with no sales left, he pays nothing")
			assert(holding("torch") == "Torch3", "and the torch stays")
			assertPlayerAt(room, 0, 4, "the player steps onto the tile")
		end,
	},
})

-- Items he refuses: the starting dagger and shovel, and Sonar, which have no
-- sale value. The player stays put and keeps them.
pawnScene({
	name = "pawnbrokerRefusesWorthless",
	items = { "HeadSonar" },
	start = { 2, 4 },
	actions = { "left", "up", "left", "up", "up", "left", "left", "left", "down" },
	checks = {
		[1] = function(room)
			assertPlayerAt(room, 2, 4, "the dagger is refused")
			assert(holding("weapon") == "WeaponDagger", "keeps the dagger")
		end,
		[3] = function(room)
			assertPlayerAt(room, 2, 3, "the basic shovel is refused")
			assert(holding("shovel") == "ShovelBasic", "keeps the shovel")
		end,
		[9] = function(room)
			assertPlayerAt(room, -1, 1, "Sonar is refused")
			assert(holding("head") == "HeadSonar", "keeps Sonar")
			assert(gold() == 0, "no gold paid")
		end,
	},
})

-- Your weapon cannot hurt him and does not anger him.
pawnScene({
	name = "pawnbrokerWeaponDoesNothing",
	start = { 0, 1 },
	actions = { "up", "up", "idle", "idle" },
	checks = {
		[4] = function(room)
			assert(room.keeper.health.health == 6, "unhurt")
			assert(not room.keeper.provokable.active, "not provoked")
			assert(fixtures.health() == 12, "never attacks")
			assertPlayerAt(room, 0, 1, "the attack does not move the player")
		end,
	},
})

-- A bomb provokes him: the slot tiles vanish, he chases and hits for 20, and
-- killed he drops a coupon and gold.
local fight = { "bomb", "left", "down", "down" }
for _ = 1, 10 do
	fight[#fight + 1] = "fight"
end
local fightLog = { health = {}, keeperHealth = {}, moved = false, lastX = nil, lastY = nil }
pawnScene({
	name = "pawnbrokerBombed",
	items = { "Bomb" },
	start = { -1, 1 },
	health = 300,
	actions = fight,
	after = function(room, index)
		fightLog.health[index] = fixtures.health()
		if Entities.entityExists(room.keeper.id) then
			fightLog.keeperHealth[room.keeper.health.health] = true
			local kx, ky = room.keeper.position.x, room.keeper.position.y
			fightLog.moved = fightLog.moved or kx ~= room.kx or ky ~= room.ky
			fightLog.lastX, fightLog.lastY = kx, ky
		end
	end,
	checks = {
		[4] = function(room)
			assert(room.keeper.health.health == 2, "the bomb takes 4 of his 6 health")
			assert(room.keeper.provokable.active, "the bomb provokes him")
			for typeName in pairs(SLOT_TILES) do
				assert(#Entities.getEntitiesByType(typeName) == 0, typeName .. " vanishes")
			end
		end,
		[14] = function(room)
			local hits = {}
			for index = 5, 14 do
				local lost = fightLog.health[index - 1] - fightLog.health[index]
				if lost > 0 then
					hits[#hits + 1] = lost
				end
			end
			assert(#hits >= 1, "he attacks once provoked")
			for _, lost in ipairs(hits) do
				assert(lost == 20, "he hits for 20, got " .. lost)
			end
			assert(fightLog.moved, "he leaves his place to chase")
			assert(fightLog.keeperHealth[1], "a dagger hit takes 1")
			assert(not Entities.entityExists(room.keeper.id), "two dagger hits kill him")
			local drops = {}
			for entity in Entities.entitiesWithComponents({ "item" }) do
				if entity.position.x == fightLog.lastX and entity.position.y == fightLog.lastY then
					drops[entity.name] = true
				end
			end
			assert(drops.MiscCoupon and drops.ResourceHoardGold, "he drops a coupon and gold")
		end,
	},
})
