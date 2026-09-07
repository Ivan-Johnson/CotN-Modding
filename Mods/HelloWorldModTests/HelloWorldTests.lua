-- Automated smoke tests for HelloWorldMod. This mod is never packaged for
-- players; it only exists to drive a run and assert on HelloWorldMod's
-- behavior, logging PASS/FAIL/SKIP lines that an external script can tail
-- from NecroDancer.log.
--
-- The dependency check, the deferred GameSession.start (with all Extra
-- Modes forced off), and the shared "extraEntities" event.levelLoad hook
-- have been confirmed live: enabling this mod alongside HelloWorldMod
-- produces "PASS dependency" and a "Starting Single Zone run" log line,
-- with no script errors, and the apple/stairs check runs against exactly
-- one stairs marker. It currently logs FAIL, matching HelloWorldMod's own
-- known bug (apples spawn at level start instead of the exit stairs).

local GameMod = require "necro.game.data.resource.GameMod"
local GameSession = require "necro.client.GameSession"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local Tick = require "necro.cycles.Tick"
local Entities = require "system.game.Entities"
local Map = require "necro.game.object.Map"
local Marker = require "necro.game.tile.Marker"

-- Tick.delay's docs require storing its returned wrapper in a global so the
-- delayed invocation survives mod reloads; declare it for luacheck since
-- that's a real Synchrony API requirement, not an accidental global.
-- luacheck: globals HelloWorldTests_startGameSession

-- Arbitrary fixed value; any constant integer here pins the run for
-- regression testing, since GameSession.SeedMode.MANUAL by itself only
-- disables re-randomization without specifying what to use instead.
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
-- unattended from mod (re)load to log output. Confirmed live: this starts a
-- "Single Zone" run without errors.
--
-- Per the API overview's load-time/run-time distinction, load-time script
-- code (i.e. this script's top-level scope) may not call anything that
-- fires an event -- which includes both ExtraMode.setActive and
-- GameSession.start. Calling them directly here throws "Cyclic dependency
-- involving 'system.events.Events'/'system.config.SettingsStorage' and
-- 'system.mod.ModLoader'" and crashes the whole script load.
--
-- Tried Tick.registerDelay(func, name) first per the deprecation warning,
-- both with and without a name argument: neither ever ran the callback
-- (confirmed live -- "PASS dependency" logs, then nothing further, even
-- after 60+ seconds). Tick.invokeLater ran the callback but crashed the
-- game the next time Menu.lua's eventHandlersChanged handler processed the
-- deferred-call queue (Tick.lua:210, "attempt to index local 'entry' (a
-- function value)"): invokeLater pushes a bare function into a queue that
-- other code expects to hold table entries. Tick.delay is the documented,
-- non-deprecated replacement and doesn't share that bug; per its docs, the
-- wrapper it returns must be stored in a global so delayed invocations
-- survive mod reloads.
HelloWorldTests_startGameSession = Tick.delay(function()
	-- Any Extra Mode left active from the lobby (e.g. All Characters Mode)
	-- changes level generation independently of the `mode` argument below:
	-- All Characters Mode replaces the level's exit with one staircase per
	-- remaining character, which broke the stairs/apple assertion further
	-- down. Force every extra mode off first so this test always runs a
	-- plain, single-staircase Single Zone level.
	for _, mode in pairs(ExtraMode.Type) do
		if mode ~= ExtraMode.Type.NONE then
			ExtraMode.setActive(mode, false)
		end
	end

	-- Seed reproducibility across the full run is still open;
	-- generatorOptions.seed only pins level 1's generation.
	GameSession.start({
		mode = GameSession.Mode.SingleZone,
		seedMode = GameSession.SeedMode.MANUAL,
		generatorOptions = { seed = FIXED_SEED },
	})
end)
HelloWorldTests_startGameSession()

-- Runs alongside HelloWorldMod's own "extraEntities" handler, which is
-- supposed to spawn apples on the exit stairs (see HelloWorldMod's own
-- TODO: it currently spawns them at the level start instead).
event.levelLoad.add("AppleOnStairsCheck", { order = "extraEntities" }, function()
	local stairs = Marker.lookUpAll(Marker.Type.STAIRS)
	local foundApple = false
	for _, pos in ipairs(stairs) do
		for _, entityID in ipairs(Map.getAll(pos[1], pos[2])) do
			if Entities.getEntityTypeName(entityID) == "Food1" then
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
end)
