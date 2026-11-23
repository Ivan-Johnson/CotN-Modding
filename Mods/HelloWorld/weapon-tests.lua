local Action = require "necro.game.system.Action"
local Entities = require "system.game.Entities"
local Input = require "necro.client.Input"
local Inventory = require "necro.game.item.Inventory"
local Move = require "necro.game.system.Move"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on HelloWorldTests; see tests.lua.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end
local fixtures = require "HelloWorldTests.fixtures"

-- Backs AuthoredDocs/Src/weapons.md. Every test plays Cadence in no-beat mode
-- on an open floor against tough Slimes spawned by hand. A step is one
-- situation: the weapon, the targets, the presses, and what must hold after.
-- Coordinates are in the facing frame: x is ahead, y is to the right-hand
-- side, so "up" on the screen is the left-hand side when facing right. `dir`
-- rotates the whole step to face another way.

local ROTATE = {
	right = function(x, y) return x, y end,
	down = function(x, y) return -y, x end,
	left = function(x, y) return -x, -y end,
	up = function(x, y) return y, -x end,
}

local function equip(weaponType)
	local player = fixtures.player()
	for _, item in ipairs(Inventory.getItems(player)) do
		if item.weapon then
			Object.delete(item)
		end
	end
	Inventory.grant(weaponType, player)
end

local function heldIDs()
	local held = {}
	for _, item in ipairs(Inventory.getItems(fixtures.player())) do
		held[item.id] = true
	end
	return held
end

local function weaponName()
	for _, item in ipairs(Inventory.getItems(fixtures.player())) do
		if item.weapon then
			return item.name
		end
	end
	return nil
end

