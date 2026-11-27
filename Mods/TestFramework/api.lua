local GameSession = require "necro.client.GameSession"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local Tick = require "necro.cycles.Tick"
local FileIO = require "system.game.FileIO"
local Action = require "necro.game.system.Action"
local Input = require "necro.client.Input"
local Turn = require "necro.cycles.Turn"
local Player = require "necro.game.character.Player"
local Beatmap = require "necro.audio.Beatmap"
local Music = require "necro.audio.Music"

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

-- Ticks since the suite loaded, counted by the TestFrameworkTimers handler.
-- The Synchrony sandbox has no os library (os.clock and os.time are missing),
-- so durations are in ticks, which run over 1000 a second.
local tickCount = 0

-- Prints a PASS/FAIL/XFAIL/XPASS line, which
-- `Mods/LiveGame/itj-impure-tests.bash` parses into the run's results.
-- elapsedTicks is optional; when given, the line ends with the duration.
local function log(status, name, reason, elapsedTicks)
	local line = string.format("[TestFramework] %s %s", status, name)
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
  character (string?)     - entity type name to play as (default "Cadence");
    without a default, a test would play whoever the previous test played
  expectFail (boolean?)   - marks this test as expected to fail (default: false).
    A failing/crashing onLoad is then logged as XFAIL instead of FAIL (still an
    overall suite success), and an onLoad that runs to completion without
    failing is logged as XPASS (an anomaly worth investigating: either the
    bug this test guards against got fixed, or the test itself broke)
  noBeat (boolean?)       - plays in no-beat mode, where beats pass only when
    the player acts, so a test can step enemies one action at a time; delayed
    effects such as traps still land in real time (AuthoredDocs/Src/testing.md,
    "No-beat mode")
  async (boolean?)        - lets onLoad outlive its own return: the test then
    ends only when onLoad's second argument, finish, is called (finish() passes,
    finish(message) fails). Drive the game with afterTicks and play below; an
    error raised inside any callback they run fails the test
  file (string?)          - the basename of the file that registers this test,
    e.g. "weapons.lua"; registerTest fills it in from its caller, so set
    it only when a shared helper module registers the test for another file (a
    helper can pass api.callerFile()).
    A test with no file matches every file selection (see selected-test.txt)
  timeoutTicks (integer?) - overrides TEST_TIMEOUT_TICKS, the ticks the test
    may take from its "Running" line, level load included, before it fails
    with "timed out" and the next test runs
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
-- The character a test plays unless it names one.
local DEFAULT_CHARACTER = "Cadence"

local tests = {}
local currentTest = nil
local suiteStartedAt = nil

-- A mod's own directory is not exposed, but the location prefix of a Lua error
-- ("<Bundle>/TestFramework/api.lua:N: ...") names it.
local function findOwnDirectory()
	local _, message = pcall(function()
		error("x")
	end)
	return "mods/" .. assert(message:match("^(.*)/[^/]*:%d+: x$"))
end

-- The basename of the file whose code called the function that calls this
-- (registerTest, or a helper that registers tests for its caller, like
-- fixtures.scene), from the location prefix of a Lua error, as
-- findOwnDirectory does. Level 5 is that caller: 1 is the function below, 2 is
-- pcall, 3 is callerFile, 4 is the function that calls it.
-- (A caller that tail-calls registerTest drops out of the stack; set `file`
-- explicitly there.) Returns nil if the message has an unexpected shape, which
-- makes the test match every selection.
local function callerFile()
	local _, message = pcall(function()
		error("x", 5)
	end)
	return message:match("([^/]*):%d+: x$")
end

-- Selects which tests run; `Mods/LiveGame/itj-impure-tests.bash` has
-- live-game-run write it, and without it the whole suite runs. A line
-- `expect: a.lua b.lua` names the files that must have registered a test
-- before the suite starts. A line `small-samples-except: a.lua b.lua` makes
-- every survey test take its small sample (smallSample, below), except those
-- registered by the listed files. Of the other lines, the first non-empty one
-- is the selection: a bare line is the exact name of one test, and
-- `file: a.lua b.lua` selects every test registered by those files; with
-- none, every test runs.
local SELECTED_TEST_FILE = findOwnDirectory() .. "/selected-test.txt"

-- Splits a list of basenames into a set.
local function basenameSet(list)
	local files = {}
	for file in list:gmatch("%S+") do
		files[file] = true
	end
	return files
end

