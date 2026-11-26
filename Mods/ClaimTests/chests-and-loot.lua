local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"
local ItemStorage = require "necro.game.item.ItemStorage"
local Object = require "necro.game.object.Object"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Contents are sampled one container every few ticks: spawning many
-- containers on one tick exhausts the item pools and leaves later ones empty,
-- which a level never does.

local function holds(typeName)
	for _, item in ipairs(Inventory.getItems(fixtures.player())) do
		if item.name == typeName then
			return true
		end
	end
	return false
end

-- Names of the loose entities (not the player or what it holds) on a tile.
local function namesAt(x, y)
	local player = fixtures.player()
	local skip = { [player.id] = true }
	for _, item in ipairs(Inventory.getItems(player)) do
		skip[item.id] = true
	end
	local names = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local position = entity.position
		if position.x == x and position.y == y and not skip[entity.id] and entity.name ~= "CadenceHead" then
			names[#names + 1] = entity.name
		end
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- Replaces a container's contents with one new typeName.
local function fill(container, typeName)
	ItemStorage.clear(container)
	ItemStorage.store(Object.spawn(typeName, 20, 20), container)
end

local function startsWithAny(name, prefixes)
	for _, prefix in ipairs(prefixes) do
		if name:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function slotOf(entity)
	return entity.itemSlot and entity.itemSlot.name or "none"
end

-- Spawns count containers of typeName, a few ticks apart, and calls
-- check(items) with each one's contents, then after() if given.
local function sampleTest(name, typeName, count, check, after)
	testsApi.registerTest({
		name = name,
		async = true,
		onLoad = function(_, finish)
			local done = 0
			local function nextSample()
				if done == count then
					if after then
						after()
					end
					finish()
					return
				end
				done = done + 1
				local container = fixtures.spawn(typeName, 6, 6)
				check(ItemStorage.getItems(container))
				Object.delete(container)
				testsApi.afterTicks(3, nextSample)
			end
			nextSample()
		end,
	})
end

------------------------------------------------------------------ opening

-- Bumping a chest opens it: its item lies on the chest's tile and the player
-- stays. The next step onto the tile picks the item up.
for _, chest in ipairs({ "ChestBlack", "ChestRed", "ChestPurple" }) do
	fixtures.scene({
		name = "lootOpen" .. chest,
		actions = { "right", "right" },
		setup = function()
			local state = { chest = fixtures.spawn(chest, 1, 0) }
			fill(state.chest, "ArmorLeather")
			return state
		end,
		checks = {
			[1] = function(state)
				assert(not Entities.entityExists(state.chest.id), chest .. ": the bump opens the chest")
				fixtures.assertAt(fixtures.player(), 0, 0, chest .. ": opening")
				assert(namesAt(1, 0) == "ArmorLeather", chest .. ": the item lies on its tile: " .. namesAt(1, 0))
			end,
			[2] = function()
				fixtures.assertAt(fixtures.player(), 1, 0, chest .. ": stepping onto the item")
				assert(holds("ArmorLeather"), chest .. ": stepping onto the item picks it up")
			end,
		},
	})
end

-- A locked chest ignores a bump without a key.
fixtures.scene({
	name = "lootLockedNeedsKey",
	actions = { "right", "right" },
	setup = function()
		return { chest = fixtures.spawn("ChestLocked", 1, 0) }
	end,
	checks = {
		[2] = function(state)
			assert(Entities.entityExists(state.chest.id), "a locked chest stays shut without a key")
			fixtures.assertAt(fixtures.player(), 0, 0, "bumping a locked chest")
		end,
	},
})

-- A key picked up on the way opens it, and is used up.
fixtures.scene({
	name = "lootLockedKeyUsedUp",
	actions = { "right", "right" },
	setup = function()
		fixtures.spawn("MiscKey", 1, 0)
		local state = { chest = fixtures.spawn("ChestLocked", 2, 0) }
		fill(state.chest, "ArmorLeather")
		return state
	end,
	checks = {
		[1] = function()
			assert(holds("MiscKey"), "walking onto the key picks it up")
		end,
		[2] = function(state)
			assert(not Entities.entityExists(state.chest.id), "the key opens the locked chest")
			assert(not holds("MiscKey"), "the key is used up")
			assert(namesAt(2, 0) == "ArmorLeather", "the item lies on its tile: " .. namesAt(2, 0))
		end,
	},
})

------------------------------------------------------------------ contents

-- Each colour draws from its own pool. The pool lists every item the colour
-- can hold in any zone; a sample of chests shows the chests use it.
local POOLS = {
	ChestBlack = "itemPoolBlackChest",
	ChestRed = "itemPoolRedChest",
	ChestPurple = "itemPoolPurpleChest",
	ChestLocked = "itemPoolLockedChest",
}

local function poolSlots(pool)
	local slots = {}
	local names = {}
	for _, prototype in Entities.prototypesWithComponents({ pool }) do
		slots[slotOf(prototype)] = true
		names[#names + 1] = prototype.name
	end
	return slots, names
end

for chest, pool in pairs(POOLS) do
	sampleTest("lootChestUsesPool" .. chest, chest, 20, function(items)
		assert(#items == 1, chest .. " holds " .. #items .. " items")
		assert(items[1][pool], chest .. " held " .. items[1].name .. ", outside " .. pool)
	end)
end

-- Black: weapons, body armor, boots and shields, and nothing else.
testsApi.registerTest({
	name = "lootBlackChestPool",
	onLoad = function()
		local slots = poolSlots("itemPoolBlackChest")
		for _, slot in ipairs({ "weapon", "body", "feet", "shield" }) do
			assert(slots[slot], "black chests hold " .. slot)
			slots[slot] = nil
		end
		assert(next(slots) == nil, "black chests hold only weapons, armor, boots and shields: " .. tostring(next(slots)))
	end,
})

-- Purple: rings, spells, and scrolls and tomes (one-use items), nothing else.
testsApi.registerTest({
	name = "lootPurpleChestPool",
	onLoad = function()
		local _, names = poolSlots("itemPoolPurpleChest")
		local found = {}
		for _, name in ipairs(names) do
			local kind = name:gsub("^Sync_", ""):match("^(%u%l+)")
			assert(kind == "Ring" or kind == "Spell" or kind == "Scroll" or kind == "Tome", "purple holds " .. name)
			found[kind] = true
		end
		assert(found.Ring and found.Spell and found.Scroll and found.Tome, "purple holds all four kinds")
	end,
})

-- Red: consumables and small gear; never a weapon, armor, boots, a shield, a
-- ring or a spell.
testsApi.registerTest({
	name = "lootRedChestPool",
	onLoad = function()
		local slots, names = poolSlots("itemPoolRedChest")
		for _, slot in ipairs({ "weapon", "body", "feet", "shield", "ring", "spell" }) do
			assert(not slots[slot], "red chests hold no " .. slot)
		end
		for _, prefix in ipairs({ "Food", "Torch", "Charm", "Head", "Bomb", "Familiar", "Shovel", "Pickaxe", "HolyWater" }) do
			local any = false
			for _, name in ipairs(names) do
				any = any or startsWithAny(name, { prefix })
			end
			assert(any, "red chests hold " .. prefix)
		end
	end,
})

-- Locked: heart containers, magic food and rarer gear; never a weapon or a
-- spell.
testsApi.registerTest({
	name = "lootLockedChestPool",
	onLoad = function()
		local slots, names = poolSlots("itemPoolLockedChest")
		assert(not slots.weapon and not slots.spell, "locked chests hold no weapon or spell")
		for _, prefix in ipairs({ "MiscHeartContainer", "FoodMagic", "Feet", "Head", "Ring", "Charm", "Shovel" }) do
			local any = false
			for _, name in ipairs(names) do
				any = any or startsWithAny(name, { prefix })
			end
			assert(any, "locked chests hold " .. prefix)
		end
	end,
})

-- A crate or barrel holds one thing: food, coins, a bomb, an enemy, or now
-- and then an item from the locked chest pool.
for _, crate in ipairs({ "Crate", "Crate2" }) do
	local seen = {}
	sampleTest("lootCrateContents" .. crate, crate, 80, function(items)
		assert(#items == 1, crate .. " holds " .. #items .. " items")
		local item = items[1]
		local kind = (startsWithAny(item.name, { "Food" }) and "food")
			or (startsWithAny(item.name, { "ResourceCoin" }) and "coins")
			or (startsWithAny(item.name, { "Bomb" }) and "bomb")
			or (item.itemPoolLockedChest and "locked")
			or (item.ai and "enemy")
		assert(kind, crate .. " held " .. item.name)
		seen[kind] = true
	end, function()
		for _, kind in ipairs({ "food", "coins", "bomb", "enemy", "locked" }) do
			assert(seen[kind], crate .. ": no " .. kind .. " turned up")
		end
	end)
end

-- Teh Urn holds three: an item, a spell and food.
sampleTest("lootUrnContents", "Crate3", 10, function(items)
	assert(#items == 3, "the urn holds " .. #items .. " items")
	assert(slotOf(items[2]) == "spell", "the urn's second item is a spell: " .. items[2].name)
	assert(startsWithAny(items[3].name, { "Food" }), "the urn's third item is food: " .. items[3].name)
end)

-- A broken crate leaves what it held on its tile, and an enemy inside comes
-- out alive. The bomb that breaks it does not destroy the contents.
for _, content in ipairs({ "Food1", "ResourceCoin10", "Skeleton" }) do
	fixtures.scene({
		name = "lootCrateBreaks" .. content,
		actions = { "bomb", "left", "left", "idle" },
		setup = function()
			local state = { crate = fixtures.spawn("Crate", 1, 0) }
			fill(state.crate, content)
			return state
		end,
		checks = {
			[4] = function(state)
				assert(not Entities.entityExists(state.crate.id), "the bomb breaks the crate")
				assert(namesAt(1, 0) == content, "the crate leaves " .. content .. ", found: " .. namesAt(1, 0))
			end,
		},
	})
end

------------------------------------------------------------------ equipment

-- Body armor takes 1, 2 or 3 off a hit, but a hit always costs at least 1.
-- A Skeleton3 hits for 4 and a Skeleton for 1; both strike on the third beat.
for _, case in ipairs({
	{ "Skeleton3", nil, 4 },
	{ "Skeleton3", "ArmorLeather", 3 },
	{ "Skeleton3", "ArmorChainmail", 2 },
	{ "Skeleton3", "ArmorPlatemail", 1 },
	{ "Skeleton", nil, 1 },
	{ "Skeleton", "ArmorPlatemail", 1 },
}) do
	local enemy, armor, loss = case[1], case[2], case[3]
	fixtures.scene({
		name = "lootArmor" .. enemy .. (armor or "None"),
		actions = fixtures.repeated("idle", 3),
		setup = function()
			if armor then
				Inventory.grant(armor, fixtures.player())
			end
			fixtures.spawn(enemy, 1, 0)
		end,
		checks = {
			[3] = function()
				local lost = 12 - fixtures.health()
				assert(lost == loss, string.format("%s vs %s: lost %d, expected %d", enemy, armor or "no armor", lost, loss))
			end,
		},
	})
end

-- Glass slippers break the first time you take damage.
fixtures.scene({
	name = "lootGlassSlippersBreak",
	actions = fixtures.repeated("idle", 3),
	setup = function()
		Inventory.grant("FeetGlassSlippers", fixtures.player())
		fixtures.spawn("Skeleton", 1, 0)
	end,
	checks = {
		[2] = function()
			assert(holds("FeetGlassSlippers"), "the slippers are worn until a hit")
		end,
		[3] = function()
			assert(fixtures.health() == 11, "the hit lands")
			assert(not holds("FeetGlassSlippers"), "the slippers break")
		end,
	},
})

-- Sunglasses add 1 to every hit you deal.
for _, case in ipairs({ { nil, 1 }, { "HeadSunglasses", 2 } }) do
	local head, damage = case[1], case[2]
	fixtures.scene({
		name = "lootSunglasses" .. (head or "None"),
		actions = { "right" },
		setup = function()
			if head then
				Inventory.grant(head, fixtures.player())
			end
			local slime = fixtures.spawn("Slime", 1, 0)
			slime.health.health = 20
			slime.health.maxHealth = 20
			return { slime = slime }
		end,
		checks = {
			[1] = function(state)
				local dealt = 20 - state.slime.health.health
				assert(dealt == damage, string.format("dagger with %s dealt %d", head or "no hat", dealt))
			end,
		},
	})
end
