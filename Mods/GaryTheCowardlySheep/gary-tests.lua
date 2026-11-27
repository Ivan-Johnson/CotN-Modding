local Action = require "necro.game.system.Action"
local Damage = require "necro.game.system.Damage"
local Entities = require "system.game.Entities"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"
local garyMod = require "GaryTheCowardlySheep.GaryTheCowardlySheep"

-- Each test plays Muriel in no-beat mode on an open floor.
-- Muriel starts at (0,0) sharing Gary's tile; "up" is toward negative y. Two
-- steps right leave Muriel at (2,0) and Gary at (1,0) facing right, so his
-- Fright zone is x in {-1, 0}, y in {-1, 0, 1}.

local function sheep()
	return Entities.getEntityByID(fixtures.player().characterWithFollower.followerID)
end

local function assertDead(what)
	assert(sheep().killable.dead, what .. ": expected Gary to be dead")
end

local function assertAlive(what)
	assert(not sheep().killable.dead, what .. ": expected Gary to be alive")
end

local function scene(name, actions, checks)
	fixtures.scene({ name = name, character = garyMod.CHARACTER, actions = actions, checks = checks })
end

scene("murielIsNamedMuriel", { "idle" }, {
	[1] = function()
		local name = fixtures.player().friendlyName.name
		assert(name == "Muriel", "the character is called " .. tostring(name))
	end,
})

scene("hostileEnemyBehindCoweringGaryFrightensHimToDeath", { "right", "right", "idle" }, {
	[2] = function()
		fixtures.assertAt(sheep(), 1, 0, "Gary trails Muriel")
		fixtures.spawn("Slime", 0, 1)
	end,
	[3] = function()
		assertDead("a green slime two tiles away, in the Fright zone")
	end,
})

-- Muriel steps onto Gary's tile, which he does not leave, then into his Fright
-- zone, while a green slime two tiles to his side keeps him Cowering.
local function murielBacksIntoGary(name, prepare, verdict)
	scene(name, { "right", "right", "left", "left" }, {
		[2] = prepare,
		[3] = function()
			fixtures.assertAt(sheep(), 1, 0, "Gary stays put as Muriel steps onto his tile")
			assertAlive("Muriel sharing Gary's tile")
		end,
		[4] = verdict,
	})
end

murielBacksIntoGary("murielBehindCoweringGaryFrightensHimToDeath", function()
	fixtures.spawn("Slime", 1, 2)
end, function()
	assertDead("Muriel directly behind Gary while a slime is two tiles away")
end)

murielBacksIntoGary("enemyThreeTilesAwayLeavesGaryCalm", function()
	fixtures.spawn("Slime", 1, 3)
end, function()
	assertAlive("Muriel behind Gary while the only slime is three tiles away")
end)

murielBacksIntoGary("wallDoesNotShieldGaryFromCowering", function()
	fixtures.spawn("Slime", 1, 2)
	fixtures.wallColumn(1, 1, 1)
end, function()
	assertDead("Muriel behind Gary while a slime two tiles away is behind a wall")
end)

murielBacksIntoGary("unprovokedShopkeeperLeavesGaryCalm", function()
	fixtures.spawn("Shopkeeper", 1, 2)
end, function()
	assertAlive("Muriel behind Gary while the only enemy near is an unprovoked shopkeeper")
end)

scene("unprovokedShopkeeperBehindGaryLeavesHimAlive", { "right", "right", "idle" }, {
	[2] = function()
		fixtures.spawn("Slime", 1, 2)
		fixtures.spawn("Shopkeeper", 0, 0)
	end,
	[3] = function()
		assertAlive("an unprovoked shopkeeper in the Fright zone of a Cowering Gary")
	end,
})

-- A provoked shopkeeper kills Muriel within a turn of reaching her, so he starts
-- behind Gary, who stands between them, and chasing her keeps him in the
-- Fright zone.
scene("provokedShopkeeperBehindGaryFrightensHimToDeath", { "right", "right", "idle" }, {
	[2] = function()
		local keeper = fixtures.spawn("Shopkeeper", -1, 0)
		Damage.inflict({
			victim = keeper,
			attacker = fixtures.player(),
			damage = 1,
			type = Damage.Type.EXPLOSIVE,
		})
		assert(keeper.provokable.active, "the explosion provoked the shopkeeper")
	end,
	[3] = function()
		assertDead("a provoked shopkeeper in the Fright zone")
	end,
})

-- The game puts crates and barrels on a team hostile to Gary, but they are not
-- enemies: near him they do not make him Cower, and in his Fright zone they
-- cause no Death by fright. Crate2 is the barrel.
for _, containerType in ipairs({ "Crate", "Crate2" }) do
	scene(containerType .. "BehindCoweringGaryLeavesHimAlive", { "right", "right", "idle" }, {
		[2] = function()
			fixtures.spawn("Slime", 1, 2)
			fixtures.spawn(containerType, 0, 1)
		end,
		[3] = function()
			assertAlive(containerType .. " in the Fright zone of a Cowering Gary")
		end,
	})

	murielBacksIntoGary(containerType .. "NearGaryLeavesHimCalm", function()
		fixtures.spawn(containerType, 1, 2)
	end, function()
		assertAlive("Muriel behind Gary while the only thing near is a " .. containerType)
	end)
end

-- A dormant exploding mushroom is provokable and unprovoked, like a shopkeeper.
murielBacksIntoGary("dormantExplodingMushroomLeavesGaryCalm", function()
	local mushroom = fixtures.spawn("MushroomExploding", 1, 2)
	assert(not mushroom.provokable.active, "the exploding mushroom is unprovoked")
end, function()
	assertAlive("Muriel behind Gary while the only enemy near is a dormant exploding mushroom")
end)

scene("garyFacingDiagonallyHasNoFrightZone", { "right", "right", "idle" }, {
	[2] = function()
		sheep().facingDirection.direction = Action.Direction.UP_RIGHT
		fixtures.spawn("Slime", 0, 1)
	end,
	[3] = function()
		assertAlive("a slime diagonally behind Gary while he faces diagonally")
	end,
})
