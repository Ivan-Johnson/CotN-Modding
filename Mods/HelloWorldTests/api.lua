local GameSession = require "necro.client.GameSession"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local Tick = require "necro.cycles.Tick"
local FileIO = require "system.game.FileIO"
local Action = require "necro.game.system.Action"
local Input = require "necro.client.Input"
local Turn = require "necro.cycles.Turn"

--[[
Generic, reusable test-running framework. Any mod may contribute test cases
by requiring this module and calling registerTest() at load-time - see the
registerTest doc comment below for the test table's shape. This module
deliberately never requires (or otherwise depends on) any particular mod
under test: the dependency direction runs the other way, with each mod under
test optionally requiring *this* module. That keeps this test framework
reusable across multiple mods, and means a mod under test never needs to
declare a dependency on this test-only mod, so players installing it don't
need this mod installed too.
]]
local FIXED_SEED = 20240101

-- Ticks since the suite loaded, counted by the TestHarnessTimers handler. The
-- Synchrony sandbox has no os library (os.clock and os.time are missing), so
-- durations are in ticks, which run over 1000 a second.
local tickCount = 0

-- elapsedTicks is optional; when given, the line ends with the duration.
local function log(status, name, reason, elapsedTicks)
	local line = string.format("[HelloWorldTests] %s %s", status, name)
	if reason then
		line = line .. ": " .. reason
	end
	if elapsedTicks then
		line = string.format("%s (%d ticks)", line, elapsedTicks)
	end
	print(line)
end

--[[
tests: queued via registerTest(), and run one at a time, each in its own
fixed-seed GameSession. A test is a table:
  name (string, required) - unique id, prefixes this test's PASS/FAIL lines;
    registering the same name again replaces the earlier test
  zone (integer?)         - procedural zone number to generate the level in
  character (string?)     - entity type name to play as, e.g. "Cadence"
  expectFail (boolean?)   - marks this test as expected to fail (default: false).
    A failing/crashing onLoad is then logged as XFAIL instead of FAIL (still an
    overall suite success), and an onLoad that runs to completion without
    failing is logged as XPASS (an anomaly worth investigating: either the
    bug this test guards against got fixed, or the test itself broke)
  noBeat (boolean?)       - plays in no-beat mode, where time passes only when
    the player acts, so a test can step enemies one action at a time
  async (boolean?)        - lets onLoad outlive its own return: the test then
    ends only when onLoad's second argument, finish, is called (finish() passes,
    finish(message) fails). Drive the game with afterTicks and play below; an
    error raised inside any callback they run fails the test
  onLoad (function(fixedSeed, finish), required)
    - runs once the level has loaded, and is passed the seed the level was
      generated with; call the builtin assert(condition, reason) once per
      assertion. A failing assert aborts the rest of this test's onLoad
      (later assertions in the same test are skipped, since they may rely on
      the failed one having held). To report a value, call
      api.observe(key, value) (defined below). Any other Lua error raised from onLoad
      (e.g. a bad API call) is caught and treated the same as a failing
      assert
]]
local tests = {}
local currentTest = nil
local suiteStartedAt = nil

-- A mod's own directory is not exposed, but the location prefix of a Lua error
-- ("<Bundle>/HelloWorldTests/api.lua:N: ...") names it.
local function findOwnDirectory()
	local _, message = pcall(function()
		error("x")
	end)
	return "mods/" .. assert(message:match("^(.*)/[^/]*:%d+: x$"))
end

-- Names the one test to run alone; written by the unit-test entrypoint, absent
-- (so the whole suite runs) otherwise.
local SELECTED_TEST_FILE = findOwnDirectory() .. "/selected-test.txt"

local function readSelectedTest()
	if not FileIO.exists(SELECTED_TEST_FILE) then
		return nil
	end
	local name = FileIO.readFileToString(SELECTED_TEST_FILE, 256):match("^%s*(.-)%s*$")
	if name == "" then
		return nil
	end
	return name
end

-- Counts both regular failures and unexpected passes (XPASS)
local failureCount = 0

-- Reports a value the running test observed, as an "OBSERVED" line beside
-- the test's PASS/FAIL line, so a test can answer a question about the game
-- instead of only asserting. Call it from onLoad; value is printed with
-- tostring().
local function observe(key, value)
	assert(currentTest, "observe may only be called from a running test's onLoad")
	print(string.format("[HelloWorldTests] OBSERVED %s %s=%s", currentTest.name, key, tostring(value)))
end

local function registerTest(test)
	assert(type(test.name) == "string", "registerTest requires a name")
	assert(type(test.onLoad) == "function", "registerTest requires an onLoad callback")
	-- A reload can run a mod's load-time registerTest() calls again against
	-- this same module instance, so a repeated name replaces its earlier
	-- test instead of queueing a second run of it.
	for index, existing in ipairs(tests) do
		if existing.name == test.name then
			tests[index] = test
			return
		end
	end
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

	if currentTest and currentTest.noBeat then
		ExtraMode.setActive(ExtraMode.Type.NO_BEAT, true)
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
		print(string.format(
			"[HelloWorldTests] Test suite completed: %d failure(s) (took %d ticks)",
			failureCount,
			tickCount - suiteStartedAt
		))
		return
	end
	currentTest.startedAt = tickCount
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

-- Logs one test's outcome: err is nil when it passed. An expectFail test logs
-- XFAIL for a failure and XPASS for a pass.
local function report(test, err)
	local elapsed = tickCount - test.startedAt
	if err == nil then
		if test.expectFail then
			failureCount = failureCount + 1
			log("XPASS", test.name, "expected this test to fail, but it passed", elapsed)
		else
			log("PASS", test.name, nil, elapsed)
		end
	elseif test.expectFail then
		log("XFAIL", test.name, tostring(err), elapsed)
	else
		failureCount = failureCount + 1
		log("FAIL", test.name, tostring(err), elapsed)
	end
