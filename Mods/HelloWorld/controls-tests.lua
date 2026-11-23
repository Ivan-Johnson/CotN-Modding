local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"
local Tile = require "necro.game.tile.Tile"
local Turn = require "necro.cycles.Turn"

-- Optional dependency on HelloWorldTests; see tests.lua.
local ok, testsApi = pcall(require, "HelloWorldTests.api")
if not ok then
	return
end
local fixtures = require "HelloWorldTests.fixtures"

-- Backs AuthoredDocs/Src/controls.md. Each test plays Cadence on an open
-- floor in no-beat mode ("up" is toward negative y), except the rhythm test.

local RIGHT, UP, LEFT, DOWN = 1, 3, 5, 7

local function facing()
	return fixtures.player().facingDirection.direction
end

local function chain()
	return fixtures.player().grooveChain.multiplier
end

local function health()
	return fixtures.player().health.health
end

local function assertAt(x, y, what)
	local position = fixtures.player().position
	assert(
		position.x == x and position.y == y,
		string.format("%s: expected the player at (%d,%d), got (%d,%d)", what, x, y, position.x, position.y)
	)
end

local function itemNames()
	local names = {}
	local playerID = fixtures.player().id
	for entity in Entities.entitiesWithComponents({ "item" }) do
		if entity.item.holder == playerID then
			names[entity.name] = true
		end
	end
	return names
end

-- The first action is always "up", which kills a Slime to raise the coin
-- multiplier to 2; the checks and the other actions follow it. The checks'
-- indexes count from the action after that kill.
local function controlsScene(name, setup, actions, checks, arenaRadius)
	local all = { "up" }
	for _, action in ipairs(actions) do
		table.insert(all, action)
	end
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			fixtures.openArena(arenaRadius or 10)
			fixtures.spawn("Slime", 0, -1)
			local scene = setup and setup() or {}
			local turns = {}
			testsApi.play(all, function(index, _, resolved)
				if index == 1 then
					assert(chain() == 2, "a kill raises the coin multiplier to 2")
					turns[0] = Turn.getCurrentTurnID()
					return
				end
				turns[index - 1] = Turn.getCurrentTurnID()
				local check = checks[index - 1]
				if check then
					check(scene, resolved, turns[index - 1] ~= turns[index - 2])
				end
			end, finish)
		end,
	})
end

-- Moves go one tile in a direction and turn the player that way. Idle keeps
-- the facing, passes a beat and breaks the coin chain.
controlsScene("controlsMoveFaceAndIdle", nil, { "right", "down", "left", "idle", "up" }, {
	[1] = function(_, resolved, turnPassed)
		assertAt(1, 0, "moving right")
		assert(facing() == RIGHT, "facing right")
		assert(resolved and turnPassed, "a move passes a beat")
		assert(chain() == 2, "moving to an empty tile keeps the chain")
	end,
	[2] = function()
		assertAt(1, 1, "moving down")
		assert(facing() == DOWN, "facing down")
	end,
	[3] = function()
		assertAt(0, 1, "moving left")
		assert(facing() == LEFT, "facing left")
	end,
	[4] = function(_, _, turnPassed)
		assertAt(0, 1, "idle stays")
		assert(facing() == LEFT, "idle keeps the facing")
		assert(turnPassed, "idle passes a beat")
		assert(chain() == 1, "idle breaks the chain")
	end,
	[5] = function()
		assertAt(0, 0, "moving up")
		assert(facing() == UP, "facing up")
	end,
})

-- Pressing toward a wall the starting shovel cannot dig, or the level's
-- border, only turns the player: a failed action that still passes a beat
-- (enemies move) and breaks the chain.
controlsScene("controlsWallBumpIsAFailedAction", function()
	Tile.setType(1, 0, "StoneWall")
	Tile.setType(-1, 0, "LevelBorder")
	return { loop = fixtures.spawn("Slime3", 3, 3) }
end, { "right", "left", "right", "right" }, {
	[1] = function(scene, _, turnPassed)
		assertAt(0, 0, "a stone wall blocks")
		assert(facing() == RIGHT, "a wall bump turns the player")
		assert(turnPassed, "a wall bump passes a beat")
		assert(chain() == 1, "a wall bump breaks the chain")
		assert(Tile.getInfo(1, 0).name == "StoneWall", "the stone wall stays")
		scene.loopAfterBump = { scene.loop.position.x, scene.loop.position.y }
	end,
	[2] = function(scene)
		assertAt(0, 0, "the level border blocks")
		assert(facing() == LEFT, "a border bump turns the player")
		local before = scene.loopAfterBump
		local after = scene.loop.position
		assert(before[1] ~= after.x or before[2] ~= after.y, "enemies move during a failed action")
	end,
	[4] = function()
		assert(Tile.getInfo(1, 0).name == "StoneWall", "the starting shovel does not dig stone")
	end,
})

