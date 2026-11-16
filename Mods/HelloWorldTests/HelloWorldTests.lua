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

-- Deferred by one tick so that any other mod's own load-time
-- api.registerTest() call - triggered by this same reload, if this mod's
-- api.lua changed - has a chance to run first: a reload always finishes an
-- entire batch of scripts before the next tick, but does not guarantee this
-- entry script runs last within that batch.
-- luacheck: globals HelloWorldTests_start
HelloWorldTests_start = Tick.delay(api.start)
HelloWorldTests_start()
