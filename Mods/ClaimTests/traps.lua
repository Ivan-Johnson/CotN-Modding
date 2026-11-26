local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local Inventory = require "necro.game.item.Inventory"
local Music = require "necro.audio.Music"
local Object = require "necro.game.object.Object"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Most traps act a fraction of a second after the step that lands on them,
-- which no-beat mode never lets pass, so those tests play to the beat: the
-- player stands still between inputs and waits are in ticks. Bounce traps act
-- at once, so their tests use no-beat scenes. "up" is toward negative y.

local health = fixtures.health
local player = fixtures.player
local assertAt = fixtures.assertAt

local function entityAt(typeName, x, y)
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name == typeName and entity.position.x == x and entity.position.y == y then
			return entity
		end
	end
	return nil
end

local function holds(itemType)
	for _, item in ipairs(Inventory.getItems(player())) do
		if item.name == itemType then
			return true
		end
	end
	return false
end

local function replaceSlot(slot, itemType)
	for _, item in ipairs(Inventory.getItemsInSlot(player(), slot)) do
		Object.delete(item)
	end
	if itemType then
		Inventory.grant(itemType, player())
	end
end

-- Ticks to wait after each action, so that the next one lands on a later beat
-- instead of counting as a second input within one beat.
local ACTION_GAP = 600

--[[
Registers a test played to the beat on an open arena. setup runs first and
its result is passed to every check. steps is a list run in order: an action
name (e.g. "right", followed by ACTION_GAP ticks of waiting), a number of
ticks to wait, a function(state) holding assertions, or
{ poll = function(state), every = ticks, times = n }, which calls poll every
`every` ticks until it returns true or has run n times, or { walkTo = { x, y } },
which moves (along x first) until the player stands there. The first step waits
out the invincibility a level starts with.
]]
local function beatTest(name, setup, steps)
	testsApi.registerTest({
		name = name,
		async = true,
		timeoutTicks = 60000,
		onLoad = function(_, finish)
			fixtures.openArena(8)
			local state = setup and setup() or {}
			local index = 0
			local step
			local function poll(spec, count)
				if count >= spec.times or spec.poll(state) then
					step()
				else
					testsApi.afterTicks(spec.every, function()
						poll(spec, count + 1)
					end)
				end
			end
			-- An input can miss its beat, so walking moves until the player is
			-- there rather than a fixed number of times.
			local function walk(x, y, count)
				local position = player().position
				local dx = x - position.x
				local dy = y - position.y
				if dx == 0 and dy == 0 then
					step()
					return
				end
				assert(count < 40, string.format("could not walk to (%d,%d)", x, y))
				local direction = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
				testsApi.play({ direction }, nil, function()
					testsApi.afterTicks(ACTION_GAP, function()
						walk(x, y, count + 1)
					end)
				end)
			end
			step = function()
				index = index + 1
				local current = steps[index]
				if current == nil then
					finish()
				elseif type(current) == "number" then
					testsApi.afterTicks(current, step)
				elseif type(current) == "function" then
					current(state)
					step()
				elseif type(current) == "table" and current.walkTo then
					walk(current.walkTo[1], current.walkTo[2], 0)
				elseif type(current) == "table" then
					poll(current, 0)
				else
					testsApi.play({ current }, nil, function()
						testsApi.afterTicks(ACTION_GAP, step)
					end)
				end
			end
			testsApi.afterTicks(1200, step)
		end,
	})
end

-- A spike trap hits for 4 a moment after you land on it, once per step onto
-- it: standing on it is safe, stepping off and back on hits again.
beatTest("trapsSpikeHitsOncePerStepOnto", function()
	fixtures.spawn("SpikeTrap", 1, 0)
	return { start = health() }
end, {
	"right",
	1500,
	function(state)
		assert(health() == state.start - 4, "landing on spikes costs 4, got " .. state.start - health())
	end,
	1500,
	function(state)
		assert(health() == state.start - 4, "standing on the spikes costs nothing more")
	end,
	"right",
	1500,
	"left",
	1500,
	function(state)
		assert(health() == state.start - 8, "stepping back on hits again")
	end,
})

-- The level's own spike traps hit the same as spawned ones.
beatTest("trapsLevelSpikeHits", function()
	assert(entityAt("SpikeTrap", 0, 7), "the fixed-seed level has a spike trap at (0,7)")
	fixtures.openArena(9)
	return { start = health() }
end, {
	-- Down column x = 2, then left and up onto (0,7) from below, which
	-- passes no other trap of the level.
	{ walkTo = { 2, 0 } },
	{ walkTo = { 2, 8 } },
	{ walkTo = { 0, 8 } },
	{ walkTo = { 0, 7 } },
	1500,
	function(state)
		assertAt(player(), 0, 7, "on the level's spike trap")
		assert(health() == state.start - 4, "the level's spike trap costs 4, got " .. state.start - health())
	end,
})