end

-- Ends the running async test, once; later calls (e.g. a stray callback
-- after a failure) do nothing.
local function finishAsync(test, err)
	if currentTest ~= test or test.finished then
		return
	end
	test.finished = true
	report(test, err)
	runNextTest()
end

-- Runs fn; an error in it fails the running test instead of vanishing into the
-- game's event loop.
local function guarded(fn, ...)
	local test = currentTest
	local ok, err = pcall(fn, ...)
	if not ok and test and test.async then
		finishAsync(test, err)
	end
end

local timers = {}

-- Runs fn after at least n ticks. Ticks run over 1000 times a second.
local function afterTicks(n, fn)
	timers[#timers + 1] = { ticks = n, fn = fn, test = currentTest }
end

event.tick.add("TestHarnessTimers", { order = "invokeLater" }, function()
	tickCount = tickCount + 1
	local due = {}
	local waiting = {}
	for _, timer in ipairs(timers) do
		timer.ticks = timer.ticks - 1
		-- A timer left by a test that has ended is dropped.
		if timer.test == currentTest then
			if timer.ticks <= 0 then
				due[#due + 1] = timer
			else
				waiting[#waiting + 1] = timer
			end
		end
	end
	timers = waiting
	for _, timer in ipairs(due) do
		guarded(timer.fn)
	end
end)

local ACTIONS = {
	right = Action.Direction.RIGHT,
	up_right = Action.Direction.UP_RIGHT,
	up = Action.Direction.UP,
	up_left = Action.Direction.UP_LEFT,
	left = Action.Direction.LEFT,
	down_left = Action.Direction.DOWN_LEFT,
	down = Action.Direction.DOWN,
	down_right = Action.Direction.DOWN_RIGHT,
	idle = Action.Special.IDLE,
	item1 = Action.Special.ITEM_1,
	item2 = Action.Special.ITEM_2,
	bomb = Action.Special.BOMB,
	spell1 = Action.Special.SPELL_1,
	spell2 = Action.Special.SPELL_2,
}

-- Ticks to wait after an action resolves before the next one, since enemies
-- skip moves when inputs are queued back to back.
local SETTLE_TICKS = 30
-- Ticks to wait for an action to advance the turn before giving up on it.
local RESOLVE_TIMEOUT_TICKS = 1500

-- Sends player 1's actions one at a time, naming them as the keys of ACTIONS
-- (e.g. "right", "idle", "bomb"). After each action resolves and settles,
-- calls afterEach(index, name, resolved) (resolved is false when the turn never
-- advanced, e.g. a diagonal input), then finished() after the last.
local function play(names, afterEach, finished)
	local index = 0
	local nextAction
	local function resolved(didResolve)
		if afterEach then
			afterEach(index, names[index], didResolve)
		end
		nextAction()
	end
	nextAction = function()
		index = index + 1
		if index > #names then
			if finished then
				finished()
			end
			return
		end
		local action = assert(ACTIONS[names[index]], "unknown action " .. tostring(names[index]))
		local turnBefore = Turn.getCurrentTurnID()
		Input.add(action, 1)
		local waited = 0
		local function waitForTurn()
			waited = waited + 1
			if Turn.getCurrentTurnID() ~= turnBefore then
				afterTicks(SETTLE_TICKS, function()
					resolved(true)
				end)
			elseif waited >= RESOLVE_TIMEOUT_TICKS then
				resolved(false)
			else
				afterTicks(1, waitForTurn)
			end
		end
		afterTicks(1, waitForTurn)
	end
	-- An input sent on the tick the level loaded is dropped.
	afterTicks(1, nextAction)
end

-- Runs one test's onLoad, which asserts its expectations with the builtin
-- assert(condition, reason). Any Lua error it raises (a failing assert, or
-- any other error, e.g. a bad API call) is caught here and logged as FAIL,
-- or XFAIL if the test declares expectFail; otherwise the test passed. An
-- async test's outcome is logged when it calls finish instead.
local function runTest(test)
	if test.async then
		local ok, err = pcall(test.onLoad, FIXED_SEED, function(message)
			finishAsync(test, message)
		end)
		if not ok then
			finishAsync(test, err)
		end
		return
	end
	local ok, err = pcall(test.onLoad, FIXED_SEED)
	report(test, not ok and err or nil)
end

event.levelLoad.add("TestHarnessRunOnLoad", { order = "extraEntities", sequence = 1 }, function()
	local test = currentTest
	if test and test.started then
		-- A level change during an async test is part of that test.
		return
	end
	if test then
		test.started = true
		runTest(test)
	end
	if not (test and test.async) then
		runNextTest()
	end
end)

local started = false

-- Kicks off the suite, running every test registered by then. Idempotent,
-- and safe to call more than once (e.g. once from this mod's own entry
-- script, and again from a Tick.delay-deferred call - see there for why):
-- only the first call has any effect.
local function start()
	if started then
		return
	end
	started = true
	local selected = readSelectedTest()
	if selected then
		local kept = {}
		for _, test in ipairs(tests) do
			if test.name == selected then
				table.insert(kept, test)
			end
		end
		if #kept == 0 then
			failureCount = failureCount + 1
			log("FAIL", selected, "no registered test has this name")
		end
		tests = kept
	end
	print("[HelloWorldTests] Starting test suite")
	suiteStartedAt = tickCount
	runNextTest()
end

return {
	afterTicks = afterTicks,
	observe = observe,
	play = play,
	registerTest = registerTest,
	start = start,
}
