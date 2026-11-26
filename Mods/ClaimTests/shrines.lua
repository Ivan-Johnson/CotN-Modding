local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence in no-beat mode on an open floor, from (0,0), with
-- a shrine spawned by hand, by default at (1,0) so "right" walks into it.
-- "up" is toward negative y, so the row below a shrine at (1,0) is y = 1.
-- Rewards are random, so the tests check their kind and place, not the item.

local player = fixtures.player
local health = fixtures.health

-- The shrines that level generation can place, with their hint text.
local HINTS = {
	ShrineOfBlood = "Give blood, get blood weapon",
	ShrineOfBoss = "Gain items, extra miniboss",
	ShrineOfChance = "Win items, if you're lucky",
	ShrineOfDarkness = "Turns out the lights",
	ShrineOfGlass = "All items become glass",
	ShrineOfPain = "Take hits near me",
	ShrineOfPeace = "Lose items, gain health",
	ShrineOfRhythm = "Items become obsidian, irregular rhythm",
	ShrineOfRisk = "Gain items, slowly lose health",
	ShrineOfSacrifice = "Requires sacrifices",
	ShrineOfSpace = "Gain shovel, bigger levels",
	ShrineOfUncertainty = "Get mystery weapon",
	ShrineOfWar = "Gain items, tougher enemies",
	Sync_ShrineOfFeast = "Overeat near me",
	Sync_ShrineOfFire = "Hit me with fire",
}

-- Names of the items the player carries, sorted, as one string.
local function carried()
	local names = {}
	for _, item in ipairs(Inventory.getItems(player())) do
		table.insert(names, item.name)
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function countCarried(name)
	local count = 0
	for _, item in ipairs(Inventory.getItems(player())) do
		if item.name == name then
			count = count + 1
		end
	end
	return count
end

local function carries(name)
	return countCarried(name) > 0
end

local function slotItem(slot)
	local item = Inventory.getItemsInSlot(player(), slot)[1]
	return item and item.name or "none"
end

local function grant(names)
	for _, name in ipairs(names) do
		Inventory.grant(name, player())
	end
end

-- Names of the unheld items on tile (x, y).
local function itemsAt(x, y)
	local names = {}
	for entity in Entities.entitiesWithComponents({ "item", "position" }) do
		if entity.item.holder == 0 and entity.position.x == x and entity.position.y == y then
			table.insert(names, entity.name)
		end
	end
	return names
end

-- Every unheld item within radius of (0,0), as sorted "name@x,y" strings.
local function itemsNear(radius)
	local found = {}
	for entity in Entities.entitiesWithComponents({ "item", "position" }) do
		local position = entity.position
		if entity.item.holder == 0 and math.abs(position.x) <= radius and math.abs(position.y) <= radius then
			table.insert(found, string.format("%s@%d,%d", entity.name, position.x, position.y))
		end
	end
	table.sort(found)
	return found
end

