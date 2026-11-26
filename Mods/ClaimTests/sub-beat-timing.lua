local Damage = require "necro.game.system.Damage"
local Inventory = require "necro.game.item.Inventory"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays a fixtures.timeline on an open arena, as Cadence on 1-1,
-- whose music has a beat every 0.52 s. Times are seconds from a beat. The
-- player stands at (0,0); "right" steps onto (1,0), where the test puts a
-- trap or the stairs. Health starts at 10 of 20, so heals show.

local player = fixtures.player
local eventsOf = fixtures.eventsOf

local WATCH = {
	health = fixtures.health,
	x = function()
		return player().position.x
	end,
	descending = function()
		return player().descent.active
	end,
}

local function timingTest(name, prepare, steps, check)
	testsApi.registerTest({
		name = name,
		async = true,
		timeoutTicks = 20000,
		onLoad = function(_, finish)
			fixtures.openArena(6)
			player().health.maxHealth = 20
			player().health.health = 10
			if prepare then
				prepare()
			end
			-- Waits out the invincibility and the rhythm leniency a level starts
			-- with; the invincibility is set a tick after onLoad.
			local function settled()
				return player().invincibility.remainingTurns == 0 and player().rhythmLeniency.remainingTurns == 0
			end
			local function start()
				if not settled() then
					testsApi.afterTicks(10, start)
					return
				end
				fixtures.timeline(steps, WATCH, 2, function(events, lastAt)
					check(events, lastAt)
					finish()
				end)
			end
			testsApi.afterTicks(10, start)
		end,
	})
end

local function moves(events)
	return #eventsOf(events, "x")
end

local function misses(events)
	return #eventsOf(events, "missedBeat")
end