-- Positions of items lying on the floor, by type name.
local function floorItems(typeName)
	local held = heldIDs()
	local found = {}
	for entity in Entities.entitiesWithComponents({ "item", "position" }) do
		if entity.name == typeName and not held[entity.id] then
			found[#found + 1] = { entity.position.x, entity.position.y }
		end
	end
	return found
end

local function clearScene()
	local held = heldIDs()
	local doomed = {}
	for entity in Entities.entitiesWithComponents({ "item", "position" }) do
		if not held[entity.id] then
			doomed[#doomed + 1] = entity
		end
	end
	for entity in Entities.entitiesWithComponents({ "ai" }) do
		doomed[#doomed + 1] = entity
	end
	for _, entity in ipairs(doomed) do
		Object.delete(entity)
	end
end

local function damageOf(rec)
	if not Entities.entityExists(rec.entity.id) then
		return rec.hp
	end
	return rec.hp - rec.entity.health.health
end

local function describe(step)
	return step.label or (step.weapon .. " " .. table.concat(step.presses, ","))
end

local function assertPosition(step, who, position, x, y)
	assert(
		position.x == x and position.y == y,
		string.format("%s: %s at (%d,%d), expected (%d,%d)", describe(step), who, position.x, position.y, x, y)
	)
end

local function verify(step, recs)
	local rotate = ROTATE[step.dir or "right"]
	for i, want in ipairs(step.hits or {}) do
		local rec = recs[i]
		if want == "dead" then
			assert(
				not Entities.entityExists(rec.entity.id),
				string.format("%s: target %d should be dead", describe(step), i)
			)
		else
			local got = damageOf(rec)
			assert(got == want, string.format("%s: target %d took %d, expected %d", describe(step), i, got, want))
		end
	end
	if step.player then
		local x, y = rotate(step.player[1], step.player[2])
		assertPosition(step, "the player", fixtures.player().position, x, y)
	end
	for i, where in pairs(step.at or {}) do
		local x, y = rotate(where[1], where[2])
		assertPosition(step, "target " .. i, recs[i].entity.position, x, y)
	end
end

-- Runs one step, then calls next(). A press the game never resolved (an input
-- dropped on a busy tick) restarts the step.
local function runStep(step, attempt, next)
	local rotate = ROTATE[step.dir or "right"]
	local player = fixtures.player()
	Move.absolute(player, 0, 0, Move.Type.TELEPORT)
	player.health.health = step.health or 12
	player.grooveChain.multiplier = step.multiplier or 1
	player.grooveChain.killCount = ((step.multiplier or 1) - 1) * 4
	player.goldCounter.amount = 0
	clearScene()
	equip(step.weapon)

	local walls = {}
	for _, wall in ipairs(step.walls or {}) do
		local x, y = rotate(wall[1], wall[2])
		Tile.setType(x, y, wall[3] or "StoneWall")
		walls[#walls + 1] = { x, y }
	end
	local function spawnTarget(t)
		local x, y = rotate(t[1], t[2])
		local entity = fixtures.spawn(t[3] or "Slime", x, y)
		local hp = t[4] or 1000
		if entity.health then
			entity.health.health = hp
			entity.health.maxHealth = hp
		end
		return { entity = entity, hp = hp }
	end
	local recs = {}
	for _, t in ipairs(step.targets or {}) do
		recs[#recs + 1] = spawnTarget(t)
	end
	for _, item in ipairs(step.items or {}) do
		local x, y = rotate(item[2], item[3])
		fixtures.spawn(item[1], x, y)
	end
	if step.setup then
		step.setup(recs)
	end

	local presses = {}
	for i, name in ipairs(step.presses) do
		presses[i] = (name == "forward") and (step.dir or "right") or name
	end
	local unresolved = false
	testsApi.play(presses, function(index, _, resolved)
		if not resolved then
			unresolved = true
			return
		end
		if step.respawn and not Entities.entityExists(recs[#recs].entity.id) then
			recs[#recs + 1] = spawnTarget(step.respawn)
		end
		if step.after and step.after[index] then
			step.after[index](recs)
		end
	end, function()
		if not unresolved then
			verify(step, recs)
		end
		for _, rec in ipairs(recs) do
			if Entities.entityExists(rec.entity.id) then
				Object.delete(rec.entity)
			end
		end
		for _, wall in ipairs(walls) do
			Tile.setType(wall[1], wall[2], "Floor")
		end
		if unresolved then
			assert(attempt < 3, describe(step) .. ": the game never resolved a press")
			runStep(step, attempt + 1, next)
			return
		end
		testsApi.afterTicks(1, next)
	end)
end

local function sceneTest(name, steps)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(12)
			local i = 0
			local function nextStep()
				i = i + 1
				if i > #steps then
					finish()
					return
				end
				local step = steps[i]
				step.presses = step.presses or { "forward" }
				runStep(step, 1, nextStep)
			end
			nextStep()
		end,
	})
end

local function step(weapon, targets, extra)
	local s = extra or {}
	s.weapon = weapon
	s.targets = targets
	return s
end

local function health()
	return fixtures.player().health.health
end

local function repeated(value, count)
	local list = {}
	for i = 1, count do
		list[i] = value
	end
	return list
end

------------------------------------------------------------------ reach

-- Which tiles each family hits, what makes it attack instead of move, and how
-- far it reaches.
sceneTest("weaponReach", {
	step("WeaponDagger", { { 1, 0 } }, { hits = { 1 }, player = { 0, 0 } }),
	step("WeaponDagger", { { 2, 0 } }, { hits = { 0 }, player = { 1, 0 } }),

	step("WeaponBroadsword", { { 1, -1 }, { 1, 0 }, { 1, 1 } }, { hits = { 1, 1, 1 }, player = { 0, 0 } }),
	step("WeaponBroadsword", { { 1, 1 } }, { hits = { 1 }, player = { 0, 0 } }),
	step("WeaponBroadsword", { { 2, 0 } }, { hits = { 0 }, player = { 1, 0 } }),

	step("WeaponLongsword", { { 1, 0 }, { 2, 0 } }, { hits = { 1, 1 }, player = { 0, 0 } }),
	step("WeaponLongsword", { { 2, 0 } }, { hits = { 1 }, player = { 0, 0 } }),

	step("WeaponSpear", { { 1, 0 }, { 2, 0 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponSpear", { { 2, 0 } }, { hits = { 1 }, player = { 0, 0 } }),
	step("WeaponSpear", { { 3, 0 } }, { hits = { 0 }, player = { 1, 0 } }),

	step("WeaponStaff", { { 1, 0 }, { 4, 0 }, { 8, 0 } }, { hits = { 1, 1, 1 }, player = { 0, 0 } }),
	step("WeaponStaff", { { 2, 0 } }, { hits = { 0 }, player = { 1, 0 } }),
	step("WeaponStaff", { { 1, 0 }, { 6, 0 } }, { walls = { { 5, 0 } }, hits = { 1, 0 }, player = { 0, 0 } }),

	step("WeaponRapier", { { 2, 0 } }, { hits = { 2 }, player = { 1, 0 } }),
	step("WeaponRapier", { { 1, 0 }, { 2, 0 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponRapier", { { 3, 0 } }, { hits = { 0 }, player = { 1, 0 } }),

	step("WeaponAxe", { { 2, 0 }, { 2, 1 }, { 2, -1 }, { 3, 0 } }, { hits = { 1, 1, 1, 0 }, player = { 1, 0 } }),
	step("WeaponAxe", { { 1, 0 }, { 2, 1 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponAxe", { { 2, 1 } }, { hits = { 1 }, player = { 1, 0 } }),
	step("WeaponAxe", { { 3, 0 } }, { hits = { 0 }, player = { 1, 0 } }),

	step("Sync_WeaponTrident", { { 2, 0 }, { 2, 1 }, { 2, -1 } }, { hits = { 1, 1, 1 }, player = { 0, 0 } }),
	step("Sync_WeaponTrident", { { 1, 0 }, { 2, 1 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("Sync_WeaponTrident", { { 2, -1 } }, { hits = { 1 }, player = { 0, 0 } }),
})

-- Side-reaching families: Cat, Whip, Flail, Harp.
sceneTest("weaponSides", {
	-- Cat: front enemy first and no move; otherwise one enemy beside the
	-- destination (left before right), then one beside the start tile.
	step(
		"WeaponCat",
		{ { 1, 0 }, { 1, 1 }, { 1, -1 }, { 0, 1 }, { 0, -1 } },
		{ hits = { 1, 0, 0, 0, 0 }, player = { 0, 0 } }
	),
	step("WeaponCat", { { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 1 } }, { hits = { 0, 0, 1, 0 }, player = { 1, 0 } }),
	step("WeaponCat", { { 1, 1 }, { 0, -1 } }, { hits = { 1, 0 }, player = { 1, 0 } }),
	step("WeaponCat", { { 0, -1 }, { 0, 1 } }, { hits = { 1, 0 }, player = { 1, 0 } }),
	step("WeaponCat", { { 2, 1 } }, { hits = { 0 }, player = { 1, 0 } }),

	-- Whip: one enemy; front, then diagonals ahead (left first), then the
	-- tiles two to the side (left first).
	step("WeaponWhip", { { 1, 0 }, { 1, -1 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponWhip", { { 1, -1 }, { 1, 1 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponWhip", { { 1, 1 }, { 1, -2 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponWhip", { { 1, -2 }, { 1, 2 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
	step("WeaponWhip", { { 1, 2 } }, { hits = { 1 }, player = { 0, 0 } }),

	-- Flail: every enemy in front, diagonally ahead and beside; each is
	-- pushed one tile ahead.
	step("WeaponFlail", { { 1, 0 } }, { hits = { 1 }, at = { { 2, 0 } } }),
	step("WeaponFlail", { { 0, 1 } }, { hits = { 1 }, at = { { 1, 1 } } }),
	step("WeaponFlail", { { 1, -1 }, { 0, -1 }, { 1, 1 }, { 0, 1 } }, { hits = { 1, 1, 1, 1 } }),
	step("WeaponFlail", { { 1, 0 } }, { walls = { { 2, 0 } }, hits = { 1 }, at = { { 1, 0 } } }),
	step("WeaponFlail", { { 0, 2 } }, { hits = { 0 }, player = { 1, 0 } }),

	-- Harp: an enemy straight ahead starts the swing, which hits all eight
	-- tiles around you.
	step(
		"WeaponHarp",
		{ { 1, 0 }, { 1, 1 }, { 1, -1 }, { 0, 1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { -1, -1 } },
		{ hits = { 1, 1, 1, 1, 1, 1, 1, 1 }, player = { 0, 0 } }
	),
	step("WeaponHarp", { { 0, 1 }, { 1, 1 } }, { hits = { 0, 0 }, player = { 1, 0 } }),
	step("WeaponHarp", { { 1, 0 }, { 2, 0 } }, { hits = { 1, 0 }, player = { 0, 0 } }),
})

-- Patterns rotate with the way you press.
sceneTest("weaponRotation", {
	step("WeaponBroadsword", { { 1, -1 }, { 1, 0 }, { 1, 1 } }, { dir = "up", hits = { 1, 1, 1 } }),
	step("WeaponLongsword", { { 1, 0 }, { 2, 0 } }, { dir = "left", hits = { 1, 1 } }),
	step("WeaponWhip", { { 1, -1 }, { 1, 1 } }, { dir = "down", hits = { 1, 0 } }),
	step("WeaponWhip", { { 1, -1 }, { 1, 1 } }, { dir = "up", hits = { 1, 0 } }),
	step("WeaponAxe", { { 2, 0 } }, { dir = "left", hits = { 1 }, player = { 1, 0 } }),
})

-- A solid tile directly ahead stops the far tiles of the reaching families
-- but not the sideways ones.
sceneTest("weaponWalls", {
	step("WeaponLongsword", { { 2, 0 } }, { walls = { { 1, 0 } }, hits = { 0 } }),
	step("WeaponSpear", { { 2, 0 } }, { walls = { { 1, 0 } }, hits = { 0 } }),
	step("WeaponRapier", { { 2, 0 } }, { walls = { { 1, 0 } }, hits = { 0 } }),
	step("WeaponAxe", { { 2, 0 } }, { walls = { { 1, 0 } }, hits = { 0 } }),
	step("Sync_WeaponTrident", { { 2, 1 } }, { walls = { { 1, 0 } }, hits = { 0 } }),
	step("WeaponStaff", { { 1, 0 }, { 3, 0 } }, { walls = { { 2, 0 } }, hits = { 1, 0 } }),
	step("WeaponBroadsword", { { 1, 1 } }, { walls = { { 1, 0 } }, hits = { 1 } }),
	step("WeaponWhip", { { 1, -1 } }, { walls = { { 1, 0 } }, hits = { 1 } }),
	step("WeaponCat", { { 0, 1 } }, { walls = { { 1, 0 } }, hits = { 1 } }),
})

------------------------------------------------------------------ materials

local FAMILIES = {
	"Dagger",
	"Broadsword",
	"Longsword",
	"Spear",
	"Rapier",
	"Axe",
	"Cat",
	"Flail",
	"Harp",
	"Staff",
	"Whip",
}

local function materialSteps(prefix, damage)
	local steps = {}
	for _, family in ipairs(FAMILIES) do
		steps[#steps + 1] = step(prefix .. family, { { 1, 0 } }, { hits = { damage }, label = prefix .. family })
	end
	steps[#steps + 1] = step("Sync_Weapon" .. prefix:gsub("^Weapon", "") .. "Trident", { { 1, 0 } }, { hits = { damage } })
	return steps
end

local function concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, item in ipairs(list) do
			out[#out + 1] = item
		end
	end
	return out
end

-- Basic, Titanium and Glass weapons hit for 1, 2 and 4 in every family, and a
-- Rapier lunge doubles that.
sceneTest("weaponMaterialDamage", concat(
	materialSteps("Weapon", 1),
	materialSteps("WeaponTitanium", 2),
	materialSteps("WeaponGlass", 4),
	{
		step("WeaponTitaniumRapier", { { 2, 0 } }, { hits = { 4 }, player = { 1, 0 } }),
		step("WeaponGlassRapier", { { 2, 0 } }, { hits = { 8 }, player = { 1, 0 } }),
		step("WeaponDaggerJeweled", { { 1, 0 } }, { hits = { 5 } }),
		step("WeaponDaggerElectric", { { 1, 0 } }, { hits = { 2 } }),
		step("WeaponDaggerPhasing", { { 1, 0 } }, { hits = { 2 } }),
		step("WeaponDaggerFrost", { { 1, 0 } }, { hits = { 1 } }),
		step("WeaponGoldenDagger", { { 1, 0 } }, { hits = { 1 } }),
		step("WeaponBloodDagger", { { 1, 0 } }, { hits = { 1 } }),
		step("Sync_WeaponOnyxDagger", { { 1, 0 } }, { hits = { 1 } }),
	}
))

-- Obsidian hits for the coin multiplier.
sceneTest("weaponObsidianMultiplier", {
	step("WeaponObsidianDagger", { { 1, 0 } }, { multiplier = 1, hits = { 1 } }),
	step("WeaponObsidianDagger", { { 1, 0 } }, { multiplier = 2, hits = { 2 } }),
	step("WeaponObsidianDagger", { { 1, 0 } }, { multiplier = 3, hits = { 3 } }),
	step("WeaponObsidianBroadsword", { { 1, 0 }, { 1, 1 } }, { multiplier = 3, hits = { 3, 3 } }),
})

-- Golden: the action right after picking up gold hits for an extra 999; a
-- diamond does not count, and an action in between loses it.
local plainGold = 0

sceneTest("weaponGoldenBonus", {
	step("WeaponGoldenDagger", { { 2, 0, "Slime", 5000 } }, {
		items = { { "ResourceCoin10", 1, 0 } }, presses = { "forward", "forward", "forward" },
		after = { [2] = function(recs)
			assert(damageOf(recs[1]) == 1000, "the hit right after a pickup deals 1000, got " .. damageOf(recs[1]))
		end },
		hits = { 1001 }, label = "golden pickup then two hits",
	}),
	step("WeaponGoldenDagger", { { 2, 0, "Slime", 5000 } }, {
		items = { { "ResourceCoin10", 1, 0 } }, presses = { "forward", "idle", "forward" },
		hits = { 1 }, label = "golden pickup, idle, hit",
	}),
	step("WeaponGoldenDagger", { { 2, 0, "Slime", 5000 } }, {
		items = { { "ResourceDiamond", 1, 0 } }, presses = { "forward", "forward" },
		hits = { 1 }, label = "golden diamond pickup",
	}),
	step("WeaponGoldenBroadsword", { { 2, 0 }, { 2, 1 } }, {
		items = { { "ResourceCoin10", 1, 0 } }, presses = { "forward", "forward" },
		hits = { "dead", "dead" }, label = "golden broadsword after pickup",
	}),
	step("WeaponDagger", { { 2, 0, "Slime", 5000 } }, {
		items = { { "ResourceCoin10", 1, 0 } }, presses = { "forward", "forward" },
		hits = { 1 }, label = "plain dagger after pickup",
	}),
	-- Kills drop more gold with a golden weapon: kill a Slime, walk onto its
	-- coin, and compare the gold with a plain dagger's.
	step("WeaponDagger", { { 1, 0, "Slime", 1 } }, {
		presses = { "forward", "forward" },
		after = { [2] = function() plainGold = fixtures.player().goldCounter.amount end },
		label = "gold from a plain dagger kill",
	}),
	step("WeaponGoldenDagger", { { 1, 0, "Slime", 1 } }, {
		presses = { "forward", "forward" },
		after = {
			[2] = function()
				local gold = fixtures.player().goldCounter.amount
				assert(gold > plainGold and plainGold > 0, "golden kill drops " .. gold .. ", plain " .. plainGold)
			end,
		},
		label = "gold from a golden dagger kill",
	}),
})

-- Blood: +999 damage at 1 health, not at 2.
sceneTest("weaponBloodLowHealth", {
	step("WeaponBloodDagger", { { 1, 0 } }, { health = 1, hits = { "dead" }, label = "blood at 1 health" }),
	step("WeaponBloodDagger", { { 1, 0 } }, { health = 2, hits = { 1 }, label = "blood at 2 health" }),
	step("WeaponBloodBroadsword", { { 1, 0 } }, { health = 1, hits = { "dead" }, label = "blood broadsword at 1 health" }),
})

-- Blood heals 1 health on every tenth kill. A test of its own, because the
-- kill count lives with the player.
sceneTest("weaponBloodHealsEveryTenKills", {
	step("WeaponBloodDagger", { { 1, 0, "Slime", 1 } }, {
		health = 6, respawn = { 1, 0, "Slime", 1 },
		presses = repeated("forward", 20),
		after = {
			[9] = function() assert(health() == 6, "no heal after 9 kills, health " .. health()) end,
			[10] = function() assert(health() == 7, "heal on the 10th kill, health " .. health()) end,
			[19] = function() assert(health() == 7, "no second heal after 19 kills, health " .. health()) end,
			[20] = function() assert(health() == 8, "heal on the 20th kill, health " .. health()) end,
		},
	}),
})

-- Glass breaks the first time you take damage, leaving you without a weapon
-- and a Glass Shard on the floor; stepping onto the shard picks it up.
sceneTest("weaponGlassShatters", {
	step("WeaponGlassDagger", { { 1, 0 } }, {
		presses = { "forward", "forward", "forward", "forward" },
		after = {
			[4] = function() assert(weaponName() == "WeaponGlassDagger", "glass survives attacks") end,
		},
		hits = { 16 },
		label = "glass dagger survives hits",
	}),
	step("WeaponGlassDagger", {}, {
		presses = { "bomb", "idle", "idle", "idle", "up", "down" },
		after = {
			[3] = function() assert(weaponName() == "WeaponGlassDagger", "glass still whole before the blast") end,
			[4] = function()
				assert(health() == 8, "the blast hurts, health " .. health())
				assert(weaponName() == nil, "glass shatters on damage, holding " .. (weaponName() or "nothing"))
				local shards = floorItems("WeaponDaggerShard")
				assert(#shards == 1 and shards[1][1] == 0 and shards[1][2] == 0, "a shard drops on the player's tile")
			end,
			[6] = function() assert(weaponName() == "WeaponDaggerShard", "stepping onto the shard picks it up") end,
		},
		label = "glass shatters",
	}),
})

-- Onyx: every hit in an unbroken run after the first deals 1000 more, across
-- targets and directions; an idle or a move ends the run.
sceneTest("weaponOnyxCombo", {
	step("Sync_WeaponOnyxDagger", { { 1, 0, "Slime", 5000 } }, {
		presses = { "forward", "forward", "forward" },
		after = {
			[1] = function(recs) assert(damageOf(recs[1]) == 1, "first hit is plain") end,
			[2] = function(recs) assert(damageOf(recs[1]) == 1001, "second hit adds 1000, got " .. damageOf(recs[1])) end,
		},
		hits = { 2001 },
	}),
	step("Sync_WeaponOnyxDagger", { { 1, 0, "Slime", 5000 } }, {
		presses = { "forward", "idle", "forward", "forward" },
		after = { [3] = function(recs) assert(damageOf(recs[1]) == 2, "an idle ends the run") end },
		hits = { 1002 },
	}),
	step("Sync_WeaponOnyxDagger", { { 1, 0, "Slime", 5000 } }, {
		presses = { "forward", "left", "right", "right" },
		hits = { 2 }, label = "onyx move ends the run",
	}),
	step("Sync_WeaponOnyxDagger", { { 1, 0, "Slime", 1 }, { 0, -1, "Slime", 5000 }, { 0, 1, "Slime", 5000 } }, {
		presses = { "forward", "up", "down" },
		hits = { "dead", 1000, 1000 }, label = "onyx kill starts the run",
	}),
	step("Sync_WeaponOnyxBroadsword", { { 1, 0, "Slime", 5000 }, { 1, 1, "Slime", 5000 } }, {
		presses = { "forward", "forward" },
		hits = { 1001, 1001 }, label = "onyx broadsword",
	}),
})

-- Frost freezes on a hit; hitting a frozen enemy kills it, for the next three
-- turns.
sceneTest("weaponFrost", {
	step("WeaponDaggerFrost", { { 1, 0 } }, {
		presses = { "forward", "forward" },
		hits = { "dead" },
		label = "frost second hit",
	}),
	step("WeaponDaggerFrost", { { 1, 0 } }, {
		presses = { "forward", "idle", "idle", "forward" },
		hits = { "dead" },
		label = "frost hit after 2 idles",
	}),
	step("WeaponDaggerFrost", { { 1, 0 } }, {
		presses = { "forward", "idle", "idle", "idle", "forward" },
		hits = { 2 },
		label = "frost hit after 3 idles",
	}),
	step("WeaponDagger", { { 1, 0 } }, { presses = { "forward", "forward" }, hits = { 2 }, label = "plain dagger twice" }),
})

-- Electric arcs 1 damage to every enemy touching a hit enemy, diagonals
-- included, along a chain.
sceneTest("weaponElectricChain", {
	step(
		"WeaponDaggerElectric",
		{ { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 }, { 5, 0 }, { 6, 0 } },
		{ hits = { 2, 1, 1, 1, 1, 1 } }
	),
	step("WeaponDaggerElectric", { { 1, 0 }, { 2, 1 }, { 3, 2 } }, { hits = { 2, 1, 1 } }),
	step("WeaponDaggerElectric", { { 1, 0 }, { 3, 0 } }, { hits = { 2, 0 } }),
	step("WeaponDaggerElectric", { { 0, 1 }, { 1, 1 } }, { hits = { 0, 0 }, player = { 1, 0 } }),
})

-- Phasing reaches what other weapons cannot: an enemy inside a wall and a
-- ghost you are facing; it does not reach past a wall.
sceneTest("weaponPhasing", {
	step("WeaponDaggerPhasing", { { 1, 0 } }, { walls = { { 1, 0 } }, hits = { 2 }, label = "phasing, enemy in wall" }),
	step("WeaponDagger", { { 1, 0 } }, { walls = { { 1, 0 } }, hits = { 0 }, label = "dagger, enemy in wall" }),
	step("WeaponDaggerPhasing", { { 1, 0, "Ghost", 50 } }, { hits = { 2 }, label = "phasing, ghost ahead" }),
	step("WeaponDagger", { { 1, 0, "Ghost", 50 } }, { hits = { 0 }, label = "dagger, ghost ahead" }),
	step("WeaponDaggerPhasing", { { 2, 0 } }, { walls = { { 1, 0 } }, hits = { 0 }, label = "phasing, wall between" }),
})

-- No melee weapon damages a crate; each pushes it one tile.
local crateSteps = {}
local crateWeapons = {
	"WeaponDagger",
	"WeaponBroadsword",
	"WeaponLongsword",
	"WeaponSpear",
	"WeaponRapier",
	"WeaponAxe",
	"WeaponCat",
	"WeaponFlail",
	"WeaponHarp",
	"WeaponStaff",
	"WeaponWhip",
	"Sync_WeaponTrident",
	"WeaponDaggerPhasing",
	"Sync_WeaponOnyxDagger",
}
for _, weapon in ipairs(crateWeapons) do
	crateSteps[#crateSteps + 1] =
		step(weapon, { { 1, 0, "Crate", 50 } }, { hits = { 0 }, at = { { 2, 0 } }, label = weapon .. " on a crate" })
end
sceneTest("weaponsDoNotBreakCrates", crateSteps)

-- Stepping onto a weapon equips it and drops yours on that tile; stepping
-- back swaps again.
sceneTest("weaponPickupSwaps", {
	step("WeaponDagger", {}, {
		items = { { "WeaponBroadsword", 1, 0 } }, presses = { "forward", "left", "forward" },
		after = {
			[1] = function()
				assert(weaponName() == "WeaponBroadsword", "equipped the broadsword")
				local dropped = floorItems("WeaponDagger")
				assert(#dropped == 1 and dropped[1][1] == 1 and dropped[1][2] == 0, "the dagger drops on that tile")
			end,
			[3] = function()
				assert(weaponName() == "WeaponDagger", "swapped back to the dagger")
				assert(#floorItems("WeaponBroadsword") == 1, "the broadsword is on the floor again")
			end,
		},
		label = "pickup swap",
	}),
})

------------------------------------------------------------------ throwing

-- THROW then a direction throws a dagger, spear or trident: it flies to the
-- first wall hitting every enemy on the line, and lands there, leaving you
-- unarmed. A trident flies three tiles wide. Other weapons cannot be thrown.
local function throwStep(weapon, thrown, wide)
	return function(next)
		local player = fixtures.player()
		Move.absolute(player, 0, 0, Move.Type.TELEPORT)
		clearScene()
		equip(weapon)
		local line = fixtures.spawn("Slime", 3, 0)
		local end_ = fixtures.spawn("Slime", 6, 0)
		local beside = fixtures.spawn("Slime", 6, 1)
		local far = fixtures.spawn("Slime", 6, 2)
		local enemies = { line, end_, beside, far }
		for _, enemy in ipairs(enemies) do
			enemy.health.health = 1000
			enemy.health.maxHealth = 1000
		end
		testsApi.afterTicks(5, function()
			Input.add(Action.Special.THROW, 1)
			testsApi.afterTicks(100, function()
				Input.add(Action.Direction.RIGHT, 1)
				testsApi.afterTicks(300, function()
					if thrown then
						assert(line.health.health == 999 and end_.health.health == 999, weapon .. " hits every enemy on the line")
						assert((beside.health.health == 999) == wide, weapon .. " flies as wide as expected")
						assert(far.health.health == 1000, weapon .. " misses enemies two lanes over")
						assert(weaponName() == nil, weapon .. " leaves the hand empty")
						local landed = floorItems(weapon)
						assert(#landed == 1 and landed[1][1] > 6 and landed[1][2] == 0, weapon .. " lands past the last enemy")
					else
						assert(weaponName() == weapon, weapon .. " stays in hand")
						assert(fixtures.player().position.x == 1, weapon .. " cannot be thrown; the direction just moves")
					end
					for _, enemy in ipairs(enemies) do
						Object.delete(enemy)
					end
					next()
				end)
			end)
		end)
	end
end

testsApi.registerTest({
	name = "weaponThrowing",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		fixtures.openArena(12)
		local steps = {
			throwStep("WeaponDagger", true, false),
			throwStep("WeaponSpear", true, false),
			throwStep("Sync_WeaponTrident", true, true),
			throwStep("WeaponBroadsword", false, false),
		}
		local i = 0
		local function nextStep()
			i = i + 1
			if i > #steps then
				finish()
				return
			end
			steps[i](nextStep)
		end
		nextStep()
	end,
})

------------------------------------------------------------------ blunderbuss

-- The Blunderbuss fires one cone for 2 damage and knocks you back a tile;
-- afterwards it only hits the tile ahead.
local CONE = { { 1, 0 }, { 2, 0 }, { 3, 0 }, { 2, 1 }, { 2, -1 }, { 3, 1 }, { 3, -1 }, { 3, 2 }, { 3, -2 } }
local OUTSIDE_CONE = { { 4, 0 }, { 1, 1 }, { 1, -1 }, { 4, 1 } }

sceneTest("weaponBlunderbuss", {
	step("WeaponBlunderbuss", concat(CONE, OUTSIDE_CONE), {
		presses = { "forward", "forward", "forward" },
		after = {
			[1] = function(recs)
				for i = 1, #CONE do
					assert(damageOf(recs[i]) == 2, "cone target " .. i .. " takes 2")
				end
				for i = #CONE + 1, #recs do
					assert(damageOf(recs[i]) == 0, "outside the cone, target " .. i)
				end
				local position = fixtures.player().position
				assert(position.x == -1 and position.y == 0, "knocked back one tile")
			end,
		},
		-- Press 2 steps back to the start, press 3 hits the front tile only.
		hits = { 4, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0 },
	}),})

------------------------------------------------------------------ pools

-- The weapons the docs call zone one are those whose first-zone weight in a
-- chest, black chest or shop pool is above zero.
testsApi.registerTest({
	name = "weaponZoneOnePools",
	onLoad = function()
		local function weight(prototype, pool)
			local component = prototype[pool]
			return component and component.weights and component.weights[1] or 0
		end
		local function inZoneOne(typeName)
			local prototype = Entities.getEntityPrototype(typeName)
			local total = 0
			for _, pool in ipairs({ "itemPoolChest", "itemPoolBlackChest", "itemPoolShop" }) do
				total = total + weight(prototype, pool)
			end
			return total > 0
		end
		local prefixes = { "Weapon", "WeaponTitanium", "WeaponObsidian", "WeaponGolden", "WeaponBlood", "WeaponGlass" }
		for _, family in ipairs(FAMILIES) do
			for _, prefix in ipairs(prefixes) do
				if not (prefix == "Weapon" and family == "Dagger") then
					assert(inZoneOne(prefix .. family), prefix .. family .. " is in a zone one pool")
				end
			end
			assert(inZoneOne("Sync_WeaponOnyx" .. family), "Sync_WeaponOnyx" .. family .. " is in a zone one pool")
		end
		local others = {
			"WeaponDaggerFrost",
			"WeaponDaggerElectric",
			"WeaponDaggerPhasing",
			"WeaponDaggerJeweled",
			"Sync_WeaponTrident",
			"Sync_WeaponTitaniumTrident",
		}
		for _, name in ipairs(others) do
			assert(inZoneOne(name), name .. " is in a zone one pool")
		end
		local later = {
			"WeaponBow",
			"WeaponCrossbow",
			"WeaponCutlass",
			"WeaponWarhammer",
			"WeaponRifle",
			"WeaponBlunderbuss",
			"Sync_WeaponOnyxTrident",
		}
		for _, name in ipairs(later) do
			assert(not inZoneOne(name), name .. " is not in a zone one pool")
		end
	end,
})
