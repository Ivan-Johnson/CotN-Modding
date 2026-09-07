-- Automated smoke tests for HelloWorldMod. This mod is never packaged for
-- players; it only exists to drive a run and assert on HelloWorldMod's
-- behavior, logging PASS/FAIL/SKIP lines that an external script can tail
-- from NecroDancer.log.
--
-- The dependency check, GameSession.start, and the shared "extraEntities"
-- event.levelLoad hook have been confirmed live: enabling this mod alongside
-- HelloWorldMod produces "PASS dependency", a "Starting Single Zone run" log
-- line, and the SKIP line below, with no script errors. The apple/stairs
-- assertion itself (marked TODO) is still unimplemented.

local GameMod = require "necro.game.data.resource.GameMod"
local GameSession = require "necro.client.GameSession"

local function pass(name)
	print(string.format("[HelloWorldTests] PASS %s", name))
end

local function fail(name, reason)
	print(string.format("[HelloWorldTests] FAIL %s: %s", name, reason))
end

local function skip(name, reason)
	print(string.format("[HelloWorldTests] SKIP %s: %s", name, reason))
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
-- TODO: `seedMode = MANUAL` alone did not make the run reproducible (the
-- logged seed was random each time); find and set whatever field actually
-- pins the seed before relying on this for regression testing.
GameSession.start({
	mode = GameSession.Mode.SingleZone,
	seedMode = GameSession.SeedMode.MANUAL,
})

-- Runs alongside HelloWorldMod's own "extraEntities" handler, which is
-- supposed to spawn apples on the exit stairs (see HelloWorldMod's own
-- TODO: it currently spawns them at the level start instead).
event.levelLoad.add("AppleOnStairsCheck", { order = "extraEntities" }, function()
	-- TODO: replace with a real assertion, e.g. querying the objects at the
	-- stairs marker position for a "Food1" entity, once the right lookup
	-- API has been confirmed in-game.
	skip("appleSpawnsOnStairs", "assertion not yet implemented")
end)
