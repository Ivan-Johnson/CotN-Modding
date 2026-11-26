local CurrentLevel = require "necro.game.level.CurrentLevel"
local Map = require "necro.game.object.Map"
local Tick = require "necro.cycles.Tick"

local api = require "HelloWorldTests.api"

-- Self-tests exercising the harness itself (api.lua's expectFail/crash
-- recovery machinery), not any particular mod under test.
api.registerTest({
	name = "checkFailureExpected",
	expectFail = true,
	onLoad = function()
		assert(false, "deliberately failing to exercise expectFail")
	end,
})

api.registerTest({
	name = "crashExpected",
	expectFail = true,
	onLoad = function()
		-- Deliberately calls a Synchrony API with invalid arguments, to
		-- exercise the harness recovering from an onLoad that crashes
		-- outright rather than failing an explicit assert().
		Map.getAll(nil, nil)
	end,
})

-- A test that never finishes must time out and let the next test run: the
-- tests after this one only run if it does.
api.registerTest({
	name = "frameworkTimeoutFailsAndContinues",
	expectFail = true,
	async = true,
	timeoutTicks = 200,
	onLoad = function() end,
})

-- Exercises observe(): the entrypoint's output must show this value next to
-- the PASS line. Also the quickest named test to run alone.
api.registerTest({
	name = "observesFixedSeed",
	onLoad = function(fixedSeed)
		api.observe("seed", fixedSeed)
		assert(CurrentLevel.getSeed() == fixedSeed, "the level was not generated from the fixed seed")
	end,
})

-- registerTest tags each test with the file that called it, and a file
-- selection keeps the tests of its files. Tests registered in a loop share the
-- tag of the file whose loop made them.
local selfTagged = {}
for index = 1, 2 do
	local test = {
		name = "fileTagFromLoop" .. index,
		onLoad = function()
			api.observe("file", selfTagged[index].file)
			-- Not a plain "<mod>.lua" string, which install-mods would try to rewrite.
			assert(selfTagged[index].file == "HelloWorldTests" .. ".lua", "a loop-registered test has the wrong file tag")
		end,
	}
	selfTagged[index] = test
	api.registerTest(test)
end

local explicitFileTest
explicitFileTest = {
	name = "fileTagExplicit",
	file = "other-tests.lua",
	onLoad = function()
		assert(explicitFileTest.file == "other-tests.lua", "registerTest overwrote an explicit file")
	end,
}
api.registerTest(explicitFileTest)

api.registerTest({
	name = "fileSelectionMatching",
	onLoad = function()
		local files = { ["a-tests.lua"] = true }
		assert(api.matchesSelection("files", files, { file = "a-tests.lua" }), "tagged file not selected")
		assert(not api.matchesSelection("files", files, { file = "b-tests.lua" }), "other file selected")
		assert(api.matchesSelection("files", files, {}), "an untagged test was not selected")
		assert(api.matchesSelection("name", "x", { name = "x" }), "named test not selected")
		assert(not api.matchesSelection("name", "x", { name = "y" }), "other name selected")
	end,
})

-- A set's keys, sorted and joined by spaces, so a failing assert shows them.
local function setText(set)
	if set == nil then
		return "<nil>"
	end
	local keys = {}
	for key in pairs(set) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return table.concat(keys, " ")
end

-- The inputs are the shapes `runPass` in `Mods/itj-impure-tests.bash` writes:
-- an `expect:` line, then the selection, which may be empty.
api.registerTest({
	name = "selectionParsing",
	onLoad = function()
		local kind, selected, expected = api.parseSelection("")
		assert(kind == nil and selected == nil and expected == nil, "a missing file selected something")

		kind, selected, expected = api.parseSelection("expect: a.lua b.lua\n")
		assert(kind == nil and selected == nil, "expect: alone made a selection")
		assert(setText(expected) == "a.lua b.lua", "expected files: " .. setText(expected))

		kind, selected, expected = api.parseSelection("expect: \n")
		assert(kind == nil and selected == nil, "an empty expect: made a selection")
		assert(setText(expected) == "", "an empty expect: gave expected files: " .. setText(expected))

		kind, selected, expected = api.parseSelection("expect: a.lua\nobservesFixedSeed\n")
		assert(kind == "name" and selected == "observesFixedSeed", "name selection: " .. tostring(selected))
		assert(setText(expected) == "a.lua", "expected files beside a name: " .. setText(expected))

		kind, selected, expected = api.parseSelection("expect: a.lua\nfile: b.lua c.lua\n")
		assert(kind == "files", "file: line parsed as " .. tostring(kind))
		assert(setText(selected) == "b.lua c.lua", "selected files: " .. setText(selected))
		assert(setText(expected) == "a.lua", "expected files beside file: " .. setText(expected))
	end,
})

api.registerTest({
	name = "missingExpectedFiles",
	onLoad = function()
		local expected = { ["a.lua"] = true, ["b.lua"] = true, ["c.lua"] = true }
		local missing = api.missingFiles(expected, { { file = "b.lua" }, { name = "untagged" } })
		assert(table.concat(missing, " ") == "a.lua c.lua", "missing: " .. table.concat(missing, " "))
		assert(#api.missingFiles({}, {}) == 0, "nothing expected, yet something is missing")
	end,
})

-- A file that registers after the wait began ends the wait.
api.registerTest({
	name = "expectWaitSeesLateFile",
	async = true,
	onLoad = function(_, finish)
		local testList = {}
		local registered = false
		api.waitForFiles({ ["late.lua"] = true }, testList, 1000, function()
			finish(not registered and "ready before late.lua registered" or nil)
		end, function()
			finish("timed out with late.lua registered")
		end)
		api.afterTicks(10, function()
			registered = true
			table.insert(testList, { file = "late.lua" })
		end)
	end,
})

-- An expected file that never registers ends the wait after its timeout.
api.registerTest({
	name = "expectWaitTimesOut",
	async = true,
	onLoad = function(_, finish)
		local waited = false
		api.waitForFiles({ ["never.lua"] = true }, {}, 50, function()
			finish("ready with never.lua missing")
		end, function(missing)
			assert(table.concat(missing, " ") == "never.lua", "missing: " .. table.concat(missing, " "))
			finish(not waited and "timed out early" or nil)
		end)
		api.afterTicks(40, function()
			waited = true
		end)
	end,
})

-- Deferred by one tick so that any other mod's own load-time
-- api.registerTest() call - triggered by this same reload, if this mod's
-- api.lua changed - has a chance to run first: a reload always finishes an
-- entire batch of scripts before the next tick, but does not guarantee this
-- entry script runs last within that batch.
-- luacheck: globals HelloWorldTests_start
HelloWorldTests_start = Tick.delay(api.start)
HelloWorldTests_start()
