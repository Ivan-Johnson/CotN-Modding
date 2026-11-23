local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on HelloWorldTests; see tests.lua.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end
local fixtures = require "HelloWorldTests.fixtures"

-- Backs AuthoredDocs/Src/ghost.md. Each test plays Cadence in no-beat mode on
-- an open floor, spawning Ghosts by hand; "up" is toward negative y.
--
-- Spawn every Ghost in setup, before the first action. A Ghost spawned between
-- actions never moves, whatever its aggro or stasis, so a test that needs one
-- to appear mid-scene would silently see a ghost that does nothing.

local function ghostScene(name, setup, actions, checks)
	fixtures.scene({ name = name, setup = setup, actions = actions, checks = checks })
end

local wallColumn = fixtures.wallColumn
local health = fixtures.health
local assertAt = fixtures.assertAt

local function assertGone(ghost, what)
	assert(not Entities.entityExists(ghost.id), what .. ": expected the ghost to be dead")
end

local function assertAlive(ghost, what)
	assert(Entities.entityExists(ghost.id), what .. ": expected the ghost to be alive")
end

-- A ghost that is behind the player follows one tile a beat, hits for 2 every
-- second beat once adjacent, and cannot hit a player who keeps moving.
ghostScene("ghostChasesFromBehind", function()
	return fixtures.spawn("Ghost", 0, 2)
end, { "up", "idle", "idle", "idle", "idle", "up", "up", "up" }, {
	[1] = function(ghost)
		assertAt(ghost, 0, 1, "one tile after the first beat")
		assert(ghost.aggro.active, "a ghost two tiles away has not noticed the player")
	end,
	[2] = function(ghost)
		assertAt(ghost, 0, 0, "adjacent behind the player")
		assert(health() == 12, "it hits on the beat after it arrives, not as it arrives")
	end,
	[3] = function()
		assert(health() == 10, "first hit is 2 damage")
	end,
	[4] = function()
		assert(health() == 10, "no hit on the beat after a hit")
	end,
	[5] = function()
		assert(health() == 8, "a hit every second beat")
	end,
	[6] = function(ghost)
		assertAt(ghost, 0, -1, "following the moving player")
		assert(health() == 8, "no damage while the player keeps moving")
	end,
	[8] = function(ghost)
		assertAt(ghost, 0, -3, "still adjacent behind the player")
		assert(health() == 8, "no damage while the player keeps moving")
	end,
})

-- Frozen ghosts: in front of the player, or on the line through the player
-- perpendicular to the way they face.
ghostScene("ghostFreezesInFrontAndBeside", function()
	return {
		front = fixtures.spawn("Ghost", 0, -3),
		right = fixtures.spawn("Ghost", 2, -1),
		left = fixtures.spawn("Ghost", -1, -1),
	}
end, { "up", "idle", "idle", "idle" }, {
	[1] = function(scene)
		for name, ghost in pairs(scene) do
			assert(ghost.aggro.active, name .. " ghost should be awake, so only the facing freezes it")
		end
	end,
	[4] = function(scene)
		assertAt(scene.front, 0, -3, "front")
		assertAt(scene.right, 2, -1, "right")
		assertAt(scene.left, -1, -1, "left")
		assert(health() == 12, "a frozen ghost never hits")
	end,
})

-- A ghost chasing when a wall blocks its horizontal step slides onto the
-- player's side line, and keeps chasing from there: it hits from beside the
-- player while the player stays put, even though a ghost placed there stays
-- frozen. The wall goes up after the first move, since the player starts on
-- that tile.
ghostScene("ghostSlidesBesideAndAttacks", function()
	return fixtures.spawn("Ghost", 2, 0)
end, { "down", "idle", "idle", "idle", "idle", "idle" }, {
	[1] = function(ghost)
		Tile.setType(0, 0, "StoneWall")
		assertAt(ghost, 1, 0, "behind the player, diagonally")
	end,
	[2] = function(ghost)
		assertAt(ghost, 1, 1, "slid beside the player when the wall blocked the horizontal step")
		assert(health() == 12, "it hits on the beat after it arrives")
	end,
	[3] = function()
		assert(health() == 10, "hits from beside the player")
	end,
	[4] = function()
		assert(health() == 10, "no hit on the beat after a hit")
	end,
	[5] = function()
		assert(health() == 8, "a hit every second beat")
	end,
})