-- The health change from the start to the end of the timeline.
local function healthChange(events)
	local changes = eventsOf(events, "health")
	if #changes == 0 then
		return 0
	end
	return changes[#changes].value - 10
end

local function spikes()
	fixtures.spawn("SpikeTrap", 1, 0)
end

local function stairs()
	Tile.setType(1, 0, "Stairs")
end

local function spellHeal()
	Inventory.grant("SpellHeal", player())
end

-- A lone press counts wherever it falls between beats.
for _, step in ipairs({ { "Early", -0.24 }, { "Late", 0.26 } }) do
	timingTest("timingLonePress" .. step[1], nil, { { step[2], "right" } }, function(events)
		assert(moves(events) == 1, "the press moved, got " .. moves(events) .. " moves")
		assert(misses(events) == 0, "no missed beat")
	end)
end

-- A second press soon after the first is a missed beat; pressed on the beat,
-- the next beat's press counts from about 0.3 s after it.
timingTest("timingSecondPressSameBeat", nil, { { 0, "right" }, { 0.15, "left" } }, function(events)
	assert(moves(events) == 1, "the second press did not move, got " .. moves(events) .. " moves")
	assert(misses(events) == 1, "the second press is a missed beat")
end)
timingTest("timingSecondPressStillSameBeat", nil, { { 0, "right" }, { 0.29, "left" } }, function(events)
	assert(moves(events) == 1 and misses(events) == 1, "0.29 s after is still the same beat")
end)
timingTest("timingSecondPressNextBeat", nil, { { 0, "right" }, { 0.31, "left" } }, function(events)
	assert(moves(events) == 2 and misses(events) == 0, "0.31 s after counts for the next beat")
end)

-- A spike trap strikes 0.2 s after you land, wherever in the beat you step.
for _, step in ipairs({ { "Early", -0.15 }, { "OnBeat", 0 }, { "Late", 0.15 } }) do
	timingTest("timingSpikeFuse" .. step[1], spikes, { { step[2], "right" } }, function(events)
		local landed = eventsOf(events, "x")[1]
		local hit = eventsOf(events, "health")[1]
		assert(landed and hit and hit.value == 6, "the spikes hit for 4")
		local fuse = hit.at - landed.at
		assert(fuse > 0.18 and fuse < 0.23, string.format("the spikes struck %.3f s after landing", fuse))
	end)
end

timingTest("timingTrapdoorFuse", function()
	fixtures.spawn("Trapdoor", 1, 0)
end, { { 0.15, "right" } }, function(events)
	local landed = eventsOf(events, "x")[1]
	local dropped = eventsOf(events, "descending")[1]
	assert(landed and dropped and dropped.value, "the trapdoor dropped the player")
	local fuse = dropped.at - landed.at
	assert(fuse > 0.18 and fuse < 0.23, string.format("the trapdoor dropped %.3f s after landing", fuse))
end)

-- Acting during the fuse springs the trap at once, and it still gets you. Left
-- alone, the trap would strike at about 0.355 s.
local STEP_OFF = 0.33
local function atOnce(at)
	return at - STEP_OFF < 0.01
end
timingTest("timingSpikeStepOffStillHits", spikes, { { 0.15, "right" }, { STEP_OFF, "left" } }, function(events)
	local hit = eventsOf(events, "health")[1]
	assert(moves(events) == 2, "stepped on and off")
	assert(hit and hit.value == 6, "stepping off still costs 4")
	assert(atOnce(hit.at), string.format("the press sprang the spikes at once, at %.3f", hit.at))
end)
timingTest("timingTrapdoorStepOffStillDrops", function()
	fixtures.spawn("Trapdoor", 1, 0)
end, { { 0.15, "right" }, { STEP_OFF, "left" } }, function(events)
	local dropped = eventsOf(events, "descending")[1]
	assert(dropped and dropped.value, "the trapdoor still dropped the player")
	assert(atOnce(dropped.at), string.format("the press sprang the trapdoor at once, at %.3f", dropped.at))
end)

-- Food or the heal spell used during the fuse blocks the spikes: their
-- invincibility takes hold before the spikes strike.
local function blocked(name, prepare, steps, expected)
	timingTest(name, function()
		spikes()
		prepare()
	end, steps, function(events)
		assert(misses(events) == 0, "no missed beat")
		local change = healthChange(events)
		assert(change == expected, string.format("expected a health change of %d, got %d", expected, change))
	end)
end
local function food()
	Inventory.grant("Food1", player())
end
for _, step in ipairs({ { "", 0.2 }, { "Later", 0.25 } }) do
	blocked("timingSpikeFoodBlocks" .. step[1], food, { { step[2], "right" }, { 0.33, "item1" } }, 2)
end
blocked("timingSpikeHealBlocks", spellHeal, { { 0.15, "right" }, { 0.33, "spell1" } }, 1)
blocked("timingSpikeHealOnCooldownBlocks", spellHeal, { { -0.52, "spell1" }, { 0.15, "right" }, { 0.33, "spell1" } }, 0)
-- Stepped on the beat, the spikes strike before the next beat's press counts.
blocked("timingSpikeFoodTooLate", food, { { 0, "right" }, { 0.33, "item1" } }, -2)

-- The level ends 0.6 s after you step onto the stairs, wherever in the beat.
for _, step in ipairs({ { "Early", -0.15 }, { "OnBeat", 0 }, { "Late", 0.15 } }) do
	timingTest("timingStairsDescent" .. step[1], stairs, { { step[2], "right" } }, function(events, lastAt)
		assert(eventsOf(events, "level")[1], "the stairs took the player down")
		local descent = lastAt - eventsOf(events, "x")[1].at
		assert(descent > 0.57 and descent < 0.63, string.format("the level ended %.3f s after the step", descent))
	end)
end

-- Nothing hurts you during the descent.
local function hit()
	Damage.inflict({
		victim = player(),
		attacker = fixtures.spawn("Slime", -4, -4),
		damage = 3,
		type = Damage.Type.PHYSICAL,
	})
end
-- Asserts that the stairs ended the level after the step at `at` ran.
local function endedAfter(events, lastAt, at)
	assert(eventsOf(events, "level")[1], "the stairs took the player down")
	assert(lastAt > at + 0.01, string.format("the level ended at %.3f, before the step at %.2f", lastAt, at))
end

timingTest("timingStairsDescentNoDamage", stairs, { { 0, "right" }, { 0.5, hit } }, function(events, lastAt)
	endedAfter(events, lastAt, 0.5)
	assert(healthChange(events) == 0, "the hit did nothing")
end)
timingTest("timingFloorHitControl", nil, { { 0, "right" }, { 0.5, hit } }, function(events)
	assert(healthChange(events) == -3, "the same hit lands off the stairs")
end)

-- The heal spell on cooldown costs health, except during the descent, up to
-- about 0.4 s after the step; a later press does nothing.
timingTest("timingHealOnCooldownCosts", spellHeal, { { 0, "spell1" }, { 0.52, "spell1" } }, function(events)
	assert(healthChange(events) == 0, "+1, then -1 on cooldown")
end)
timingTest("timingStairsHealOnCooldownFree", function()
	stairs()
	spellHeal()
end, { { -0.52, "spell1" }, { 0, "right" }, { 0.37, "spell1" } }, function(events, lastAt)
	endedAfter(events, lastAt, 0.37)
	assert(healthChange(events) == 2, "both casts healed 1")
end)
timingTest("timingStairsLatePressIgnored", function()
	stairs()
	spellHeal()
end, { { -0.52, "spell1" }, { 0, "right" }, { 0.45, "spell1" } }, function(events, lastAt)
	endedAfter(events, lastAt, 0.45)
	assert(healthChange(events) == 1, "only the first cast did anything")
	assert(misses(events) == 0, "the late press is not a missed beat either")
end)
