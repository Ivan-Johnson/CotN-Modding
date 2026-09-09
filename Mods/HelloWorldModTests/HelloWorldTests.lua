local GameMod = require "necro.game.data.resource.GameMod"
local GameSession = require "necro.client.GameSession"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Tick = require "necro.cycles.Tick"
local Entities = require "system.game.Entities"
local Map = require "necro.game.object.Map"
local Marker = require "necro.game.tile.Marker"

local FIXED_SEED = 20240101

local function pass(name)
	print(string.format("[HelloWorldTests] PASS %s", name))
end

local function fail(name, reason)
	print(string.format("[HelloWorldTests] FAIL %s: %s", name, reason))
end

if not GameMod.isModLoaded("HelloWorld") then
	fail("dependency", "HelloWorldMod is not loaded")
	return
end
pass("dependency")

-- Kick off a run as soon as this mod loads, so the whole suite runs
-- unattended from mod (re)load to log output.
-- luacheck: globals HelloWorldTests_startGameSession
HelloWorldTests_startGameSession = Tick.delay(function()
	print("[HelloWorldTests] Starting test suite")

	-- Force every extra mode off, since e.g. All Characters Mode replaces
	-- the level's exit with one staircase per remaining character, which
	-- would break the stairs/apple assertion below.
	for _, mode in pairs(ExtraMode.Type) do
		if mode ~= ExtraMode.Type.NONE then
			ExtraMode.setActive(mode, false)
		end
	end

	GameSession.start({
		mode = GameSession.Mode.SingleZone,
	})
end)
HelloWorldTests_startGameSession()

-- Pins the seed each level is actually generated with, which is what
-- CurrentLevel.getSeed() reports and what determines level layout.
event.levelGenerate.add("ForceFixedSeed", {}, function(ev)
	if ev.options then
		ev.options.seed = FIXED_SEED
	end
end)

event.levelLoad.add("AppleOnStairsCheck", { order = "extraEntities", sequence = 1 }, function()
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
		pass("appleSpawnsOnStairs")
	else
		fail("appleSpawnsOnStairs", string.format(
			"no Food1 entity at any of %d stairs marker(s)", #stairs))
	end
	print("[HelloWorldTests] Test suite completed")
end)