-- A dagger bump toward a ghost that is chasing from beside the player kills
-- it, before or after it has hit.
for _, beats in ipairs({ { "down", "idle", "right" }, { "down", "idle", "idle", "right" } }) do
	ghostScene("ghostBesideDiesToDaggerBump" .. #beats, function()
		return fixtures.spawn("Ghost", 2, 0)
	end, beats, {
		[1] = function()
			Tile.setType(0, 0, "StoneWall")
		end,
		[#beats] = function(ghost)
			assertGone(ghost, "dagger bump toward a ghost beside the player")
		end,
	})
end

-- Ghosts that start on the side line or in front stay frozen and never hit.
ghostScene("ghostSpawnedOnTheLineStaysFrozen", function()
	return {
		right = fixtures.spawn("Ghost", 1, 1),
		left = fixtures.spawn("Ghost", -1, 1),
		farRight = fixtures.spawn("Ghost", 2, 1),
		front = fixtures.spawn("Ghost", 0, 2),
	}
end, { "down", "idle", "idle", "idle", "idle" }, {
	[5] = function(scene)
		assertAt(scene.right, 1, 1, "right")
		assertAt(scene.left, -1, 1, "left")
		assertAt(scene.farRight, 2, 1, "farRight")
		assertAt(scene.front, 0, 2, "front")
		assert(health() == 12, "frozen ghosts never hit")
	end,
})

-- A ghost re-checks which side of the player it is on only when the player
-- moves to a new tile. Bumping stone turns the player, but a frozen ghost
-- that is now behind stays frozen until the next move.
ghostScene("ghostRecheckOnlyWhenThePlayerMoves", function()
	Tile.setType(-1, 1, "StoneWall")
	return fixtures.spawn("Ghost", 1, 1)
end, { "down", "left", "idle", "idle", "up", "idle" }, {
	[2] = function()
		assert(fixtures.player().facingDirection.direction == 5, "the bump turns the player left")
	end,
	[4] = function(ghost)
		assertAt(ghost, 1, 1, "still frozen after the turn")
		assert(health() == 12, "no hit after the turn")
	end,
	[5] = function(ghost)
		assertAt(ghost, 0, 1, "chasing once the player moves")
	end,
})

-- Each ghost reacts to the first move: the first steps horizontally first
-- although it is farther away vertically, the other two have their horizontal
-- step blocked by a wall or an enemy and take the vertical one.
ghostScene("ghostStepsHorizontallyThenVertically", function()
	Tile.setType(1, 0, "StoneWall")
	fixtures.spawn("Slime", -1, 0)
	return {
		farBelow = fixtures.spawn("Ghost", 1, 1),
		blocked = fixtures.spawn("Ghost", 2, 0),
		blockedByEnemy = fixtures.spawn("Ghost", -2, 0),
	}
end, { "up" }, {
	[1] = function(scene)
		assertAt(scene.farBelow, 0, 1, "horizontal step first")
		assertAt(scene.blocked, 2, -1, "vertical step when a wall blocks the horizontal one")
		assertAt(scene.blockedByEnemy, -2, -1, "vertical step when an enemy blocks the horizontal one")
	end,
})

-- A ghost wakes within two tiles of the player and in line of sight; once
-- awake it stays awake, is stopped by walls, and resumes from any distance.
ghostScene("ghostWakesWithinTwoTilesAndStaysAwake", function()
	wallColumn(-1, 1, 1, "StoneWall")
	wallColumn(0, 1, 1, "StoneWall")
	wallColumn(1, 1, 1, "StoneWall")
	return {
		far = fixtures.spawn("Ghost", 0, -3),
		near = fixtures.spawn("Ghost", 2, 0),
		hidden = fixtures.spawn("Ghost", 0, 2),
	}
end, { "idle", "left", "left", "left", "left", "left", "left", "left", "left", "idle", "idle", "idle" }, {
	[1] = function(scene)
		assert(not scene.far.aggro.active, "a ghost three tiles away in plain sight stays asleep")
		assert(scene.near.aggro.active, "a ghost two tiles away wakes")
		assert(not scene.hidden.aggro.active, "a ghost behind a wall stays asleep")
		wallColumn(1, -1, 0, "StoneWall")
	end,
	[9] = function(scene)
		assertAt(scene.near, 2, 0, "blocked by the wall while the player walks away")
		wallColumn(1, -1, 0, "Floor")
	end,
	[10] = function(scene)
		assertAt(scene.near, 1, 0, "resumes the chase from ten tiles away")
	end,
	[12] = function(scene)
		assertAt(scene.near, -1, 0, "keeps chasing")
	end,
})

-- Turning to face a ghost that is adjacent behind kills it in one hit. The
-- kill counts for the coin multiplier, and the coin is worth 4 gold at x1.
ghostScene("ghostDiesWhenTheDaggerTurnsOnIt", function()
	return fixtures.spawn("Ghost", 0, 1)
end, { "up", "down", "down" }, {
	[2] = function(ghost)
		assertGone(ghost, "turned on from behind")
		assert(fixtures.player().grooveChain.multiplier == 2, "the kill raises the coin multiplier")
	end,
	[3] = function()
		assert(fixtures.player().goldCounter.amount == 4, "a ghost drops 4 gold at x1")
	end,
})

-- Nothing in front of or beside the player can hurt a frozen ghost, neither a
-- dagger bump nor a bomb blast, while a bomb kills one that is chasing.
ghostScene("ghostFrozenIsInvulnerable", function()
	return fixtures.spawn("Ghost", 0, -2)
end, { "up", "up", "bomb", "idle", "idle", "idle" }, {
	[2] = function(ghost)
		assertAlive(ghost, "after a dagger bump")
	end,
	[6] = function(ghost)
		assert(health() == 8, "the blast reached the player")
		assertAlive(ghost, "after the blast")
	end,
})

ghostScene("ghostBombKillsChasingGhost", function()
	return fixtures.spawn("Ghost", 0, 2)
end, { "up", "bomb", "idle", "idle", "idle" }, {
	[4] = function(ghost)
		assertAlive(ghost, "before the blast")
	end,
	[5] = function(ghost)
		assertGone(ghost, "after the blast")
	end,
})

-- A trident turning toward a chasing ghost two tiles behind kills it; a dagger
-- only steps toward it, which freezes it.
for _, weapon in ipairs({ "Sync_WeaponTitaniumTrident", "WeaponDagger" }) do
	ghostScene("ghostTwoTilesBehindWith" .. weapon, function()
		if weapon ~= "WeaponDagger" then
			Inventory.grant(weapon, fixtures.player())
		end
		return fixtures.spawn("Ghost", 0, 2)
	end, { "idle", "up", "down" }, {
		[3] = function(ghost)
			if weapon == "WeaponDagger" then
				assertAlive(ghost, "dagger")
			else
				assertGone(ghost, "trident")
			end
		end,
	})
end

-- The coin is worth 8 gold at x3, the cap, which five kills reach.
ghostScene("ghostGoldAtFullMultiplier", function()
	for x = 1, 5 do
		fixtures.spawn("Slime", x, 0)
	end
	return {}
end, { "right", "right", "right", "right", "right", "right", "right", "right", "right", "right", "left", "left" }, {
	[9] = function(scene)
		assert(fixtures.player().grooveChain.multiplier == 3, "five kills reach x3")
		scene.ghost = fixtures.spawn("Ghost", 3, 0)
		scene.goldBefore = fixtures.player().goldCounter.amount
	end,
	[11] = function(scene)
		assertGone(scene.ghost, "turned on from behind")
		scene.goldBefore = fixtures.player().goldCounter.amount
	end,
	[12] = function(scene)
		local gold = fixtures.player().goldCounter.amount - scene.goldBefore
		assert(gold == 8, "a ghost drops 8 gold at x3, got " .. gold)
	end,
})

-- A ghost that comes with the level follows the same rules: it sleeps until
-- the player is within two tiles, stays frozen while faced, chases once the
-- player turns away, and dies to the turn back.
testsApi.registerTest({
	name = "naturalGhostFollowsTheRules",
	noBeat = true,
	async = true,
	onLoad = function(_, finish)
		-- Level 3 has ghosts. A level change from the first level takes effect
		-- late, so go through level 2 and poll.
		GameSession.goToLevel(2)
		testsApi.afterTicks(400, function()
			GameSession.goToLevel(3)
			local function whenLoaded()
				if CurrentLevel.getNumber() ~= 3 then
					testsApi.afterTicks(10, whenLoaded)
					return
				end
				testsApi.afterTicks(300, function()
					fixtures.openArena(12, "Ghost")
					local ghost
					for candidate in Entities.entitiesWithComponents({ "ai" }) do
						local distance = math.abs(candidate.position.x) + math.abs(candidate.position.y)
						if not ghost or distance < math.abs(ghost.position.x) + math.abs(ghost.position.y) then
							ghost = candidate
						end
					end
					local x, y = ghost.position.x, ghost.position.y
					assert(not ghost.aggro.active, "a level's ghost starts asleep")

					-- Walk to three tiles to the ghost's right, then onto its row.
					local actions = {}
					for _ = 1, math.abs(x + 3) do
						table.insert(actions, x + 3 > 0 and "right" or "left")
					end
					for _ = 1, math.abs(y) do
						table.insert(actions, y > 0 and "down" or "up")
					end
					local approached = #actions
					for _, action in ipairs({ "left", "right", "idle", "left", "left" }) do
						table.insert(actions, action)
					end

					testsApi.play(actions, function(index)
						if index == approached then
							assertAt(ghost, x, y, "asleep while the player approaches")
						elseif index == approached + 1 then
							assertAt(ghost, x, y, "frozen while the player faces it")
							assert(ghost.aggro.active, "awake two tiles away")
						elseif index == approached + 2 then
							assertAt(ghost, x + 1, y, "chasing once the player turns away")
						elseif index == approached + 4 then
							assertGone(ghost, "turned on from behind")
						end
					end, finish)
				end)
			end
			whenLoaded()
		end)
	end,
})
