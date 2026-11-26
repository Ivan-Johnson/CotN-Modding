local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Most tests play Cadence in no-beat mode on an open floor with 100 health, so
-- a hit shows as a small drop. The player starts at (0,0). A Skeleton next to
-- the player hits on the third beat and every second beat after.

local player = fixtures.player
local health = fixtures.health

local function setHealth(entity, amount)
	entity.health.maxHealth = amount
	entity.health.health = amount
end

local function grant(...)
	for _, itemType in ipairs({ ... }) do
		Inventory.grant(itemType, player())
	end
end

-- Reading a component an entity lacks raises an error.
local function hasComponent(entity, name)
	return (pcall(function()
		assert(entity[name] ~= nil)
	end))
end

-- A scene whose checks assert the player's health after the given actions.
local function healthScene(name, actions, setup, expected)
	local checks = {}
	for index, want in pairs(expected) do
		checks[index] = function(state)
			assert(health() == want, string.format("after action %d: expected %d health, got %d", index, want, health()))
			if state.check then
				state.check(index)
			end
		end
	end
	fixtures.scene({
		name = name,
		actions = actions,
		setup = function()
			setHealth(player(), 100)
			return setup() or {}
		end,
		checks = checks,
	})
end

-- Armor takes its reduction off an enemy's hit, but a hit costs at least 1.
healthScene("damageArmorReducesEnemyHit", fixtures.repeated("idle", 3), function()
	grant("ArmorChainmail")
	fixtures.spawn("Skeleton3", 1, 0)
end, { [3] = 98 })

healthScene("damageArmorLeavesAtLeastOne", fixtures.repeated("idle", 3), function()
	grant("ArmorPlatemail")
	fixtures.spawn("Skeleton", 1, 0)
end, { [3] = 99 })

-- Armor reduces a bomb's blast like an enemy's hit.
healthScene("damageArmorReducesBlast", { "bomb", "idle", "idle", "idle" }, function()
	grant("Bomb", "ArmorChainmail")
end, { [4] = 98 })

-- Spike traps only spring to the beat, so these tests play in beat mode; the
-- first wait lets the invincibility a level starts with run out.
for _, case in ipairs({ { "ArmorChainmail", 2 }, { "FeetBootsLead", 0 } }) do
	local itemType, loss = case[1], case[2]
	testsApi.registerTest({
		name = "damageSpikeTrap" .. itemType,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			fixtures.openArena(6)
			setHealth(player(), 100)
			grant(itemType)
			local position = player().position
			fixtures.spawn("SpikeTrap", position.x + 1, position.y)
			testsApi.afterTicks(1200, function()
				testsApi.play({ "right" }, nil, function()
					testsApi.afterTicks(1500, function()
						local lost = 100 - health()
						assert(lost == loss, string.format("spikes with %s cost %d, expected %d", itemType, lost, loss))
						finish()
					end)
				end)
			end)
		end,
	})
end

-- A Blast Helm stops your own bomb's blast, which still hurts a slime beside you.
fixtures.scene({
	name = "damageBlastHelmStopsBlast",
	actions = { "bomb", "idle", "idle", "idle" },
	setup = function()
		setHealth(player(), 100)
		grant("Bomb", "HeadBlastHelm")
		local slime = fixtures.spawn("Slime", -1, 0)
		setHealth(slime, 10)
		return { slime = slime }
	end,
	checks = {
		[4] = function(state)
			assert(state.slime.health.health == 6, "the blast went off: slime at " .. state.slime.health.health)
			assert(health() == 100, "the helm stops the blast, health " .. health())
		end,
	},
})

-- A hit makes you invincible on the next beat: the skeleton's hit on beat 3
-- stops the blast of the bomb placed on beat 1, which goes off on beat 4.
healthScene("damageInvincibleOnBeatAfterHit", { "bomb", "idle", "idle", "idle" }, function()
	grant("Bomb")
	local skeleton = fixtures.spawn("Skeleton", 1, 0)
	return {
		check = function(index)
			if index == 4 then
				assert(not Entities.entityExists(skeleton.id), "the blast went off and killed the skeleton")
			end
		end,
	}
end, { [3] = 99, [4] = 99 })

-- Hits two beats apart both land.
healthScene("damageHitsTwoBeatsApartLand", fixtures.repeated("idle", 5), function()
	fixtures.spawn("Skeleton", 1, 0)
end, { [3] = 99, [5] = 98 })

-- Several enemies hitting on one beat cost one hit, the hardest one's here,
-- whichever side or spawn order.
for _, case in ipairs({
	{ "SkeletonFirst", { { "Skeleton", 1, 0 }, { "Skeleton3", -1, 0 } } },
	{ "Skeleton3First", { { "Skeleton3", 1, 0 }, { "Skeleton", -1, 0 } } },
	{ "Vertical", { { "Skeleton", 0, -1 }, { "Skeleton3", 0, 1 } } },
}) do
	healthScene("damageOneHitPerBeat" .. case[1], fixtures.repeated("idle", 5), function()
		for _, spot in ipairs(case[2]) do
			fixtures.spawn(spot[1], spot[2], spot[3])
		end
	end, { [3] = 96, [5] = 92 })
end

-- Which hit lands is the acting order's choice: with their priorities
-- swapped, the skeleton strikes first and only its 1 lands.
healthScene("damageOneHitPerBeatFollowsPriority", fixtures.repeated("idle", 5), function()
	local weak = fixtures.spawn("Skeleton", 1, 0)
	local strong = fixtures.spawn("Skeleton3", -1, 0)
	weak.priority.value, strong.priority.value = strong.priority.value, weak.priority.value
end, { [3] = 99, [5] = 98 })

