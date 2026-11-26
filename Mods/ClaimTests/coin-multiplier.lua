local Entities = require "system.game.Entities"
local GrooveChain = require "necro.game.character.GrooveChain"
local Inventory = require "necro.game.item.Inventory"
local Move = require "necro.game.system.Move"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence in
-- no-beat mode on an open floor, with enemies spawned by hand. The framework's
-- Cadence starts with the coin items CoinsX15 and CoinsX2, so every test
-- starts by removing them and re-grants what it needs. "x1" is the chain
-- multiplier; the coin multiplier is the chain plus 0.5 per coin item.

local COIN_ITEMS = { "CoinsX15", "CoinsX2" }

local function player()
	return fixtures.player()
end

local function gold()
	return player().goldCounter.amount
end

local function coinMultiplier()
	return player().coinMultiplier.multiplier
end

local function findItem(name)
	for _, item in ipairs(Inventory.getItems(player())) do
		if item.name == name then
			return item
		end
	end
end

local function removeItems(names)
	for _, name in ipairs(names) do
		local item = findItem(name)
		if item then
			Object.delete(item)
		end
	end
end

local function setItems(names)
	removeItems(COIN_ITEMS)
	for _, name in ipairs(names) do
		if not findItem(name) then
			Inventory.grant(name, player())
		end
	end
end

local function setChain(kills, multiplier)
	local entity = player()
	entity.grooveChain.killCount = kills
	entity.grooveChain.multiplier = multiplier
	GrooveChain.update(entity)
end

local function isPile(entity)
	return entity.name:find("^ResourceCoin") or entity.name:find("^ResourceHoardGold")
end

local function piles()
	local found = {}
	for entity in Entities.entitiesWithComponents({ "position", "itemCurrency" }) do
		if isPile(entity) then
			table.insert(found, entity)
		end
	end
	return found
end

-- Back to the origin with no enemies, traps, bombs on the floor or piles, and
-- plenty of health, so one scene cannot leak into the next.
local function reset()
	local entity = player()
	Move.absolute(entity, 0, 0, Move.Type.TELEPORT)
	local doomed = {}
	for candidate in Entities.entitiesWithComponents({ "position" }) do
		local name = candidate.name
		local isLoose = not candidate.item and (candidate.ai or name:find("Trap") or name:find("^Bomb"))
		if isLoose or isPile(candidate) or name == "Food1" then
			table.insert(doomed, candidate)
		end
	end
	for _, candidate in ipairs(doomed) do
		Object.delete(candidate)
	end
	entity.health.maxHealth = 200
	entity.health.health = 200
	Tile.setType(1, 0, "Floor")
end

local function act(name, after)
	testsApi.play({ name }, nil, after)
end

local function walkTo(x, y, after)
	local entity = player()
	local dx = x - entity.position.x
	local dy = y - entity.position.y
	if dx == 0 and dy == 0 then
		after()
		return
	end
	local direction
	if dx ~= 0 then
		direction = dx > 0 and "right" or "left"
	else
		direction = dy > 0 and "down" or "up"
	end
	act(direction, function()
		walkTo(x, y, after)
	end)
end

local function collectPiles(after)
	local found = piles()
	local goldBefore = gold()
	local function collect(index)
		local pile = found[index]
		if not pile then
			after(gold() - goldBefore, #found)
			return
		end
		walkTo(pile.position.x, pile.position.y, function()
			collect(index + 1)
		end)
	end
	collect(1)
end

local function series(items, run, finish)
	local index = 0
	local function nextItem()
		index = index + 1
		if not items[index] then
			finish()
			return
		end
		run(items[index], nextItem)
	end
	nextItem()
end

local function scene(name, body)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(12)
			body(finish)
		end,
	})
end

-- Spawns typeName next to the player, fights it with the dagger (or the given
-- actions), and walks onto what it dropped. Calls after(gold collected, coin
-- multiplier before the last action). opts.chain re-sets the chain before every
-- action, so an enemy's hits cannot change the multiplier under test.
local function kill(typeName, after, opts)
	opts = opts or {}
	local entity = player()
	local side = entity.position.x > 3 and -1 or 1
	local spawned = fixtures.spawn(typeName, entity.position.x + (opts.dx or side), entity.position.y + (opts.dy or 0))
	local actionIndex = 0
	local lastMultiplier = coinMultiplier()
	local goldBefore = gold()
	local function step()
		if not Entities.entityExists(spawned.id) then
			collectPiles(function()
				after(gold() - goldBefore, lastMultiplier)
			end)
			return
		end
		actionIndex = actionIndex + 1
		assert(actionIndex <= 30, typeName .. " would not die")
		if opts.chain then
			setChain(opts.chain[1], opts.chain[2])
		end
		lastMultiplier = coinMultiplier()
		local scripted = opts.actions and opts.actions[actionIndex]
		if scripted then
			act(scripted, step)
			return
		end
		local here = player().position
		local dx = spawned.position.x - here.x
		local dy = spawned.position.y - here.y
		local direction
		if dx ~= 0 then
			direction = dx > 0 and "right" or "left"
		else
			direction = dy > 0 and "down" or "up"
		end
		act(direction, step)
	end
	step()