-- Enemies take the same 4 each time they land on spikes. A Slime2 bounces
-- between (3,2) and the spikes at (3,3) every other beat.
beatTest("trapsSpikeHurtsEnemies", function()
	fixtures.spawn("SpikeTrap", 3, 3)
	local slime = fixtures.spawn("Slime2", 3, 2)
	slime.health.maxHealth = 20
	slime.health.health = 20
	return slime
end, {
	5000,
	function(slime)
		local lost = 20 - slime.health.health
		assert(lost >= 8 and lost % 4 == 0, "each landing on the spikes costs 4, lost " .. lost)
	end,
})

-- An automatic spike trap springs on its own: it hits a player who is placed
-- on it and never moves. Then it leaves them alone until they step off and
-- back on.
beatTest("trapsAutoSpikeSpringsOnItsOwn", function()
	fixtures.spawn("Sync_AutoSpikeTrap", 0, 0)
	return { start = health() }
end, {
	4000,
	function(state)
		assert(health() == state.start - 4, "it springs without a step, for 4; lost " .. state.start - health())
	end,
	3000,
	function(state)
		assert(health() == state.start - 4, "no second hit while standing still")
	end,
	"right",
	1000,
	"left",
	4000,
	function(state)
		assert(health() == state.start - 8, "stepping off and back on lets it hit again")
	end,
})

-- A bomb trap drops a lit bomb on itself; the blast hurts like the player's own
-- bomb and destroys the trap.
beatTest("trapsBombTrapStayAndGetHit", function()
	fixtures.spawn("BombTrap", 1, 0)
	return { start = health() }
end, {
	"right",
	600,
	function()
		assert(entityAt("BombLit", 1, 0), "a lit bomb lies on the trap")
	end,
	3000,
	function(state)
		assert(health() == state.start - 4, "the blast costs 4, got " .. state.start - health())
		assert(not entityAt("BombTrap", 1, 0), "the blast destroys the bomb trap")
	end,
})

beatTest("trapsBombTrapRunAway", function()
	fixtures.spawn("BombTrap", 1, 0)
	return { start = health() }
end, {
	"right",
	"right",
	"right",
	3500,
	function(state)
		assert(not entityAt("BombLit", 1, 0), "the bomb has gone off")
		assert(health() == state.start, "two tiles from the bomb is safe")
	end,
})

