local Entities = require "system.game.Entities"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Backs testing.md's "No-beat mode" section: no-beat mode runs two clocks.
-- Each test plays Cadence in no-beat mode on an open floor, from (0,0); "up"
-- is toward negative y.

local player = fixtures.player
local health = fixtures.health
local assertAt = fixtures.assertAt

local function exists(typeName)
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name == typeName then
			return true
		end
	end
	return false
end

-- Polls every 10 ticks until done() holds, up to limit ticks, then calls
-- andThen with whether it held.
local function waitFor(done, limit, andThen, waited)
	waited = waited or 0
	if done() or waited >= limit then
		andThen(done())
		return
	end
	testsApi.afterTicks(10, function()
		waitFor(done, limit, andThen, waited + 10)
	end)
end

local function noBeatTest(name, body)
	testsApi.registerTest({ name = name, noBeat = true, async = true, timeoutTicks = 30000, onLoad = body })
end

local function confused()
	return player().confusable.remainingTurns > 0
end

-- A trap's effect lands a moment after the step onto it, in real time and
-- without another input: later than api.play's settle.
local LANDED = {
	ConfusionTrap = confused,
	TeleportTrap = function()
		local position = player().position
		return position.x ~= 1 or position.y ~= 0
	end,
}
for trapType, landed in pairs(LANDED) do
	noBeatTest("testingNoBeatDelayLandsWithoutInput" .. trapType, function(_, finish)
		fixtures.openArena(8)
		fixtures.spawn(trapType, 1, 0)
		testsApi.play({ "idle", "right" }, nil, function()
			assertAt(player(), 1, 0, "on the trap")
			assert(not landed(), "the effect has not landed when api.play returns")
			waitFor(landed, 1000, function(held)
				assert(held, "the effect lands within 1000 ticks, with no further input")
				finish()
			end)
		end)
	end)
end

-- An input sent before the delay runs out lands the pending effect first:
-- the confusion reverses the very input that follows the step.
noBeatTest("testingNoBeatNextInputLandsPendingDelay", function(_, finish)
	fixtures.openArena(8)
	fixtures.spawn("ConfusionTrap", 1, 0)
	testsApi.play({ "idle", "right", "right" }, nil, function()
		assert(confused(), "confused")
		assertAt(player(), 0, 0, "the second right moved left")
		finish()
	end)
end)

-- Waiting ticks passes no beats: the invincibility a level starts with
-- outlasts the wait, so a spike trap stepped onto first costs nothing, and the
-- next step onto one costs 4.
noBeatTest("testingNoBeatTickWaitKeepsLevelStartInvincibility", function(_, finish)
	fixtures.openArena(8)
	local start = health()
	testsApi.afterTicks(3000, function()
		assert(player().invincibility.remainingTurns > 0, "still invincible after 3000 ticks")
		fixtures.spawn("SpikeTrap", 1, 0)
		fixtures.spawn("SpikeTrap", 1, 1)
		testsApi.play({ "right" }, nil, function()
			testsApi.afterTicks(1000, function()
				assert(health() == start, "the first step's spikes cost nothing")
				testsApi.play({ "down" }, nil, function()
					testsApi.afterTicks(1000, function()
						assert(health() == start - 4, "the second step's spikes cost 4, lost " .. start - health())
						finish()
					end)
				end)
			end)
		end)
	end)
end)

-- A bomb's fuse counts beats, so waiting ticks never sets it off; idles do.
noBeatTest("testingNoBeatTickWaitKeepsBombLit", function(_, finish)
	fixtures.openArena(8)
	testsApi.play({ "idle", "bomb" }, nil, function()
		testsApi.afterTicks(3000, function()
			assert(exists("BombLit"), "the bomb is still lit after 3000 ticks")
			testsApi.play(fixtures.repeated("idle", 4), nil, function()
				assert(not exists("BombLit"), "four idles set it off")
				finish()
			end)
		end)
	end)
end)