-- Parses the text of SELECTED_TEST_FILE (format above; "" when the file is
-- missing). Returns the selection (nil, or "name" and a test name, or "files"
-- and a set of basenames), then the set of expected files, or nil, and then
-- the set of files whose survey tests keep their full sample when the others
-- take their small one, or nil when every test takes its full sample.
local function parseSelection(text)
	local kind, selected, expected, fullSample
	for line in text:gmatch("[^\n]+") do
		line = line:match("^%s*(.-)%s*$")
		local expectList = line:match("^expect:%s*(.*)$")
		local fileList = line:match("^file:%s*(.*)$")
		local fullList = line:match("^small%-samples%-except:%s*(.*)$")
		if expectList then
			expected = basenameSet(expectList)
		elseif fullList then
			fullSample = basenameSet(fullList)
		elseif not kind and fileList then
			kind, selected = "files", basenameSet(fileList)
		elseif not kind and line ~= "" then
			kind, selected = "name", line
		end
	end
	return kind, selected, expected, fullSample
end

-- Whether a selection, as parseSelection returns it, keeps the test. A test
-- with no file tag is kept by every file selection (fail safe).
local function matchesSelection(kind, selected, test)
	if kind == "name" then
		return test.name == selected
	end
	return test.file == nil or selected[test.file] == true
end

-- Counts both regular failures and unexpected passes (XPASS)
local failureCount = 0

-- Reports a value the running test observed, as an "OBSERVED" line beside
-- the test's PASS/FAIL line, so a test can answer a question about the game
-- instead of only asserting. Call it from onLoad; value is printed with
-- tostring().
-- The files whose survey tests keep their full sample, as parseSelection
-- returns it: nil until the suite starts, and for a run at full size.
local fullSampleFiles = nil

-- Whether the running survey test should take its small sample: a few runs or
-- trials that exercise the same code, with the assertions that need the full
-- sample skipped. `nix run .#itj-impure-tests -- --small-samples` asks for
-- it, as the hooks do when only the harness changed (ADR 0008). A test with
-- no file tag keeps its full sample.
local function smallSample()
	assert(currentTest, "smallSample may only be called from a running test")
	return fullSampleFiles ~= nil and currentTest.file ~= nil and not fullSampleFiles[currentTest.file]
end

local function observe(key, value)
	assert(currentTest, "observe may only be called from a running test's onLoad")
	print(string.format("[TestFramework] OBSERVED %s %s=%s", currentTest.name, key, tostring(value)))
end

local function registerTest(test)
	assert(type(test.name) == "string", "registerTest requires a name")
	assert(type(test.onLoad) == "function", "registerTest requires an onLoad callback")
	test.file = test.file or callerFile()
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
-- luacheck: globals TestFramework_startGameSession
TestFramework_startGameSession = Tick.delay(function()
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

	-- The level generator's initialCharacters alone leaves the player as the
	-- menu's selected character, so select the test's character too.
	Player.setCharacterType(1, currentTest and currentTest.character or DEFAULT_CHARACTER)

	GameSession.start({
		mode = GameSession.Mode.SingleZone,
	})
end)

local function runNextTest()
	currentTest = table.remove(tests, 1)
	if not currentTest then
		-- Leave Cadence selected, so the game's next run, or a framework
		-- that predates setCharacterType, does not play the last test's
		-- character.
		Player.setCharacterType(1, DEFAULT_CHARACTER)
		-- `Mods/LiveGame/itj-impure-tests.bash` greps this exact "N failure(s)"
		-- phrasing to decide its own exit code, so keep the wording in sync
		-- with it.
		print(string.format(
			"[TestFramework] Test suite completed: %d failure(s) (took %d ticks)",
			failureCount,
			tickCount - suiteStartedAt
		))
		return
	end
	currentTest.startedAt = tickCount
	print(string.format("[TestFramework] Running %s", currentTest.name))
	TestFramework_startGameSession()
end

-- A function(options) that returns the seed to generate a level with in
-- place of FIXED_SEED, or nil; see setSeedOverride.
local seedOverride