-- A trapdoor drops the player to the next level, with health and items kept.
beatTest("trapsTrapdoorDescends", function()
	return { level = CurrentLevel.getNumber(), start = health(), items = #Inventory.getItems(player()) }
end, {
	function()
		fixtures.spawn("Trapdoor", 1, 0)
	end,
	"right",
	6000,
	function(state)
		assert(CurrentLevel.getNumber() == state.level + 1, "the trapdoor leads to the next level")
		assert(health() == state.start, "health is unchanged")
		assert(#Inventory.getItems(player()) == state.items, "items are kept")
	end,
})

-- Tempo traps change the music's speed by an eighth for a few seconds. The
-- poll records the furthest the speed got from normal, and stops once it is
-- back to normal.
local function tempoTest(name, trapType, factor)
	beatTest(name, function()
		fixtures.spawn(trapType, 1, 0)
		return { extreme = 1 }
	end, {
		"right",
		{
			every = 200,
			times = 150,
			poll = function(state)
				local pitch = Music.getEffectivePitch()
				if math.abs(pitch - 1) > math.abs(state.extreme - 1) then
					state.extreme = pitch
				end
				return pitch == 1 and state.extreme ~= 1
			end,
		},
		function(state)
			local message = string.format("the music peaked at %.3f, expected %.3f", state.extreme, factor)
			assert(math.abs(state.extreme - factor) < 0.001, message)
			assert(Music.getEffectivePitch() == 1, "the music is back to normal speed")
		end,
	})
end

tempoTest("trapsTempoUpSpeedsMusic", "TempoUpTrap", 1.125)
tempoTest("trapsTempoDownSlowsMusic", "TempoDownTrap", 0.875)

-- A confusion trap reverses the player's directions for about ten beats.
beatTest("trapsConfusionReversesControls", function()
	fixtures.spawn("ConfusionTrap", 1, 0)
	return {}
end, {
	"right",
	1000,
	function()
		local turns = player().confusable.remainingTurns
		assert(turns >= 7 and turns <= 10, "confused for about ten beats, " .. turns .. " left")
	end,
	"right",
	function()
		assertAt(player(), 0, 0, "right moves left")
	end,
	"up",
	function()
		assertAt(player(), 0, 1, "up moves down")
	end,
	"left",
	function()
		assertAt(player(), 1, 1, "left moves right")
	end,
	"down",
	function()
		assertAt(player(), 1, 0, "down moves up")
	end,
	8000,
	function()
		assert(player().confusable.remainingTurns == 0, "the confusion wears off")
	end,
	"right",
	function()
		assertAt(player(), 2, 0, "right moves right again")
	end,
})

-- A scatter trap knocks the player's equipment onto the tiles around them;
-- bombs and spells stay.
local SCATTERED = { "WeaponDagger", "ShovelBasic", "RingCourage", "ArmorLeather", "HeadMinersCap", "Torch1", "Food1" }
beatTest("trapsScatterDropsEquipment", function()
	replaceSlot("weapon", "WeaponDagger")
	replaceSlot("shovel", "ShovelBasic")
	replaceSlot("ring", "RingCourage")
	replaceSlot("body", "ArmorLeather")
	replaceSlot("head", "HeadMinersCap")
	replaceSlot("torch", "Torch1")
	replaceSlot("feet", nil)
	replaceSlot("spell", "SpellFireball")
	if not holds("Bomb") then
		Inventory.grant("Bomb", player())
	end
	Inventory.grant("Food1", player())
	fixtures.spawn("ScatterTrap", 1, 0)
	return {}
end, {
	"right",
	1000,
	function()
		for _, itemType in ipairs(SCATTERED) do
			assert(not holds(itemType), itemType .. " is knocked out of the inventory")
			local found = false
			for entity in Entities.entitiesWithComponents({ "item" }) do
				if entity.name == itemType and entity.position then
					local dx = math.abs(entity.position.x - 1)
					local dy = math.abs(entity.position.y)
					found = found or (dx <= 2 and dy <= 2 and (dx + dy) > 0)
				end
			end
			assert(found, itemType .. " lands within two tiles of the trap")
		end
		assert(holds("Bomb"), "bombs stay")
		assert(holds("SpellFireball"), "spells stay")
	end,
})

-- A teleport trap sends the player to another spot on the level.
beatTest("trapsTeleportMovesAway", function()
	fixtures.spawn("TeleportTrap", 1, 0)
	return {}
end, {
	"right",
	1000,
	function()
		local position = player().position
		local distance = math.abs(position.x - 1) + math.abs(position.y)
		assert(distance >= 3, string.format("teleported only to (%d,%d)", position.x, position.y))
		local info = Tile.getInfo(position.x, position.y)
		assert(info and info.isFloor, "the player lands on floor")
	end,
})

-- Bounce traps push the player one more tile in the same action.
local function bounce(name, traps, actions, x, y, what, prepare)
	fixtures.scene({
		name = name,
		radius = 6,
		setup = function()
			for _, trap in ipairs(traps) do
				fixtures.spawn(trap[1], trap[2], trap[3])
			end
			if prepare then
				prepare()
			end
		end,
		actions = actions,
		checks = {
			[#actions] = function()
				assertAt(player(), x, y, what)
			end,
		},
	})
end

bounce("trapsBounceWithArrow", { { "BounceTrapRight", 1, 0 } }, { "right" }, 2, 0, "pushed on along the arrow")
bounce("trapsBounceAcrossArrow", { { "BounceTrapUp", 1, 0 } }, { "right" }, 1, -1, "pushed up off the trap")
bounce("trapsBounceAgainstArrow", { { "BounceTrapLeft", 1, 0 } }, { "right" }, 0, 0, "pushed back where it came from")
bounce("trapsBounceDiagonal", { { "BounceTrapUpRight", 1, 0 } }, { "right" }, 2, -1, "pushed diagonally")
bounce("trapsBounceOmniRight", { { "BounceTrapOmni", 1, 0 } }, { "right" }, 2, 0, "omni continues the move")
bounce("trapsBounceOmniUp", { { "BounceTrapOmni", 0, -1 } }, { "up" }, 0, -2, "omni continues the move")
bounce(
	"trapsBounceChains",
	{ { "BounceTrapUp", 1, 0 }, { "BounceTrapRight", 1, -1 } },
	{ "right" },
	2,
	-1,
	"one bounce trap pushes onto the next"
)
local function wallAbove()
	Tile.setType(1, -1, "StoneWall")
end
bounce("trapsBounceIntoWall", { { "BounceTrapUp", 1, 0 } }, { "right" }, 1, 0, "a wall keeps it on the trap", wallAbove)

-- Enemies bounce too: a Slime2 that hops down onto a right arrow at (3,3)
-- lands on (4,3).
beatTest("trapsBounceMovesEnemies", function()
	fixtures.spawn("BounceTrapRight", 3, 3)
	return fixtures.spawn("Slime2", 3, 2)
end, {
	{
		every = 100,
		times = 40,
		poll = function(slime)
			return slime.position.y ~= 2
		end,
	},
	function(slime)
		assertAt(slime, 4, 3, "the slime is pushed along the arrow")
	end,
})

-- A bounce onto spikes sets the spikes off.
beatTest("trapsBounceOntoSpikes", function()
	fixtures.spawn("BounceTrapUp", 1, 0)
	fixtures.spawn("SpikeTrap", 1, -1)
	return { start = health() }
end, {
	"right",
	1500,
	function(state)
		assertAt(player(), 1, -1, "bounced onto the spikes")
		assert(health() == state.start - 4, "the spikes hit for 4")
	end,
})