-- Minibosses act before every other zone one enemy; within each
-- group, an enemy that hits harder acts first. Slime and monkeys never hit.
testsApi.registerTest({
	name = "damagePriorityOrdersByDamage",
	onLoad = function()
		local minibosses = { BatMiniboss = true, Minotaur = true, Minotaur2 = true, Dragon = true, Dragon2 = true }
		local hitters = {}
		for _, typeName in ipairs({
			"Slime2", "Slime3", "Skeleton", "Skeleton2", "Skeleton3", "Zombie", "Bat", "Bat2", "Bat3", "Ghost",
			"Wraith", "Trapchest6", "BatMiniboss", "Minotaur", "Minotaur2", "Dragon", "Dragon2",
		}) do
			local entity = fixtures.spawn(typeName, 5, 5)
			hitters[#hitters + 1] = {
				name = typeName,
				miniboss = minibosses[typeName] and 1 or 0,
				damage = entity.innateAttack.damage,
				priority = entity.priority.value,
			}
		end
		for _, a in ipairs(hitters) do
			for _, b in ipairs(hitters) do
				if a.miniboss > b.miniboss or (a.miniboss == b.miniboss and a.damage > b.damage) then
					assert(a.priority > b.priority, string.format("%s acts after %s", a.name, b.name))
				end
			end
		end
	end,
})

-- Nothing hurts you on a level's first beat: a skeleton set to attack on
-- beat 1 misses, and the control without the invincibility takes the hit.
local function firstBeatTest(name, level, removeInvincibility, expectedLoss)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			local function go()
				fixtures.openArena(6)
				setHealth(player(), 100)
				local position = player().position
				local skeleton = fixtures.spawn("Skeleton", position.x + 1, position.y)
				skeleton.beatDelay.counter = 0
				if removeInvincibility then
					player().invincibility.remainingTurns = 0
				end
				testsApi.play({ "idle" }, function()
					assert(skeleton.beatDelay.counter == 1, "the skeleton acted on beat 1")
					local lost = 100 - health()
					assert(lost == expectedLoss, string.format("level %d beat 1 cost %d", level, lost))
				end, finish)
			end
			if level == 1 then
				go()
				return
			end
			-- A jump requested from the level's load handler is dropped.
			testsApi.afterTicks(30, function()
				GameSession.goToLevel(level)
				local function poll()
					if CurrentLevel.getNumber() == level then
						-- The new level's entities settle a moment after the number changes.
						testsApi.afterTicks(300, go)
					else
						testsApi.afterTicks(10, poll)
					end
				end
				poll()
			end)
		end,
	})
end
firstBeatTest("damageFirstBeatOfLevel1", 1, false, 0)
firstBeatTest("damageFirstBeatOfLevel2", 2, false, 0)
firstBeatTest("damageFirstBeatControl", 2, true, 1)

-- Enemies have no invincibility: a dagger hits a slime on every beat, and no
-- enemy the level starts with has invincibility on hit.
fixtures.scene({
	name = "damageEnemiesHaveNoInvincibility",
	actions = fixtures.repeated("right", 3),
	setup = function()
		local levelEnemies = 0
		for entity in Entities.entitiesWithComponents({ "ai", "health" }) do
			levelEnemies = levelEnemies + 1
			assert(not hasComponent(entity, "invincibilityOnHit"), entity.name .. " has invincibility on hit")
		end
		assert(levelEnemies > 0, "the level has enemies")
		local slime = fixtures.spawn("Slime", 1, 0)
		setHealth(slime, 20)
		return { slime = slime }
	end,
	checks = {
		[3] = function(state)
			assert(state.slime.health.health == 17, "three hits on three beats, slime at " .. state.slime.health.health)
		end,
	},
})

-- Your hit: the weapon's damage, doubled by a lunge, then 1 more for each of
-- Sunglasses and the Ring of Might.
for _, case in ipairs({
	{ "RingMight", nil, { "RingMight" }, 1, 2 },
	{ "SunglassesAndRingMight", nil, { "HeadSunglasses", "RingMight" }, 1, 3 },
	{ "LungeThenSunglasses", "WeaponTitaniumRapier", { "HeadSunglasses" }, 2, 5 },
}) do
	local name, weapon, items, distance, damage = case[1], case[2], case[3], case[4], case[5]
	fixtures.scene({
		name = "damageDealt" .. name,
		actions = { "right" },
		setup = function()
			if weapon then
				grant(weapon)
			end
			for _, itemType in ipairs(items) do
				grant(itemType)
			end
			local slime = fixtures.spawn("Slime", distance, 0)
			setHealth(slime, 50)
			return { slime = slime }
		end,
		checks = {
			[1] = function(state)
				local dealt = 50 - state.slime.health.health
				assert(dealt == damage, string.format("%s dealt %d, expected %d", name, dealt, damage))
			end,
		},
	})
end

-- The Blood Drum's cost lands while you are invincible and leaves you open:
-- skeleton hits on beat 3, drum on beat 4, skeleton hits again on beat 5.
healthScene("damageBloodDrumIgnoresInvincibility", { "idle", "idle", "idle", "item1", "idle" }, function()
	grant("BloodDrum")
	fixtures.spawn("Skeleton", 1, 0)
end, { [3] = 99, [4] = 98, [5] = 97 })