-- One item on each of the three tiles in the row below (x, y).
local function assertRowBelow(x, y, what)
	for dx = -1, 1 do
		assert(#itemsAt(x + dx, y + 1) == 1, string.format("%s: expected one item at (%d,%d)", what, x + dx, y + 1))
	end
end

-- Registers a scene with a shrine of type spec.shrine at (spec.sx, spec.sy),
-- default (1,0); spec.setup(shrine) may change the scene, and every check
-- gets the shrine.
local function shrineScene(name, spec)
	fixtures.scene({
		name = name,
		radius = 8,
		setup = function()
			assert(player().name == "Cadence", "expected to play Cadence, got " .. player().name)
			local shrine = fixtures.spawn(spec.shrine, spec.sx or 1, spec.sy or 0)
			if spec.setup then
				spec.setup(shrine)
			end
			return shrine
		end,
		actions = spec.actions,
		checks = spec.checks,
	})
end

-- What a shrine use can change, to show that a second use did nothing.
local function snapshot()
	local entity = player()
	return string.format(
		"%d/%d %d %s %s",
		health(),
		entity.health.maxHealth,
		entity.goldCounter.amount,
		carried(),
		table.concat(itemsNear(3), ",")
	)
end

-- A single-player level can hold the shrines in HINTS: all of them in an
-- all-zones run, all but the Shrine of Rhythm in a single-zone run. The two
-- multiplayer shrines are in both pools but excluded from single player.
local MULTIPLAYER = { Sync_ShrineOfBinding = true, Sync_ShrineOfDuplication = true }
testsApi.registerTest({
	name = "shrinesInLevelPools",
	onLoad = function()
		local pooled = {}
		for _, typeName in ipairs(Entities.getEntityTypesWithComponents({ "shrine" })) do
			local prototype = Entities.getEntityPrototype(typeName)
			local all = prototype.shrinePoolAllZones and prototype.shrinePoolAllZones.weight or 0
			local single = prototype.shrinePoolSingleZone and prototype.shrinePoolSingleZone.weight or 0
			local multiplayerOnly = prototype.shrinePoolExcludeFromSinglePlayer ~= nil
			assert(multiplayerOnly == (MULTIPLAYER[typeName] == true), typeName .. " single-player exclusion")
			if all > 0 and not multiplayerOnly then
				local hint = prototype.shrineHintLabel.text
				assert(HINTS[typeName] == hint, typeName .. " hint reads " .. tostring(hint))
				assert((single > 0) == (typeName ~= "ShrineOfRhythm"), typeName .. " single-zone weight " .. single)
				pooled[typeName] = true
			else
				assert(single == 0 or multiplayerOnly, typeName .. " is only in the single-zone pool")
			end
		end
		for typeName in pairs(HINTS) do
			assert(pooled[typeName], typeName .. " is on the page but not in the all-zones pool")
		end
	end,
})

-- A walk-in shrine is solid, works on the first bump, and a second bump does
-- nothing. check(shrine) asserts the first bump's effect.
local function walkIn(name, shrineType, setup, check)
	local before
	shrineScene(name, {
		shrine = shrineType,
		setup = setup,
		actions = { "right", "right" },
		checks = {
			[1] = function(shrine)
				assert(player().position.x == 0, "the shrine is solid")
				assert(shrine.shrine.active, "the bump uses the shrine")
				check(shrine)
				before = snapshot()
			end,
			[2] = function()
				assert(snapshot() == before, "a second bump does nothing: " .. snapshot())
			end,
		},
	})
end

-- Blood: health drops to 1 from any amount, the weapon becomes a blood weapon
-- and the old one lands on the player's tile, and a Blood Shovel appears below.
for _, start in ipairs({ { 20, 20 }, { 5, 12 } }) do
	walkIn("shrineBloodFrom" .. start[1], "ShrineOfBlood", function()
		player().health.maxHealth = start[2]
		player().health.health = start[1]
	end, function()
		assert(health() == 1, "health drops to 1, got " .. health())
		assert(slotItem("weapon"):find("Blood"), "a blood weapon, got " .. slotItem("weapon"))
		assert(itemsAt(0, 0)[1] == "WeaponDagger", "the old weapon is dropped on the player's tile")
		assert(itemsAt(1, 1)[1] == "ShovelBlood", "a Blood Shovel below the shrine")
	end)
end

-- Boss: three items in the row below.
walkIn("shrineBossThreeBelow", "ShrineOfBoss", nil, function()
	assertRowBelow(1, 0, "boss")
end)

-- Darkness: Map, Compass and Ring of Shadows; the torch and the old ring are
-- destroyed, not dropped.
walkIn("shrineDarknessTakesTorchAndRing", "ShrineOfDarkness", function()
	grant({ "RingCourage", "Torch2" })
end, function()
	for _, name in ipairs({ "MiscMap", "MiscCompass", "RingShadows" }) do
		assert(carries(name), "gives " .. name)
	end
	assert(not carries("RingCourage") and not carries("Torch2"), "the ring and torch go: " .. carried())
	assert(#itemsNear(3) == 0, "nothing is dropped: " .. table.concat(itemsNear(3), ","))
end)

-- Glass: weapon, shovel, armor, headgear, boots and torch turn to glass; the
-- ring, charm, spell and holy water stay.
walkIn("shrineGlassTurnsGearToGlass", "ShrineOfGlass", function()
	grant({ "ArmorLeather", "HeadMinersCap", "FeetBootsExplorers", "TorchInfernal" })
	grant({ "RingCourage", "CharmStrength", "SpellFireball", "HolyWater" })
end, function()
	for slot, glass in pairs({
		weapon = "WeaponGlassDagger",
		shovel = "ShovelGlass",
		body = "ArmorGlass",
		head = "HeadGlassJaw",
		feet = "FeetGlassSlippers",
		torch = "TorchGlass",
	}) do
		assert(slotItem(slot) == glass, slot .. " should be " .. glass .. ", got " .. slotItem(slot))
	end
	for _, name in ipairs({ "RingCourage", "CharmStrength", "SpellFireball", "HolyWater" }) do
		assert(carries(name), name .. " stays")
	end
end)

-- Rhythm: weapon, shovel and armor turn to obsidian; the ring stays.
walkIn("shrineRhythmTurnsGearToObsidian", "ShrineOfRhythm", function()
	grant({ "ArmorLeather", "RingCourage" })
end, function()
	for slot, obsidian in pairs({ weapon = "WeaponObsidianDagger", shovel = "ShovelObsidian", body = "ArmorObsidian" }) do
		assert(slotItem(slot) == obsidian, slot .. " should be " .. obsidian .. ", got " .. slotItem(slot))
	end
	assert(carries("RingCourage"), "the ring stays")
end)

-- Peace: one more heart container and full health, and no item is taken.
local peaceKit
walkIn("shrinePeaceHealsAndAddsHeart", "ShrineOfPeace", function()
	player().health.health = 3
	grant({ "ArmorLeather", "RingCourage", "CharmStrength", "SpellFireball", "HeadMinersCap" })
	peaceKit = carried()
end, function()
	assert(player().health.maxHealth == 14 and health() == 14, "health 14/14, got " .. health())
	assert(carried() == peaceKit, "items kept: " .. carried())
end)

-- Risk: Bag of Holding and two Food1 into the inventory, three items below.
walkIn("shrineRiskGivesBagFoodAndRow", "ShrineOfRisk", nil, function()
	assert(carries("BagHolding"), "a Bag of Holding")
	assert(countCarried("Food1") == 2, "two Food1, got " .. countCarried("Food1"))
	assertRowBelow(1, 0, "risk")
end)

-- Space: three shovels in the row below.
walkIn("shrineSpaceThreeShovels", "ShrineOfSpace", nil, function()
	for dx = 0, 2 do
		local name = itemsAt(dx, 1)[1] or "none"
		assert(Entities.getEntityPrototype(name).itemSlot.name == "shovel", name .. " is a shovel")
	end
end)

-- Uncertainty: a random uncertain weapon; the old one lands on the player's tile.
walkIn("shrineUncertaintyMysteryWeapon", "ShrineOfUncertainty", nil, function()
	assert(slotItem("weapon"):find("Uncertain$"), "an uncertain weapon, got " .. slotItem("weapon"))
	assert(itemsAt(0, 0)[1] == "WeaponDagger", "the old weapon is dropped on the player's tile")
end)

-- War: two items straight into the inventory, none on the floor.
local warBefore
walkIn("shrineWarTwoItems", "ShrineOfWar", function()
	warBefore = #Inventory.getItems(player())
end, function()
	assert(#Inventory.getItems(player()) == warBefore + 2, "two more items: " .. carried())
	assert(#itemsNear(3) == 0, "nothing on the floor")
end)

-- Taking one item of the row below makes the other two vanish; a shovel taken
-- from Space swaps with the carried one.
for _, shrineType in ipairs({ "ShrineOfBoss", "ShrineOfRisk", "ShrineOfSpace" }) do
	shrineScene("shrineRowIsOneChoice" .. shrineType, {
		shrine = shrineType,
		actions = { "right", "down" },
		checks = {
			[2] = function()
				assert(#itemsAt(1, 1) == 0 and #itemsAt(2, 1) == 0, "the other two vanish")
				if shrineType == "ShrineOfSpace" then
					assert(slotItem("shovel") ~= "ShovelBasic", "took a shovel from the row")
					assert(itemsAt(0, 1)[1] == "ShovelBasic", "the old shovel is left on that tile")
				end
			end,
		},
	})
end

-- Chance: 10 gold, doubling each use, any number of uses; some uses drop an
-- item. With too little gold nothing happens.
local CHANCE_USES = 8
local chanceChecks = {}
for use = 1, CHANCE_USES do
	local paid = 10 * (2 ^ use - 1)
	chanceChecks[use] = function(shrine)
		local gold = player().goldCounter.amount
		assert(gold == 10000 - paid, string.format("after use %d expected %d gold, got %d", use, 10000 - paid, gold))
		if use == CHANCE_USES then
			local drops = #itemsNear(3)
			assert(drops > 0 and drops < CHANCE_USES, "some uses, not all, drop an item: " .. drops)
			assert(not shrine.shrine.active, "it never runs out")
		end
	end
end
shrineScene("shrineChancePriceDoubles", {
	shrine = "ShrineOfChance",
	setup = function()
		player().goldCounter.amount = 10000
	end,
	actions = fixtures.repeated("right", CHANCE_USES),
	checks = chanceChecks,
})
shrineScene("shrineChanceTooPoor", {
	shrine = "ShrineOfChance",
	setup = function()
		player().goldCounter.amount = 9
	end,
	actions = { "right" },
	checks = {
		[1] = function()
			assert(player().goldCounter.amount == 9 and #itemsNear(3) == 0, "nothing happens")
		end,
	},
})

-- Shrines that a bump does not use.
for _, shrineType in ipairs({ "ShrineOfPain", "ShrineOfSacrifice", "Sync_ShrineOfFeast", "Sync_ShrineOfFire" }) do
	shrineScene("shrineBumpDoesNotUse" .. shrineType, {
		shrine = shrineType,
		actions = { "right" },
		checks = {
			[1] = function(shrine)
				assert(player().position.x == 0, "the shrine is solid")
				assert(not shrine.shrine.active and #itemsNear(3) == 0, "the bump does nothing")
			end,
		},
	})
end

-- Sacrifice: five kills on a tile orthogonally beside it, then three items below.
local sacrificeChecks = {}
for kill = 1, 5 do
	sacrificeChecks[kill] = function(shrine)
		assert(shrine.shrine.active == (kill == 5), "active only after the fifth kill, not kill " .. kill)
		if kill < 5 then
			fixtures.spawn("Slime", 1, 0)
		else
			assertRowBelow(2, 0, "sacrifice")
		end
	end
end
shrineScene("shrineSacrificeFiveKills", {
	shrine = "ShrineOfSacrifice",
	sx = 2,
	setup = function()
		fixtures.spawn("Slime", 1, 0)
	end,
	actions = fixtures.repeated("right", 5),
	checks = sacrificeChecks,
})
-- A kill on a diagonal or two tiles away does not count.
for _, at in ipairs({ { 2, 1, "Diagonal" }, { 3, 0, "TwoAway" } }) do
	shrineScene("shrineSacrificeIgnoresKill" .. at[3], {
		shrine = "ShrineOfSacrifice",
		sx = at[1],
		sy = at[2],
		setup = function()
			fixtures.spawn("Slime", 1, 0)
		end,
		actions = { "right" },
		checks = {
			[1] = function(shrine)
				assert(#itemsAt(1, 0) > 0, "the slime died and dropped gold")
				assert(shrine.shrineActivateOnDeath.remainingActivations == 5, "the kill did not count")
			end,
		},
	})
end

-- Pain: each hit taken orthogonally beside it drops an item beside the player,
-- five times, whatever the damage.
for _, enemy in ipairs({ "Skeleton", "Skeleton2" }) do
	shrineScene("shrinePainFiveHits" .. enemy, {
		shrine = "ShrineOfPain",
		sx = 0,
		sy = -1,
		setup = function()
			player().health.maxHealth = 60
			player().health.health = 60
			fixtures.spawn(enemy, 1, 0)
		end,
		actions = fixtures.repeated("idle", 14),
		checks = {
			[14] = function(shrine)
				assert(shrine.shrine.active, "active after five hits")
				assert(health() <= 60 - 6, "took six or more hits")
				local drops = itemsNear(1)
				assert(#drops == 5, "five items beside the player: " .. table.concat(drops, ","))
			end,
		},
	})
end
shrineScene("shrinePainIgnoresDiagonal", {
	shrine = "ShrineOfPain",
	sx = 1,
	sy = -1,
	setup = function()
		fixtures.spawn("Skeleton", 1, 0)
	end,
	actions = fixtures.repeated("idle", 6),
	checks = {
		[6] = function(shrine)
			assert(health() < 12, "the skeleton hit")
			assert(shrine.shrineActivateOnHit.remainingActivations == 5 and #itemsNear(2) == 0, "no hit counted")
		end,
	},
})
-- Taking one Pain item leaves the others.
shrineScene("shrinePainDropsAreAllYours", {
	shrine = "ShrineOfPain",
	sx = 0,
	sy = -1,
	setup = function(shrine)
		shrine.shrineActivateOnHit.remainingActivations = 2
		player().health.maxHealth = 40
		player().health.health = 40
		fixtures.spawn("Skeleton", 1, 0)
	end,
	actions = { "idle", "idle", "idle", "idle", "idle", "down", "left", "up" },
	checks = {
		[5] = function()
			assert(#itemsNear(1) == 2, "two hits, two items")
		end,
		[8] = function()
			local left = itemsNear(1)
			assert(#left == 1 and left[1]:find("^WeaponDagger@"), "took both; left: " .. table.concat(left, ","))
		end,
	},
})

-- Feast: eating at full health right beside it drops an item below it;
-- eating while hurt, or three tiles away, does not.
for _, case in ipairs({ { "Full", 1, 12, true }, { "Hurt", 1, 4, false }, { "Far", 3, 12, false } }) do
	local name, sx, startHealth, activates = case[1], case[2], case[3], case[4]
	shrineScene("shrineFeast" .. name, {
		shrine = "Sync_ShrineOfFeast",
		sx = sx,
		setup = function()
			player().health.health = startHealth
			grant({ "Food1" })
		end,
		actions = { "item1" },
		checks = {
			[1] = function(shrine)
				assert(not carries("Food1"), "the food was eaten")
				assert(shrine.shrine.active == activates, "activated: " .. tostring(shrine.shrine.active))
				assert((#itemsAt(sx, 1) == 1) == activates, "an item below only when activated")
			end,
		},
	})
end

-- Fire: a fireball or a bomb blast activates it, and three items appear below.
shrineScene("shrineFireFireball", {
	shrine = "Sync_ShrineOfFire",
	sx = 3,
	setup = function()
		grant({ "SpellFireball" })
	end,
	actions = { "spell1" },
	checks = {
		[1] = function(shrine)
			assert(shrine.shrine.active, "a fireball activates it")
			assertRowBelow(3, 0, "fire")
		end,
	},
})
shrineScene("shrineFireBomb", {
	shrine = "Sync_ShrineOfFire",
	actions = { "bomb", "left", "left", "idle" },
	checks = {
		[4] = function()
			assertRowBelow(1, 0, "fire")
		end,
	},
})

-- A bomb destroys a shrine, which leaves one item: for Blood, a Crown of
-- Thorns if unused and a Ring of Regeneration if used.
for _, case in ipairs({
	{ "Unused", { "bomb", "left", "left", "idle" }, "HeadCrownOfThorns" },
	{ "Used", { "right", "bomb", "left", "left", "idle" }, "RingRegeneration" },
}) do
	local name, actions, drop = case[1], case[2], case[3]
	shrineScene("shrineBombedBlood" .. name, {
		shrine = "ShrineOfBlood",
		actions = actions,
		checks = {
			[#actions] = function(shrine)
				assert(not Entities.entityExists(shrine.id), "the bomb destroys the shrine")
				local left = itemsAt(1, 0)[1]
				assert(left == drop, "leaves " .. drop .. ", got " .. tostring(left))
			end,
		},
	})
end
