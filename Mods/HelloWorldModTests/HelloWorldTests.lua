local GameMod = require "necro.game.data.resource.GameMod"
local GameSession = require "necro.client.GameSession"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Tick = require "necro.cycles.Tick"
local Entities = require "system.game.Entities"
local Map = require "necro.game.object.Map"
local Marker = require "necro.game.tile.Marker"

local FIXED_SEED = 20240101

local function log(status, name, reason)
	if reason then
		print(string.format("[HelloWorldTests] %s %s: %s", status, name, reason))
	else
		print(string.format("[HelloWorldTests] %s %s", status, name))
	end
end

if not GameMod.isModLoaded("HelloWorld") then
	log("FAIL", "dependency", "HelloWorldMod is not loaded")
	return
end
log("PASS", "dependency")

--[[
Minimal test harness: registerTest() queues a test, and the harness runs each
queued test in its own fixed-seed GameSession, one after another. A test is a
table:
  name (string, required) - unique id, prefixes this test's PASS/FAIL lines
  zone (integer?)         - procedural zone number to generate the level in
  character (string?)     - entity type name to play as, e.g. "Cadence"
  expectFail (boolean?)   - marks this test as expected to fail (default: false).
    A failing/crashing onLoad is then logged as XFAIL instead of FAIL (still an
    overall suite success), and an onLoad that runs to completion without
    failing is logged as XPASS (an anomaly worth investigating: either the
    bug this test guards against got fixed, or the test itself broke)
  onLoad (function(), required)
    - runs once the level has loaded; call the builtin assert(condition,
      reason) once per assertion. A failing assert aborts the rest of this
      test's onLoad (later assertions in the same test are skipped, since
      they may rely on the failed one having held). Any other Lua error
      raised from onLoad (e.g. a bad API call) is caught and treated the
      same as a failing assert
]]
local tests = {}
local currentTest = nil

-- Counts both regular failures and unexpected passes (XPASS)
local failureCount = 0

local function registerTest(test)
	assert(type(test.name) == "string", "registerTest requires a name")
	assert(type(test.onLoad) == "function", "registerTest requires an onLoad callback")
	table.insert(tests, test)
end

-- Defined once and reused for every queued test's session (Tick.delay's
-- result must be bound to a global variable, and re-created wrapper closures
-- reusing that same global confuse its binding check).
-- luacheck: globals HelloWorldTests_startGameSession
HelloWorldTests_startGameSession = Tick.delay(function()
	-- Force every extra mode off, since e.g. All Characters Mode replaces
	-- the level's exit with one staircase per remaining character, which
	-- would break stairs-marker-based assertions.
	for _, mode in pairs(ExtraMode.Type) do
		if mode ~= ExtraMode.Type.NONE then
			ExtraMode.setActive(mode, false)
		end
	end

	GameSession.start({
		mode = GameSession.Mode.SingleZone,
	})
end)

local function runNextTest()
	currentTest = table.remove(tests, 1)
	if not currentTest then
		-- `run-tests` greps this exact "N failure(s)" phrasing to decide
		-- its own exit code, so keep the wording in sync with it.
		print(string.format("[HelloWorldTests] Test suite completed: %d failure(s)", failureCount))
		return
	end
	print(string.format("[HelloWorldTests] Running %s", currentTest.name))
	HelloWorldTests_startGameSession()
end

-- Pins the seed every test's level is generated with, which is what
-- CurrentLevel.getSeed() reports and what determines level layout, and
-- applies the current test's zone/character overrides, if any.
event.levelGenerate.add("TestHarnessConfigureLevel", {}, function(ev)
	if not ev.options then
		return
	end
	ev.options.seed = FIXED_SEED
	if currentTest and currentTest.zone then
		ev.options.zone = currentTest.zone
	end
	if currentTest and currentTest.character then
		ev.options.initialCharacters = { [1] = currentTest.character }
	end
end)

-- Runs one test's onLoad, which asserts its expectations with the builtin
-- assert(condition, reason). Any Lua error it raises (a failing assert, or
-- any other error, e.g. a bad API call) is caught here and logged as FAIL,
-- or XFAIL if the test declares expectFail; otherwise the test passed.
local function runTest(test)
	local ok, err = pcall(test.onLoad)
	if ok then
		if test.expectFail then
			failureCount = failureCount + 1
			log("XPASS", test.name, "expected this test to fail, but it passed")
		else
			log("PASS", test.name)
		end
		return
	end

	if test.expectFail then
		log("XFAIL", test.name, tostring(err))
	else
		failureCount = failureCount + 1
		log("FAIL", test.name, tostring(err))
	end
end

event.levelLoad.add("TestHarnessRunOnLoad", { order = "extraEntities", sequence = 1 }, function()
	if currentTest then
		runTest(currentTest)
	end
	runNextTest()
end)

registerTest({
	name = "checkFailureExpected",
	expectFail = true,
	onLoad = function()
		assert(false, "deliberately failing to exercise expectFail")
	end,
})

registerTest({
	name = "crashExpected",
	expectFail = true,
	onLoad = function()
		-- Deliberately calls a Synchrony API with invalid arguments, to
		-- exercise the harness recovering from an onLoad that crashes
		-- outright rather than failing an explicit assert().
		Map.getAll(nil, nil)
	end,
})

registerTest({
	name = "appleSpawnsOnStairs",
	onLoad = function()
		assert(CurrentLevel.getSeed() == FIXED_SEED, string.format(
			"expected level seed %d, got %s", FIXED_SEED, tostring(CurrentLevel.getSeed())))

		local stairs = Marker.lookUpAll(Marker.Type.STAIRS)
		assert(#stairs == 1, string.format(
			"expected exactly 1 stairs marker, got %d", #stairs))

		local entityIDs = Map.getAll(stairs[1][1], stairs[1][2])
		local foundApple = false
		for _, entityID in ipairs(entityIDs) do
			if Entities.getEntityTypeName(Entities.getEntityByID(entityID)) == "Food1" then
				assert(not foundApple, "Expected exactly one apple")
				foundApple = true
			end
		end
	end,
})


-- Kick off the suite as soon as this mod loads, so it runs unattended from
-- mod (re)load to log output.
print("[HelloWorldTests] Starting test suite")
runNextTest()