-- Pins the seed every test's level is generated with, which is what
-- CurrentLevel.getSeed() reports and what determines level layout, and
-- applies the current test's zone/character overrides, if any.
event.levelGenerate.add("TestFrameworkConfigureLevel", {}, function(ev)
	if not ev.options then
		return
	end
	ev.options.seed = seedOverride and seedOverride(ev.options) or FIXED_SEED
	if currentTest and currentTest.zone then
		ev.options.zone = currentTest.zone
	end
	if currentTest then
		ev.options.initialCharacters = { [1] = currentTest.character or DEFAULT_CHARACTER }
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

--[[
The beat grid, for atBeat: beat is the music time of a beat (the beatmap's
next beat, whose index getCurrentBeat gives), and interval the seconds
between beats, from two beats' times and indexes. The next beat time stays on
a beat until its late window has passed, so it says nothing by itself about
where the beats fall now. A new level restarts the music, so a step back
restarts the grid.
]]
local beatGrid = {}

local function updateBeatGrid()
	local beatmap = Beatmap.getPrimary()
	if not beatmap then
		return
	end
	local index = beatmap:getCurrentBeat()
	local time = beatmap:getNextBeatTime()
	if beatGrid.index and index > beatGrid.index then
		local interval = (time - beatGrid.beat) / (index - beatGrid.index)
		beatGrid.interval = interval > 0.05 and interval or nil
	elseif beatGrid.index ~= index then
		beatGrid.interval = nil
	end
	beatGrid.index = index
	beatGrid.beat = time
end

-- Ticks a test may take, from its "Running" line to its result, level load
-- included, before it fails as timed out. Set to about 3x the slowest test's
-- measured time: controlsDiagonalsAreIgnored took 6127 ticks (full run,
-- 53176 ticks in all), so 18000.
local TEST_TIMEOUT_TICKS = 18000

-- Runs fn after at least n ticks. Ticks run over 1000 times a second.
local function afterTicks(n, fn)
	timers[#timers + 1] = { ticks = n, fn = fn, test = currentTest }
end

event.tick.add("TestFrameworkTimers", { order = "invokeLater" }, function()
	tickCount = tickCount + 1
	updateBeatGrid()
	local test = currentTest
	if test and tickCount - test.startedAt >= (test.timeoutTicks or TEST_TIMEOUT_TICKS) then
		-- Does nothing for a test that already finished.
		finishAsync(test, "timed out")
	end
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
-- Outside no-beat mode, an input waits until the next beat is this close (in
-- seconds of music time), since one sent a fixed number of ticks after the
-- last drifts off the beat and, over about 0.22 s early, becomes a missed beat.
local BEAT_WINDOW_SECONDS = 0.04

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
		local turnBefore
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
		local beatWaited = 0
		local function sendOnBeat()
			beatWaited = beatWaited + 1
			local onBeat = currentTest and currentTest.noBeat
				or math.abs(Beatmap.getPrimary():getNextBeatTime() - Music.getMusicTime()) <= BEAT_WINDOW_SECONDS
			if onBeat or beatWaited >= RESOLVE_TIMEOUT_TICKS then
				turnBefore = Turn.getCurrentTurnID()
				Input.add(action, 1)
				afterTicks(1, waitForTurn)
			else
				afterTicks(1, sendOnBeat)
			end
		end
		sendOnBeat()
	end
	-- An input sent on the tick the level loaded is dropped.
	afterTicks(1, nextAction)
end

-- Sends player 1's action now, named as in ACTIONS, without waiting for the
-- beat; for sub-beat timing, call it from atBeat or atMusicTime.
local function send(name)
	Input.add(assert(ACTIONS[name], "unknown action " .. tostring(name)), 1)
end

-- Calls fn() on the first tick at or after the music time `time`.
local function atMusicTime(time, fn)
	if Music.getMusicTime() >= time then
		fn()
	else
		afterTicks(1, function()
			atMusicTime(time, fn)
		end)
	end
end

--[[
Calls fn(beat, interval) on the first tick at or after `offset` seconds of
music time from a beat (negative: before it), choosing the earliest beat whose
target is at least `lead` seconds (default 0; negative allows a target in the
past) from now. beat is that beat's music time and interval the seconds
between beats. Music time moves every tick, so the call lands within about a
millisecond of its target. A change of tempo (e.g. a tempo trap) is not
followed.
]]
local function atBeat(offset, fn, lead)
	local function waitForGrid()
		if not beatGrid.interval then
			afterTicks(1, waitForGrid)
			return
		end
		local interval = beatGrid.interval
		local behind = Music.getMusicTime() + (lead or 0) - (beatGrid.beat + offset)
		local beat = beatGrid.beat + math.ceil(behind / interval) * interval
		atMusicTime(beat + offset, function()
			fn(beat, interval)
		end)
	end
	waitForGrid()
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

-- How many times a test's session restarts when its player spawned as the
-- wrong character.
local CHARACTER_RETRIES = 3

event.levelLoad.add("TestFrameworkRunOnLoad", { order = "extraEntities", sequence = 1 }, function()
	local test = currentTest
	-- With no current test, the suite has not started (runSuite starts the
	-- first test itself) or has finished, so the level is not the framework's.
	-- Running the queue here would print the completion line again on every
	-- level the player loads, which reads as a fresh suite passing.
	if not test then
		return
	end
	if test.started then
		-- A level change during an async test is part of that test.
		return
	end
	-- A session started just as a reload regenerates the entity schema can
	-- spawn the player as Cadence, even though the test's character, say one a
	-- mod defines, is valid by the time the level loads. Restart the session
	-- then, rather than run the test as the wrong character.
	local retries = test.characterRetries or 0
	local spawnedAs = Player.getCharacterType(1)
	if spawnedAs ~= (test.character or DEFAULT_CHARACTER) and retries < CHARACTER_RETRIES then
		test.characterRetries = retries + 1
		print(string.format("[TestFramework] Restarting %s: the player spawned as %s", test.name, tostring(spawnedAs)))
		TestFramework_startGameSession()
		return
	end
	test.started = true
	runTest(test)
	if not test.async then
		runNextTest()
	end
end)

local started = false

-- One install reloads the game in several batches, and a mod new to the
-- bundle can load in a later batch than this framework. So the suite waits,
-- up to this long, for each expected file to register a test.
local EXPECT_TIMEOUT_TICKS = 10000

-- The expected files that no test in testList comes from, sorted.
local function missingFiles(expected, testList)
	local registered = {}
	for _, test in ipairs(testList) do
		if test.file then
			registered[test.file] = true
		end
	end
	local missing = {}
	for file in pairs(expected) do
		if not registered[file] then
			missing[#missing + 1] = file
		end
	end
	table.sort(missing)
	return missing
end

-- Rechecks testList every tick until each expected file has registered a
-- test, then calls onReady(); after timeoutTicks it calls onTimeout(missing)
-- instead. The callbacks run through afterTicks, so inside an async test an
-- error in them fails that test.
local function waitForFiles(expected, testList, timeoutTicks, onReady, onTimeout)
	local waitStartedAt = tickCount
	local function check()
		local missing = missingFiles(expected, testList)
		if #missing == 0 then
			onReady()
		elseif tickCount - waitStartedAt >= timeoutTicks then
			onTimeout(missing)
		else
			afterTicks(1, check)
		end
	end
	check()
end

-- Filters the tests by the selection, then runs them.
local function runSuite(kind, selected)
	if kind then
		local kept = {}
		for _, test in ipairs(tests) do
			if matchesSelection(kind, selected, test) then
				table.insert(kept, test)
			end
		end
		if #kept == 0 then
			failureCount = failureCount + 1
			if kind == "name" then
				log("FAIL", selected, "no registered test has this name")
			else
				log("FAIL", "fileSelection", "no registered test comes from the selected files")
			end
		end
		tests = kept
	end
	print("[TestFramework] Starting test suite")
	suiteStartedAt = tickCount
	runNextTest()
end

-- Kicks off the suite, once every expected file has registered a test.
-- Idempotent, and safe to call more than once (e.g. once from this mod's own
-- entry script, and again from a Tick.delay-deferred call - see there for
-- why): only the first call has any effect, even while it waits.
local function start()
	if started then
		return
	end
	started = true
	local text = FileIO.exists(SELECTED_TEST_FILE) and FileIO.readFileToString(SELECTED_TEST_FILE, 4096) or ""
	local kind, selected, expected, fullSample = parseSelection(text)
	fullSampleFiles = fullSample
	waitForFiles(expected or {}, tests, EXPECT_TIMEOUT_TICKS, function()
		runSuite(kind, selected)
	end, function(missing)
		failureCount = failureCount + 1
		log("FAIL", "expectedFiles", "no test registered from " .. table.concat(missing, " "))
		tests = {}
		runSuite(nil)
	end)
end

-- Makes the levels generated from now on use seedFunction(options) as their
-- seed instead of the fixed seed, until called again with nil. A handler of
-- its own cannot do this: the framework's handler may run after it.
local function setSeedOverride(seedFunction)
	seedOverride = seedFunction
end

return {
	afterTicks = afterTicks,
	atBeat = atBeat,
	atMusicTime = atMusicTime,
	callerFile = callerFile,
	matchesSelection = matchesSelection,
	missingFiles = missingFiles,
	observe = observe,
	parseSelection = parseSelection,
	play = play,
	registerTest = registerTest,
	send = send,
	setSeedOverride = setSeedOverride,
	smallSample = smallSample,
	start = start,
	waitForFiles = waitForFiles,
}