-- Pressing toward dirt digs it (a beat, the player stays, the chain holds);
-- a door opens the same way; the next press walks through.
controlsScene("controlsDirtAndDoorsOpenByBumping", function()
	Tile.setType(1, 0, "DirtWall")
	Tile.setType(-1, 0, "DoorVertical")
end, { "right", "right", "left", "left" }, {
	[1] = function(_, _, turnPassed)
		assertAt(0, 0, "digging does not move")
		assert(turnPassed, "digging passes a beat")
		assert(Tile.getInfo(1, 0).name == "Floor", "dirt becomes floor")
		assert(facing() == RIGHT, "digging turns the player")
		assert(chain() == 2, "digging keeps the chain")
	end,
	[2] = function()
		assertAt(1, 0, "walking into the dug tile")
	end,
	[3] = function()
		assertAt(0, 0, "walking back")
	end,
	[4] = function()
		assertAt(0, 0, "opening the door does not move")
		assert(Tile.getInfo(-1, 0).name == "Floor", "an opened door is floor")
		assert(facing() == LEFT, "opening a door turns the player")
		assert(chain() == 2, "opening a door keeps the chain")
	end,
})

-- Pressing toward an enemy attacks it and the player stays; toward a chest
-- opens it; toward a crate slides the crate one tile. None breaks the chain.
controlsScene("controlsBumpsAttackOpenAndPush", function()
	return {
		skeleton = fixtures.spawn("Skeleton2", 1, 0),
		chest = fixtures.spawn("ChestBlack", -1, 0),
		crate = fixtures.spawn("Crate", 0, 1),
		crate2 = fixtures.spawn("Crate2", 0, -2),
	}
end, { "right", "left", "down", "up", "up" }, {
	[1] = function(scene, _, turnPassed)
		assertAt(0, 0, "attacking does not move")
		assert(facing() == RIGHT, "attacking turns the player")
		assert(turnPassed, "attacking passes a beat")
		assert(scene.skeleton.health.health == 1, "the dagger hit for 1")
		assert(chain() == 2, "hitting an enemy keeps the chain")
	end,
	[2] = function(scene)
		assertAt(0, 0, "opening a chest does not move")
		assert(not Entities.entityExists(scene.chest.id), "the chest opens")
		assert(facing() == LEFT, "opening a chest turns the player")
		assert(chain() == 2, "opening a chest keeps the chain")
	end,
	[3] = function(scene)
		assertAt(0, 0, "pushing a crate does not move")
		assert(Entities.entityExists(scene.crate.id), "pushing does not break the crate")
		assert(scene.crate.position.x == 0 and scene.crate.position.y == 2, "the crate slides one tile")
		assert(facing() == DOWN, "pushing a crate turns the player")
		assert(chain() == 2, "pushing keeps the chain")
	end,
	[4] = function()
		assertAt(0, -1, "walking up")
	end,
	[5] = function(scene)
		assertAt(0, -1, "pushing a crate does not move")
		assert(Entities.entityExists(scene.crate2.id), "pushing does not break the crate")
		assert(scene.crate2.position.y == -3, "the second crate type slides one tile too")
	end,
})

-- Diagonal inputs are ignored: no beat passes, and neither the facing nor the
-- chain changes.
local DIAGONALS = { "left", "up_right", "up_left", "down_left", "down_right", "right" }
controlsScene("controlsDiagonalsAreIgnored", nil, DIAGONALS, {
	[2] = function(_, resolved)
		assert(not resolved, "up_right is ignored")
	end,
	[3] = function(_, resolved)
		assert(not resolved, "up_left is ignored")
	end,
	[4] = function(_, resolved)
		assert(not resolved, "down_left is ignored")
	end,
	[5] = function(_, resolved)
		assert(not resolved, "down_right is ignored")
		assertAt(-1, 0, "diagonals do not move")
		assert(facing() == LEFT, "diagonals do not turn the player")
		assert(chain() == 2, "diagonals do not break the chain")
	end,
	[6] = function()
		assertAt(0, 0, "ordinary moves still work")
	end,
})

