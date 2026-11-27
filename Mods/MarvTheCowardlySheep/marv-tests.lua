local Damage = require "necro.game.system.Damage"
local Entities = require "system.game.Entities"
local Move = require "necro.game.system.Move"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"
local marvMod = require "MarvTheCowardlySheep.MarvTheCowardlySheep"

-- Each test plays Muriel in no-beat mode on an open floor.
-- Muriel starts at (0,0) sharing Marv's tile; "up" is toward negative y. Two
-- steps right leave Muriel at (2,0) and Marv at (1,0), so his Fright zone is
-- x in -4..0, y in -2..2, less any tile a wall hides from him.

local function sheep()
	return Entities.getEntityByID(fixtures.player().characterWithFollower.followerID)
end

local function assertDead(what)
	assert(sheep().killable.dead, what .. ": expected Marv to be dead")
end

local function assertAlive(what)
	assert(not sheep().killable.dead, what .. ": expected Marv to be alive")
end

local function scene(name, actions, checks)
	fixtures.scene({ name = name, character = marvMod.CHARACTER, actions = actions, checks = checks })
end

scene("murielIsNamedMuriel", { "idle" }, {
	[1] = function()
		local name = fixtures.player().friendlyName.name
		assert(name == "Muriel", "the character is called " .. tostring(name))
	end,
})

-- Two steps right put Marv between Muriel and the Fright zone; then spawn()
-- runs, and the turn after shows whether Marv died.
local function sceneWithMarvBetween(name, spawn, verdict)
	scene(name, { "right", "right", "idle" }, {
		[2] = function()
			fixtures.assertAt(sheep(), 1, 0, "Marv trails Muriel")
			spawn()
		end,
		[3] = verdict,
	})
end

sceneWithMarvBetween("hostileEnemyInFrightZoneFrightensMarvToDeath", function()
	fixtures.spawn("Slime", -4, 2)
end, function()
	assertDead("a green slime in the far corner of the Fright zone")
end)

sceneWithMarvBetween("hostileEnemyOnFrightZoneNearEdgeFrightensMarvToDeath", function()
	fixtures.spawn("Slime", 0, -2)
end, function()
	assertDead("a green slime on the Fright zone's near edge")
end)

-- Marv moved to (0,-1), two tiles over and one up from Muriel, puts his
-- Fright zone on his diagonal: x in -5..-1, y in -6..-2. Muriel teleported
-- instead would bring him along.
local function murielOffAxis(name, spawnX, spawnY, verdict)
	sceneWithMarvBetween(name, function()
		Move.absolute(sheep(), 0, -1, Move.Type.TELEPORT)
		fixtures.spawn("Slime", spawnX, spawnY)
	end, function()
		fixtures.assertAt(sheep(), 0, -1, "Marv stays where he was teleported")
		verdict()
	end)
end

murielOffAxis("offAxisMurielPutsFrightZoneOnDiagonal", -2, -3, function()
	assertDead("a slime in the diagonal Fright zone")
end)

murielOffAxis("offAxisMurielLeavesStraightZoneSafe", -1, -1, function()
	assertAlive("a slime in the straight zone but not the diagonal one")
end)

sceneWithMarvBetween("hostileEnemyPastFrightZoneLeavesMarvAlive", function()
	fixtures.spawn("Slime", -4, 3)
	fixtures.spawn("Slime", -5, 0)
end, function()
	assertAlive("slimes just past the Fright zone")
end)

sceneWithMarvBetween("hostileEnemyBesideMarvLeavesHimAlive", function()
	fixtures.spawn("Slime", 1, 2)
end, function()
	assertAlive("a slime two tiles to Marv's side, outside the Fright zone")
end)

sceneWithMarvBetween("wallHidesEnemyFromMarv", function()
	fixtures.wallColumn(0, -1, 1)
	fixtures.spawn("Slime", -2, 0)
end, function()
	assertAlive("a slime in the Fright zone's square, behind a wall")
end)

-- Line of sight passes between two diagonally touching walls.
sceneWithMarvBetween("diagonalGapDoesNotHideEnemy", function()
	fixtures.wallColumn(0, 0, 0)
	fixtures.wallColumn(1, 1, 1)
	fixtures.spawn("Slime", -1, 2)
end, function()
	assertDead("a slime seen through a diagonal gap between walls")
end)

scene("murielOnMarvDisablesFrightZone", { "right", "right", "left", "idle" }, {
	[2] = function()
		fixtures.spawn("Slime", -2, 0)
	end,
	[3] = function()
		fixtures.assertAt(sheep(), 1, 0, "Marv stays put as Muriel steps onto his tile")
	end,
	[4] = function()
		assertAlive("a slime in the old Fright zone while Muriel shares Marv's tile")
	end,
})

-- Once Muriel walks past Marv to his other side, the Fright zone flips.
scene("frightZoneFollowsMurielsSide", { "right", "right", "left", "left" }, {
	[3] = function()
		fixtures.spawn("Slime", 4, 0)
	end,
	[4] = function()
		fixtures.assertAt(sheep(), 1, 0, "Marv stays put as Muriel passes him")
		assertDead("a slime on Marv's far side from Muriel")
	end,
})

sceneWithMarvBetween("unprovokedShopkeeperInFrightZoneLeavesMarvAlive", function()
	fixtures.spawn("Shopkeeper", -2, 0)
end, function()
	assertAlive("an unprovoked shopkeeper in the Fright zone")
end)

-- A provoked shopkeeper kills Muriel within a turn of reaching her, so he starts
-- behind Marv, who stands between them.
sceneWithMarvBetween("provokedShopkeeperInFrightZoneFrightensMarvToDeath", function()
	local keeper = fixtures.spawn("Shopkeeper", -1, 0)
	Damage.inflict({
		victim = keeper,
		attacker = fixtures.player(),
		damage = 1,
		type = Damage.Type.EXPLOSIVE,
	})
	assert(keeper.provokable.active, "the explosion provoked the shopkeeper")
end, function()
	assertDead("a provoked shopkeeper in the Fright zone")
end)

-- The game puts crates and barrels on a team hostile to Marv, but they are not
-- enemies, so they cause no Death by fright. Crate2 is the barrel.
for _, containerType in ipairs({ "Crate", "Crate2" }) do
	sceneWithMarvBetween(containerType .. "InFrightZoneLeavesMarvAlive", function()
		fixtures.spawn(containerType, 0, 1)
	end, function()
		assertAlive(containerType .. " in the Fright zone")
	end)
end

-- A dormant exploding mushroom is provokable and unprovoked, like a shopkeeper.
sceneWithMarvBetween("dormantExplodingMushroomInFrightZoneLeavesMarvAlive", function()
	local mushroom = fixtures.spawn("MushroomExploding", -1, 1)
	assert(not mushroom.provokable.active, "the exploding mushroom is unprovoked")
end, function()
	assertAlive("a dormant exploding mushroom in the Fright zone")
end)
