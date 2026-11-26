local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Dove (Cadence where it shows the difference) in no-beat
-- mode, on an open floor unless it surveys a level; "up" is toward negative y.

local player = fixtures.player
local health = fixtures.health
local assertAt = fixtures.assertAt

local function freeze(entity)
	entity.beatDelay.interval = 100000
	entity.beatDelay.counter = 100000
end

-- An enemy that never acts on its own, so a test reads what Dove did to it.
local function frozen(typeName, x, y)
	local entity = fixtures.spawn(typeName, x, y)
	freeze(entity)
	return entity
end

local function goldPiles()
	local count = 0
	for entity in Entities.entitiesWithComponents({ "position", "itemCurrency" }) do
		if entity.name:find("^ResourceCoin") or entity.name:find("^ResourceHoardGold") then
			count = count + 1
		end
	end
	return count
end

-- Like fixtures.scene, but as spec.character (default Dove), keeping the
-- level's enemies of type spec.keepType. checks[#actions + 1], if given, runs
-- spec.lateTicks after the last action settles.
local function scene(spec)
	local checks = spec.checks
	testsApi.registerTest({
		name = spec.name,
		character = spec.character or "Dove",
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(8, spec.keepType)
			local state = spec.setup and spec.setup() or {}
			testsApi.play(spec.actions, function(index)
				if checks[index] then
					checks[index](state)
				end
			end, function()
				local late = checks[#spec.actions + 1]
				if not late then
					finish()
					return
				end
				testsApi.afterTicks(spec.lateTicks, function()
					late(state)
					finish()
				end)
			end)
		end,
	})
end

testsApi.registerTest({
	name = "doveStartingKit",
	character = "Dove",
	onLoad = function()
		assert(player().name == "Dove", "playing as " .. player().name)
		assert(health() == 14 and player().health.maxHealth == 14, "14 health")
		local held = {}
		for _, item in ipairs(Inventory.getItems(player())) do
			held[item.name] = true
		end
		for _, name in ipairs({ "Bomb", "WeaponFlower", "ShovelCrystal", "RingPeace" }) do
			assert(held[name], "starts with " .. name)
		end
		assert(not held.WeaponDagger, "no dagger")
	end,
})

-- The flower does no damage, and Dove stays put when she attacks. The first
-- tickle drops the enemy's gold; each one counts as a kill for the groove
-- chain. The wall behind the skeleton stops the knockback.
scene({
	name = "doveFlowerTickles",
	setup = function()
		fixtures.wallColumn(2, 0, 0)
		local skeleton = frozen("Skeleton", 1, 0)
		skeleton.health.health = 10
		skeleton.health.maxHealth = 10
		return skeleton
	end,
	actions = { "right", "right" },
	checks = {
		[1] = function(skeleton)
			assert(skeleton.health.health == 10, "no damage")
			assertAt(skeleton, 1, 0, "the wall stops the knockback")
			assertAt(player(), 0, 0, "Dove does not move when she attacks")
			assert(goldPiles() == 1, "the first tickle drops gold")
			assert(player().grooveChain.killCount == 1, "a tickle counts as a kill")
		end,
		[2] = function(skeleton)
			assert(skeleton.health.health == 10, "still no damage")
			assert(goldPiles() == 1, "the gold drops only once")
			assert(player().grooveChain.killCount == 2, "every tickle counts as a kill")
		end,
	},
})

-- Skeletons and the Minotaur are knocked back a tile; a slime is not.
scene({
	name = "doveFlowerKnockback",
	setup = function()
		return {
			skeleton = frozen("Skeleton", 1, 0),
			minotaur = frozen("Minotaur", -1, 0),
			slime = frozen("Slime", 0, -1),
		}
	end,
	actions = { "right", "left", "up" },
	checks = {
		[1] = function(s)
			assertAt(s.skeleton, 2, 0, "skeleton knocked back")
		end,
		[2] = function(s)
			assertAt(s.minotaur, -2, 0, "minotaur knocked back")
			assert(s.minotaur.health.health == s.minotaur.health.maxHealth, "minotaur unhurt")
		end,
		[3] = function(s)
			assertAt(s.slime, 0, -1, "slime stays")
			assertAt(player(), 0, 0, "Dove never moved")
		end,
	},
})

-- Enemies still hurt Dove.
scene({
	name = "doveTakesDamage",
	setup = function()
		fixtures.spawn("Skeleton", 2, 0)
	end,
	actions = { "idle", "idle", "idle" },
	checks = {
		[3] = function()
			assert(health() == 13, "a skeleton hits Dove for 1, health " .. health())
		end,
	},
})

-- Dove's bomb teleports the enemies in its blast, unhurt, still breaks dirt
-- walls, and still hurts Dove.
scene({
	name = "doveBombTeleports",
	setup = function()
		Tile.setType(1, 1, "DirtWall")
		return {
			skeleton = frozen("Skeleton", 1, 0),
			minotaur = frozen("Minotaur", -1, -1),
			far = frozen("Slime", 0, 2),
		}
	end,
	actions = { "bomb", "idle", "idle", "idle" },
	checks = {
		[4] = function(s)
			for _, name in ipairs({ "skeleton", "minotaur" }) do
				local enemy = s[name]
				assert(Entities.entityExists(enemy.id), name .. " survives")
				assert(enemy.health.health == enemy.health.maxHealth, name .. " unhurt")
				local x, y = enemy.position.x, enemy.position.y
				assert(math.abs(x) > 1 or math.abs(y) > 1, string.format("%s teleported, at (%d,%d)", name, x, y))
			end
			assertAt(s.far, 0, 2, "outside the blast")
			assert(fixtures.tileName(1, 1) == "Floor", "the dirt wall breaks")
			assert(health() == 10, "the blast hurts Dove for 4, health " .. health())
		end,
	},
})

-- Stairs locked by a living miniboss open when Dove steps on them, and she
-- descends; for Cadence they stay locked.
local function lockedStairs(character, opens)
	scene({
		name = "lockedStairs" .. character,
		character = character,
		keepType = "Minotaur",
		lateTicks = 2500,
		setup = function()
			local minotaur
			local kept = {}
			for entity in Entities.entitiesWithComponents({ "ai" }) do
				kept[#kept + 1] = entity.name
				if entity.name == "Minotaur" then
					minotaur = entity
				end
			end
			assert(minotaur, "the level's miniboss is kept, found: " .. table.concat(kept, " "))
			freeze(minotaur)
			Tile.setType(1, 0, "LockedStairs")
			return minotaur
		end,
		actions = { "right" },
		checks = {
			[1] = function(minotaur)
				assert(Entities.entityExists(minotaur.id), "the miniboss lives")
				local expected = opens and "Stairs" or "LockedStairs"
				assert(fixtures.tileName(1, 0) == expected, "the tile is " .. fixtures.tileName(1, 0))
			end,
			[2] = function()
				local expected = opens and 2 or 1
				assert(CurrentLevel.getNumber() == expected, "on level " .. CurrentLevel.getNumber())
			end,
		},
	})
end
lockedStairs("Dove", true)
lockedStairs("Cadence", false)

-- A single-zone run as Dove ends on its third level, with no boss level.
testsApi.registerTest({
	name = "doveRunHasNoBoss",
	character = "Dove",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		-- A level change from the first level takes effect late, so go
		-- through level 2 and poll, as ghost.lua does.
		GameSession.goToLevel(2)
		testsApi.afterTicks(400, function()
			GameSession.goToLevel(3)
			local function whenLoaded()
				if CurrentLevel.getNumber() ~= 3 then
					testsApi.afterTicks(10, whenLoaded)
					return
				end
				assert(CurrentLevel.getDungeonLength() == 3, "three levels, not " .. CurrentLevel.getDungeonLength())
				assert(CurrentLevel.isRunFinal(), "level 3 is the run's last")
				assert(not CurrentLevel.isBoss(), "and not a boss level")
				finish()
			end
			whenLoaded()
		end)
	end,
})

-- Dove's levels, as generated, have no monkeys, harpies, trapdoors or
-- sarcophagi. Cadence's first level on the same seed has monkeys in zone 1,
-- trapdoors in zone 2, and harpies, monkeys and a sarcophagus in zone 4.
local function isBanned(name)
	return name == "Harpy" or name:find("Monkey") or name:find("Trapdoor") or name:find("Sarcophagus")
end

for zone = 1, 5 do
	testsApi.registerTest({
		name = "doveLevelBans" .. zone,
		character = "Dove",
		zone = zone,
		onLoad = function()
			for entity in Entities.entitiesWithComponents({ "position" }) do
				assert(not isBanned(entity.name), "zone " .. zone .. " has a " .. entity.name)
			end
		end,
	})
end