-- An item is used with item1, which keeps the chain and the facing; an empty
-- slot (no item, no spell, no bomb) is a failed action.
-- Each failed use is followed by a kill that restores the chain, so the next
-- failed use shows its own effect.
controlsScene("controlsItemsSpellsAndBombs", function()
	fixtures.spawn("Food1", 1, 0)
	fixtures.spawn("Slime", 2, 0)
	fixtures.spawn("Slime", 3, 0)
	fixtures.player().health.health = 6
end, { "right", "item1", "item1", "right", "spell1", "right", "right", "bomb", "bomb" }, {
	[1] = function()
		assert(itemNames().Food1, "walking onto food picks it up")
		assert(chain() == 2, "picking up keeps the chain")
		assert(health() == 6, "food is not eaten on pickup")
	end,
	[2] = function()
		assert(not itemNames().Food1, "item1 uses the item")
		assert(health() == 8, "food heals 2")
		assert(chain() == 2, "using an item keeps the chain")
		assert(facing() == RIGHT, "using an item keeps the facing")
	end,
	[3] = function(_, _, turnPassed)
		assert(turnPassed, "a failed action passes a beat")
		assert(chain() == 1, "an empty item slot is a failed action")
		assert(facing() == RIGHT, "a failed action keeps the facing")
	end,
	[4] = function()
		assert(chain() == 2, "a kill restores the chain")
	end,
	[5] = function(_, _, turnPassed)
		assert(turnPassed, "a failed action passes a beat")
		assert(chain() == 1, "an empty spell slot is a failed action")
	end,
	[7] = function()
		assert(chain() == 2, "a kill restores the chain")
	end,
	[8] = function()
		assert(not itemNames().Bomb, "placing a bomb spends it")
		assert(facing() == RIGHT, "placing a bomb keeps the facing")
		assert(chain() == 2, "placing a bomb keeps the chain")
	end,
	[9] = function(_, _, turnPassed)
		assert(turnPassed, "bomb with none left passes a beat")
		assert(chain() == 1, "bomb with none left breaks the chain")
	end,
})

-- Picking up a second action item swaps it with the one held and leaves the
-- first on that tile.
controlsScene("controlsActionItemPickupSwaps", function()
	fixtures.spawn("Food1", 1, 0)
	fixtures.spawn("HolyWater", 2, 0)
end, { "right", "right", "left", "right" }, {
	[2] = function()
		local names = itemNames()
		assert(names.HolyWater and not names.Food1, "the new item replaces the held one")
	end,
	[4] = function()
		local names = itemNames()
		assert(names.Food1 and not names.HolyWater, "walking back onto the dropped item swaps again")
	end,
})

-- A spell that has recharged is free; otherwise it costs 1 health. The Earth
-- Spell recharges after 10 kills.
controlsScene("controlsSpellRechargesAfterTenKills", function()
	Inventory.grant("SpellEarth", fixtures.player())
	for x = 2, 11 do
		fixtures.spawn("Slime", x, 0)
	end
end, (function()
	local actions = { "spell1", "right", "right" }
	for _ = 1, 10 do
		table.insert(actions, "right")
		table.insert(actions, "right")
	end
	table.insert(actions, "spell1")
	table.insert(actions, "spell1")
	return actions
end)(), {
	[1] = function()
		assert(health() == 12, "a charged spell is free")
		assert(chain() == 2, "casting keeps the chain")
		assert(facing() == UP, "casting keeps the facing")
	end,
	[24] = function()
		assert(health() == 12, "a spell recharged by 10 kills is free")
	end,
	[25] = function()
		assert(health() == 11, "casting before it recharges costs 1 health")
	end,
}, 14)

-- With no input the beat goes on: enemies move and the chain breaks.
testsApi.registerTest({
	name = "controlsRhythmKeepsBeatingWithoutInput",
	async = true,
	onLoad = function(_, finish)
		fixtures.openArena(10)
		fixtures.spawn("Slime", 0, -1)
		local loop = fixtures.spawn("Slime3", 3, 3)
		local start
		local moved = false
		-- The slime walks a 4-tile loop, so compare each sample with where it
		-- started rather than only the last one.
		local function watch(ticksLeft)
			if loop.position.x ~= start[1] or loop.position.y ~= start[2] then
				moved = true
			end
			if ticksLeft > 0 then
				testsApi.afterTicks(50, function()
					watch(ticksLeft - 50)
				end)
				return
			end
			assert(chain() == 1, "a missed beat breaks the chain")
			assert(moved, "enemies move without input")
			finish()
		end
		testsApi.play({ "up" }, function()
			assert(chain() == 2, "a kill raises the coin multiplier to 2")
			start = { loop.position.x, loop.position.y }
		end, function()
			watch(3000)
		end)
	end,
})
