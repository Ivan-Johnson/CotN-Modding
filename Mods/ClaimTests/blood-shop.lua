local CurrentLevel = require "necro.game.level.CurrentLevel"
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
local health = fixtures.health

-- The fixed seed does not fix the level's secret room: the run's random seed
-- picks it, if any. So each test starts a fresh single-zone run whose 1-1
-- holds the blood shop: while `forcing` is set, the run's level sequence gets
-- the blood shop's travel rune. The run keeps the framework's fixed seed and
-- no-beat mode. The shop is a separate room of the level, so the tests
-- teleport the player in rather than walk through the travel rune, which
-- belongs to secret-shops.lua.
local forcing = false
event.levelSequenceUpdate.add("ClaimTestsBloodShopRoom", { order = "secretRooms", sequence = 20 }, function(ev)
	if forcing and ev.sequence[1] then
		ev.sequence[1].secretRoom = "TravelRune3"
	end
end)

local function named(name)
	local list = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name == name then
			list[#list + 1] = entity
		end
	end
	return list
end

local function priceTag(ware)
	return ware.sale.priceTag ~= 0 and Entities.getEntityByID(ware.sale.priceTag) or nil
end

-- The blood shopkeeper, and his wares from left to right.
local function findShop()
	local keeper = assert(named("Shopkeeper2")[1], "the level has the blood shopkeeper")
	local wares = {}
	for entity in Entities.entitiesWithComponents({ "sale" }) do
		local p = entity.position
		if p and priceTag(entity) and p.y == keeper.position.y + 2 and math.abs(p.x - keeper.position.x) <= 1 then
			wares[p.x - keeper.position.x + 2] = entity
		end
	end
	return { keeper = keeper, wares = wares }
end

local function healthCost(ware)
	return priceTag(ware).priceTagCostHealth.cost
end

-- Starts a run whose 1-1 has the blood shop, from runSeed if given, and calls
-- andThen once its shopkeeper has spawned.
local function openBloodShop(runSeed, andThen)
	forcing = true
	if runSeed then
		testsApi.setSeedOverride(function()
			return runSeed
		end)
	end
	testsApi.afterTicks(100, function()
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		local function whenReady()
			if CurrentLevel.isLoading() or #named("Shopkeeper2") < 1 then
				testsApi.afterTicks(10, whenReady)
				return
			end
			forcing = false
			testsApi.setSeedOverride(nil)
			testsApi.afterTicks(100, andThen)
		end
		testsApi.afterTicks(50, whenReady)
	end)
end

-- Registers a no-beat test that opens the blood shop, runs
-- prepare(shop), which returns the tile to teleport the player to, and plays
-- actions. checks[i](shop) runs after action i. Each "fight" action becomes
-- an attack on the shopkeeper if he is beside the player, a step that puts
-- him beside the player if he is diagonal to them, or else an idle; each turn
-- is logged in shop.log.
local function bloodShopScene(name, prepare, actions, checks)
	testsApi.registerTest({
		name = name,
		async = true,
		noBeat = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			openBloodShop(nil, function()
						local shop = findShop()
						shop.log = {}
						local x, y = prepare(shop)
						Move.absolute(player(), x, y, Move.Type.TELEPORT)
						local plan = {}
						for index, action in ipairs(actions) do
							plan[index] = action
						end
						local before
						testsApi.play(plan, function(index)
							local keeper = shop.keeper
							local alive = Entities.entityExists(keeper.id)
							if before then
								before.playerDamage = before.health - health()
								before.keeperDamage = alive and before.keeperHealth - keeper.health.health
									or before.keeperHealth
								shop.log[#shop.log + 1] = before
							end
							if alive then
								shop.lastX, shop.lastY = keeper.position.x, keeper.position.y
							end
							if checks[index] then
								checks[index](shop)
							end
							before = nil
							if plan[index + 1] == "fight" then
								plan[index + 1] = "idle"
							end
							if alive then
								local dx = keeper.position.x - player().position.x
								local dy = keeper.position.y - player().position.y
								before = {
									health = health(),
									keeperHealth = keeper.health.health,
									diagonal = math.abs(dx) == 1 and math.abs(dy) == 1,
								}
								if actions[index + 1] == "fight" then
									if math.abs(dx) + math.abs(dy) == 1 then
										plan[index + 1] = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
										before.attacked = true
									elseif before.diagonal then
										plan[index + 1] = dy == 1 and "down" or "up"
									end
								end
							end
						end, finish)
			end)
		end,
	})
end

local function fights(route, count)
	local list = {}
	for _, action in ipairs(route) do
		list[#list + 1] = action
	end
	for _ = 1, count do
		list[#list + 1] = "fight"
	end
	return list
end

local function beside(shop)
	return shop.keeper.position.x - 1, shop.keeper.position.y
end

-- The shop: Shopkeeper2 behind three wares, each priced in health and not in
-- gold, the left one a gold weapon. Buying takes the price from your health,
-- not your maximum, and you step onto the tile holding the ware.
bloodShopScene("bloodShopBuy", function(shop)
	for slot = 1, 3 do
		local ware = shop.wares[slot]
		assert(ware, "ware " .. slot .. " is for sale")
		local tag = priceTag(ware)
		assert(tag.priceTagCostHealth and tag.priceTagCostHealth.cost > 0, "ware " .. slot .. " has a health price")
		assert(not tag.priceTagCostCurrency, "ware " .. slot .. " has no gold price")
	end
	assert(shop.wares[1].weaponMaterialGold, "the left ware is a gold weapon, got " .. shop.wares[1].name)
	local costs = {}
	for slot = 1, 3 do
		costs[slot] = healthCost(shop.wares[slot])
	end
	costs = table.concat(costs, ",")
	assert(costs == "3,2,2", "prices " .. costs)
	assert(health() == 12, "Cadence starts the single-zone run on 12 health, has " .. health())
	local p = shop.wares[1].position
	return p.x, p.y + 1
end, { "up" }, {
	[1] = function(shop)
		assert(health() == 9 and player().health.maxHealth == 12, "paid 3 health, left " .. health())
		local p = shop.wares[1].position
		fixtures.assertAt(player(), p.x, p.y, "on the ware's tile")
		assert(Inventory.getItemInSlot(player(), "weapon").id == shop.wares[1].id, "holding the ware")
	end,
})

-- With no more health than the price, the purchase still goes through and
-- kills you, as "Blood Debt".
local killer
event.objectDeath.add("ClaimTestsBloodShopKiller", { order = "runSummary", sequence = -1 }, function(ev)
	if ev.entity and ev.entity.id == player().id then
		killer = ev.killerName
	end
end)
for name, short in pairs({ bloodShopExactHealthKills = 0, bloodShopTooLittleHealthKills = 1 }) do
	bloodShopScene(name, function(shop)
		player().health.health = healthCost(shop.wares[1]) - short
		killer = nil
		local p = shop.wares[1].position
		return p.x, p.y + 1
	end, { "up" }, {
		[1] = function(shop)
			assert(health() == 0, "the price killed the player, left " .. health())
			assert(killer == "Blood Debt", "killed by " .. tostring(killer))
			assert(Inventory.getItemInSlot(player(), "weapon").id == shop.wares[1].id, "the ware was bought")
		end,
	})
end

-- Attacking an unprovoked blood shopkeeper does nothing, and he never attacks.
bloodShopScene("bloodShopkeeperIgnoresAttacks", function(shop)
	return beside(shop)
end, { "right", "right", "right", "idle", "idle" }, {
	[5] = function(shop)
		assert(shop.keeper.health.health == 8, "the shopkeeper took nothing")
		assert(not shop.keeper.provokable.active, "and is not provoked")
		assert(health() == 12, "the player took nothing")
	end,
})

-- A bomb takes 4 of his 8 health and provokes him. Provoked, he hits for 20
-- every second beat, and the wares keep their price.
local idleRoute = { "bomb", "left", "down", "down", "down" }
for _ = 1, 16 do
	idleRoute[#idleRoute + 1] = "idle"
end
bloodShopScene("bloodShopkeeperHits", function(shop)
	player().health.health = 300
	player().health.maxHealth = 300
	Inventory.grant("Bomb", player())
	return beside(shop)
end, idleRoute, {
	[4] = function(shop)
		assert(shop.keeper.provokable.active, "the bomb provoked him")
		assert(shop.keeper.health.health == 4, "the bomb took 4 of his 8, left " .. shop.keeper.health.health)
	end,
	[#idleRoute] = function(shop)
		local hits, lastHit = 0, nil
		for index, turn in ipairs(shop.log) do
			if turn.playerDamage > 0 then
				assert(turn.playerDamage == 20, "he hits for 20, hit " .. turn.playerDamage)
				assert(not lastHit or index - lastHit == 2, "a hit every second beat")
				hits, lastHit = hits + 1, index
			end
		end
		assert(hits >= 3, "he hit more than twice, hit " .. hits)
		for slot = 1, 3 do
			assert(priceTag(shop.wares[slot]).priceTag.active, "ware " .. slot .. " still has its price")
		end
	end,
})

-- A dagger takes 1 per hit. Killed, he drops a Blood Drum where he died, and
-- the wares left are free.
local killRoute = fights({ "bomb", "left", "down", "down" }, 40)
bloodShopScene("bloodShopkeeperKilled", function(shop)
	player().health.health = 300
	player().health.maxHealth = 300
	Inventory.grant("Bomb", player())
	return beside(shop)
end, killRoute, {
	[#killRoute] = function(shop)
		assert(not Entities.entityExists(shop.keeper.id), "the shopkeeper died")
		local hits = 0
		for _, turn in ipairs(shop.log) do
			if turn.attacked then
				assert(turn.keeperDamage == 1, "a dagger hit takes 1, took " .. turn.keeperDamage)
				hits = hits + 1
			end
		end
		assert(hits == 4, "four dagger hits after the bomb, got " .. hits)
		local drum
		for _, entity in ipairs(named("BloodDrum")) do
			if entity.position.x == shop.lastX and entity.position.y == shop.lastY then
				drum = entity
			end
		end
		assert(drum, string.format("he dropped a Blood Drum where he died, (%d,%d)", shop.lastX, shop.lastY))
		local free = 0
		for slot = 1, 3 do
			local ware = shop.wares[slot]
			if Entities.entityExists(ware.id) and priceTag(ware) then
				assert(not priceTag(ware).priceTag.active, "ware " .. slot .. " is free")
				free = free + 1
			end
		end
		assert(free >= 1, "a ware was left to check")
	end,
})

-- Whatever the seed, the left ware is a gold weapon. Eight seeds gave eight
-- different sets of wares.
testsApi.registerTest({
	name = "bloodShopGoldWeaponEverySeed",
	async = true,
	timeoutTicks = 60000,
	onLoad = function(_, finish)
		local seeds = { 1, 2, 3, 4, 5, 6, 7, 8 }
		local sets = {}
		local index = 0
		local function nextSeed()
			index = index + 1
			if index > #seeds then
				local distinct = 0
				for _ in pairs(sets) do
					distinct = distinct + 1
				end
				assert(distinct >= 4, "the seeds gave " .. distinct .. " distinct ware sets")
				finish()
				return
			end
			openBloodShop(seeds[index], function()
				local shop = findShop()
				local names = {}
				for slot = 1, 3 do
					names[slot] = shop.wares[slot] and shop.wares[slot].name or "none"
				end
				local set = table.concat(names, ",")
				assert(CurrentLevel.getSeed() == seeds[index], "the run used seed " .. tostring(CurrentLevel.getSeed()))
				sets[set] = true
				assert(shop.wares[1].weaponMaterialGold, "seed " .. seeds[index] .. ": left ware " .. names[1])
				nextSeed()
			end)
		end
		nextSeed()
	end,
})
