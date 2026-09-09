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
  onLoad (function(pass, fail), required)
    - runs once the level has loaded; call pass(assertion) / fail(assertion, reason)
      once per check
]]
local tests = {}
local currentTest = nil

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
		print("[HelloWorldTests] Test suite completed")
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

event.levelLoad.add("TestHarnessRunOnLoad", { order = "extraEntities", sequence = 1 }, function()
	local test = currentTest
	if test then
		local function pass(assertion)
			log("PASS", test.name .. "." .. assertion)
		end
		local function fail(assertion, reason)
			log("FAIL", test.name .. "." .. assertion, reason)
		end
		test.onLoad(pass, fail)
	end
	runNextTest()
end)

registerTest({
	name = "appleSpawnsOnStairs",
	onLoad = function(pass, fail)
		if CurrentLevel.getSeed() == FIXED_SEED then
			pass("fixedSeed")
		else
			fail("fixedSeed", string.format(
				"expected level seed %d, got %s", FIXED_SEED, tostring(CurrentLevel.getSeed())))
		end

		local stairs = Marker.lookUpAll(Marker.Type.STAIRS)
		local foundApple = false
		for _, pos in ipairs(stairs) do
			for _, entityID in ipairs(Map.getAll(pos[1], pos[2])) do
				if Entities.getEntityTypeName(Entities.getEntityByID(entityID)) == "Food1" then
					foundApple = true
				end
			end
		end
		if foundApple then
			pass("appleOnStairs")
		else
			fail("appleOnStairs", string.format(
				"no Food1 entity at any of %d stairs marker(s)", #stairs))
		end
	end,
})

-- Kick off the suite as soon as this mod loads, so it runs unattended from
-- mod (re)load to log output.
print("[HelloWorldTests] Starting test suite")
runNextTest()