end

local function killPaying(typeName, expected, opts)
	return function(next)
		reset()
		setChain(0, 1)
		kill(typeName, function(paid)
			assert(paid == expected, string.format("%s paid %d, expected %d", typeName, paid, expected))
			next()
		end, opts)
	end
end

-- The chain starts at x1, the first kill makes it x2 and the fifth x3, where it
-- stays. A kill pays at the multiplier from before it.
scene("coinChainRisesToThreeAndPaysBeforeRising", function(finish)
	setItems({})
	reset()
	setChain(0, 1)
	local paid = { 1, 2, 2, 2, 2, 3, 3 }
	local multiplierAfter = { 2, 2, 2, 2, 3, 3, 3 }
	local kills = {}
	for index = 1, #paid do
		kills[index] = index
	end
	assert(player().grooveChain.multiplier == 1, "the chain starts at x1")
	series(kills, function(index, next)
		kill("Slime", function(collected)
			assert(collected == paid[index], string.format("kill %d paid %d, expected %d", index, collected, paid[index]))
			local multiplier = player().grooveChain.multiplier
			assert(multiplier == multiplierAfter[index], string.format("after kill %d: x%d", index, multiplier))
			next()
		end)
	end, finish)
end)

-- Each coin item adds 0.5 to the multiplier, whatever the chain; fractions of
-- a gold round half up.
scene("coinItemsAddHalfEach", function(finish)
	local cases = {
		{ items = {}, chain = { 0, 1 }, type = "Slime", paid = 1 },
		{ items = { "CoinsX15" }, chain = { 0, 1 }, type = "Slime", paid = 2 },
		{ items = { "CoinsX15" }, chain = { 0, 1 }, type = "Skeleton2", paid = 5 },
		{ items = { "CoinsX2" }, chain = { 0, 1 }, type = "Skeleton2", paid = 5 },
		{ items = { "CoinsX15", "CoinsX2" }, chain = { 0, 1 }, type = "Slime", paid = 2 },
		{ items = { "CoinsX15", "CoinsX2" }, chain = { 1, 2 }, type = "Slime3", paid = 6 },
		{ items = { "CoinsX15", "CoinsX2" }, chain = { 5, 3 }, type = "Skeleton2", paid = 12 },
	}
	series(cases, function(case, next)
		reset()
		setItems(case.items)
		setChain(case.chain[1], case.chain[2])
		kill(case.type, function(paid)
			assert(paid == case.paid, string.format("%s with %d items at x%d paid %d, expected %d", case.type,
				#case.items, case.chain[2], paid, case.paid))
			next()
		end, { chain = case.chain })
	end, finish)
end)

local BASE_GOLD = {
	Slime = 1,
	Slime2 = 2,
	Slime3 = 2,
	Zombie = 1,
	Skeleton = 2,
	Skeleton2 = 3,
	Skeleton3 = 4,
	Bat = 2,
	Bat2 = 3,
	Bat3 = 20,
	Monkey = 1,
	BatMiniboss = 10,
	Minotaur = 10,
	Minotaur2 = 15,
	Dragon = 10,
	Dragon2 = 20,
}

-- What each enemy pays at x1 with no coin items.
scene("coinBaseGoldPerEnemy", function(finish)
	setItems({})
	local order = {}
	for typeName in pairs(BASE_GOLD) do
		table.insert(order, typeName)
	end
	table.sort(order)
	series(order, function(typeName, next)
		killPaying(typeName, BASE_GOLD[typeName], { chain = { 0, 1 } })(next)
	end, function()
		-- A Ghost dies to the dagger only on the action that turns the player
		-- toward it; a Monkey2 dies before it grabs only to a 2-damage weapon.
		killPaying("Ghost", 2, { dx = 0, dy = 1, actions = { "up", "down" }, chain = { 0, 1 } })(function()
			Inventory.grant("WeaponTitaniumBroadsword", player())
			killPaying("Monkey2", 3, { chain = { 0, 1 } })(finish)
		end)
	end)
end)

-- Enemies that come with the level carry the same amounts.
testsApi.registerTest({
	name = "coinNaturalEnemiesPayTheBaseGold",
	onLoad = function()
		local checked = 0
		for entity in Entities.entitiesWithComponents({ "dropCurrencyOnDeath", "ai" }) do
			local expected = BASE_GOLD[entity.name]
			if expected then
				checked = checked + 1
				local amount = entity.dropCurrencyOnDeath.amount
				assert(amount == expected, string.format("%s drops %d, expected %d", entity.name, amount, expected))
			end
		end
		assert(checked > 0, "the level has no enemy of the tabulated types")
	end,
})

-- Actions that leave the chain alone and actions that end it. Each starts from
-- five kills (x3) with one tile of floor to the right of the player.
local function chainProbe(label, setup, actions, expectedMultiplier, waitTicks)
	return {
		label = label,
		setup = setup,
		actions = actions,
		multiplier = expectedMultiplier,
		waitTicks = waitTicks or 1,
	}
end

-- A probe whose actions must also cost the player health.
local function hurtProbe(label, setup, actions, expectedMultiplier)
	local probe = chainProbe(label, setup, actions, expectedMultiplier)
	probe.hurt = true
	return probe
end

local function tile(tileType)
	return function()
		Tile.setType(1, 0, tileType)
	end
end

local function spawnAt(typeName)
	return function()
		fixtures.spawn(typeName, 1, 0)
	end
end

local function nothing() end

scene("coinChainSurvivesOrBreaks", function(finish)
	setItems({})
	local probes = {
		chainProbe("walking onto empty floor", nothing, { "right" }, 3),
		chainProbe("digging dirt", tile("DirtWall"), { "right", "right" }, 3),
		chainProbe("opening a door", tile("DoorHorizontal"), { "right", "right" }, 3),
		chainProbe("placing a bomb", function()
			Inventory.grant("Bomb", player())
		end, { "bomb" }, 3),
		chainProbe("picking up a pile", spawnAt("ResourceCoin5"), { "right" }, 3),
		chainProbe("picking up an item", spawnAt("Food1"), { "right" }, 3),
		chainProbe("a bounce trap", spawnAt("BounceTrapRight"), { "right" }, 3),
		-- The Blood Drum's 1-health cost is self-damage, which keeps the chain.
		hurtProbe("the Blood Drum's cost", function()
			Inventory.grant("BloodDrum", player())
		end, { "item1" }, 3),
		-- Damage from the player's own bomb ends it; the walk stays in the blast.
		hurtProbe("the player's own bomb", function()
			Inventory.grant("Bomb", player())
		end, { "bomb", "right", "up", "down" }, 1),
		chainProbe("idling", nothing, { "idle" }, 1),
		chainProbe("bumping stone", tile("StoneWall"), { "right" }, 1),
		chainProbe("bumping the level edge", tile("LevelBorder"), { "right" }, 1),
		chainProbe("a bomb with none left", function()
			removeItems({ "Bomb", "Bomb3" })
		end, { "bomb" }, 1),
		hurtProbe("stepping on spikes", spawnAt("SpikeTrap"), { "right", "right" }, 1),
		-- Last: the chain ends a fraction of a second after the step, and the
		-- level changes a couple of seconds after it.
		chainProbe("falling through a trapdoor", spawnAt("Trapdoor"), { "right" }, 1, 500),
	}
	series(probes, function(probe, next)
		reset()
		setChain(5, 3)
		probe.setup()
		testsApi.play(probe.actions, nil, function()
			testsApi.afterTicks(probe.waitTicks, function()
				local multiplier = player().grooveChain.multiplier
				assert(multiplier == probe.multiplier, string.format("%s: x%d, expected x%d", probe.label, multiplier,
					probe.multiplier))
				if probe.hurt then
					assert(player().health.health < 200, probe.label .. " should hurt the player")
				end
				next()
			end)
		end)
	end, finish)
end)

-- An enemy's own attack ends the chain: the player keeps hitting a skeleton
-- too tough to die until it hits back.
scene("coinChainEndsOnEnemyAttack", function(finish)
	setItems({})
	reset()
	setChain(5, 3)
	local skeleton = fixtures.spawn("Skeleton", 1, 0)
	skeleton.health.maxHealth = 100
	skeleton.health.health = 100
	local steps = 0
	local function step()
		if player().health.health < 200 then
			assert(player().grooveChain.multiplier == 1, "the skeleton's hit left x" .. player().grooveChain.multiplier)
			finish()
			return
		end
		assert(player().grooveChain.multiplier == 3, "the chain broke before the hit")
		steps = steps + 1
		assert(steps <= 6, "the skeleton never hit")
		act("right", step)
	end
	step()
end)

-- A bomb counts every enemy it kills, each paid at the multiplier the earlier
-- kills left, and destroys the piles lying in its blast.
scene("coinBombKillsPayAndBombsDestroyPiles", function(finish)
	setItems({})
	reset()
	setChain(0, 1)
	fixtures.spawn("ResourceCoin5", -1, -1)
	Inventory.grant("Bomb", player())
	fixtures.spawn("Slime", 1, 0)
	fixtures.spawn("Slime", -1, 0)
	fixtures.spawn("Slime", 0, 1)
	local goldBefore = gold()
	testsApi.play({ "bomb", "up", "up", "up", "up" }, nil, function()
		assert(player().grooveChain.killCount == 3, "three kills in one blast")
		assert(player().grooveChain.multiplier == 2, "three kills make x2")
		collectPiles(function(collected, count)
			assert(count == 3, "three piles, the one in the blast destroyed: " .. count)
			assert(collected == 5, "paid 1, 2 and 2: " .. collected)
			assert(gold() - goldBefore == 5, "no gold from the destroyed pile")
			finish()
		end)
	end)
end)

-- Two enemies killed by spikes leave no gold and do not move the chain.
scene("coinTrapKillsPayNothing", function(finish)
	setItems({})
	reset()
	setChain(5, 3)
	local victims = {}
	for _, spot in ipairs({ { 4, 4, "Slime3" }, { -4, -4, "Slime2" } }) do
		for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			fixtures.spawn("SpikeTrap", spot[1] + offset[1], spot[2] + offset[2])
		end
		table.insert(victims, fixtures.spawn(spot[3], spot[1], spot[2]))
	end
	testsApi.play({ "left", "right", "left", "right", "left", "right", "left", "right" }, nil, function()
		for _, victim in ipairs(victims) do
			assert(not Entities.entityExists(victim.id), victim.name .. " should have died to the spikes")
		end
		assert(#piles() == 0, "a trap kill leaves no gold")
		assert(player().grooveChain.killCount == 5, "a trap kill does not extend the chain")
		finish()
	end)
end)

-- Walking onto a pile gives its own gold, whatever the multiplier; diamonds
-- give none.
scene("coinPilePickupsIgnoreTheMultiplier", function(finish)
	local cases = {
		{ "ResourceCoin5", 5 },
		{ "ResourceHoardGoldSmall", 25 },
		{ "ResourceHoardGold", 50 },
		{ "ResourceDiamond", 0 },
	}
	series(cases, function(case, next)
		reset()
		setItems({ "CoinsX15", "CoinsX2" })
		setChain(5, 3)
		fixtures.spawn(case[1], 1, 0)
		local goldBefore = gold()
		act("right", function()
			local collected = gold() - goldBefore
			assert(collected == case[2], string.format("%s gave %d, expected %d", case[1], collected, case[2]))
			next()
		end)
	end, finish)
end)

-- The Ring of Gold adds one gold per kill after the multiplier.
scene("coinRingOfGoldAddsOneAfterTheMultiplier", function(finish)
	local cases = {
		{ chain = { 0, 1 }, type = "Slime", paid = 2 },
		{ chain = { 5, 3 }, type = "Slime", paid = 4 },
		{ chain = { 5, 3 }, type = "Skeleton3", paid = 13 },
	}
	series(cases, function(case, next)
		reset()
		setItems({ "RingGold" })
		setChain(case.chain[1], case.chain[2])
		kill(case.type, function(paid)
			assert(paid == case.paid, string.format("%s at x%d paid %d, expected %d", case.type, case.chain[2], paid,
				case.paid))
			next()
		end, { chain = case.chain })
	end, finish)
end)

-- A monkey that has grabbed the player and then dies leaves no gold and does
-- not count as a kill.
scene("coinGrabbingMonkeyPaysNothing", function(finish)
	setItems({})
	reset()
	setChain(0, 1)
	local goldBefore = gold()
	local monkey = fixtures.spawn("Monkey", 3, 0)
	testsApi.play({ "up", "down", "up", "down" }, nil, function()
		local here = player().position
		assert(monkey.position.x == here.x and monkey.position.y == here.y, "the monkey has grabbed the player")
		testsApi.play({ "right", "right", "right", "right" }, nil, function()
			assert(not Entities.entityExists(monkey.id), "the monkey should be dead")
			assert(#piles() == 0 and gold() == goldBefore, "a grabbing monkey leaves no gold")
			assert(player().grooveChain.killCount == 0, "and does not extend the chain")
			finish()
		end)
	end)
end)
