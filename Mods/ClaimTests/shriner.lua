local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Move = require "necro.game.system.Move"
local ShrineGeneration = require "necro.game.level.ShrineGeneration"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Every test plays Cadence on a level whose secret room is forced to be the
-- shriner's (TravelRune7). The fixed seed does not fix the level's secret
-- room: the run's random seed picks it, if any. So a test restarts the run
-- with forceShriner set. Positions are taken relative to the Shriner, who
-- stands at the back of the room: the shrines are the row two tiles in front
-- of him, and the rune out is two tiles in front of the shrines. "up" is
-- toward negative y, so "in front" is +y.
--
-- The level-generation options can also name a room, so both are forced.

local forceShriner = false
event.levelSequenceUpdate.add("ClaimTestsShrinerRoom", { order = "secretRooms", sequence = 1000 }, function(ev)
	if not forceShriner then
		return
	end
	for _, level in ipairs(ev.sequence) do
		if level.type == "Necro" then
			level.secretRoom = "TravelRune7"
		end
	end
end)
event.levelGenerate.add("ClaimTestsShrinerRoomOptions", { sequence = -999 }, function(ev)
	if forceShriner and ev.options and ev.options.type == "Necro" then
		ev.options.secretRoom = "TravelRune7"
	end
end)
local loads = 0
event.levelLoad.add("ClaimTestsShrinerLoads", { order = "activationRange", sequence = 1000 }, function()
	loads = loads + 1
end)

local player = fixtures.player
local health = fixtures.health

-- The shrines the shriner's room can hold in a single-zone run.
local POOL = {
	ShrineOfBlood = true,
	ShrineOfBoss = true,
	ShrineOfDarkness = true,
	ShrineOfGlass = true,
	ShrineOfPeace = true,
	ShrineOfRisk = true,
	ShrineOfSpace = true,
	ShrineOfUncertainty = true,
	ShrineOfWar = true,
}

local function named(name)
	local found = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name == name then
			table.insert(found, entity)
		end
	end
	return found
end

local function shriner()
	return named("Shriner")[1]
end

-- Restarts the run with the shriner's room forced, then calls andThen(npc)
-- once the new level has loaded and settled.
local function withShriner(andThen)
	forceShriner = true
	-- Counted from the restart, not from onLoad: the test level's own load
	-- reaches the counter after onLoad runs.
	local before
	local function wait()
		if loads == before or CurrentLevel.isLoading() then
			testsApi.afterTicks(10, wait)
			return
		end
		forceShriner = false
		testsApi.afterTicks(300, function()
			andThen(assert(shriner(), "the level has the shriner's room"))
		end)
	end
	testsApi.afterTicks(10, function()
		before = loads
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		testsApi.afterTicks(50, wait)
	end)
end

-- The room's shrines, left to right.
local function roomShrines(npc)
	local found = {}
	for entity in Entities.entitiesWithComponents({ "shrine" }) do
		local dx = entity.position.x - npc.x
		if entity.position.y == npc.y + 2 and math.abs(dx) <= 1 then
			table.insert(found, entity)
		end
	end
	table.sort(found, function(a, b)
		return a.position.x < b.position.x
	end)
	return found
end

-- The dragons' names, sorted; with a room position, only those in the room.
local function dragons(room)
	local names = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local position = entity.position
		local inRoom = not room
			or (math.abs(position.x - room.x) <= 2 and position.y >= room.y - 2 and position.y <= room.y + 5)
		if entity.name:find("^Dragon") and inRoom then
			table.insert(names, entity.name)
		end
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function gold()
	return player().goldCounter.amount
end

local function goTo(x, y)
	Move.absolute(player(), x, y, Move.Type.TELEPORT)
	fixtures.assertAt(player(), x, y, "teleport")
end

-- Registers a no-beat test that finds the room, gives the player `spec.gold`
-- gold, stands them at (Shriner + spec.at), and plays spec.actions; checks[i]
-- runs after action i with the state that spec.setup returned.
local function roomScene(name, spec)
	testsApi.registerTest({
		name = name,
		noBeat = true,
		async = true,
		zone = spec.zone,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withShriner(function(npc)
				assert(player().name == "Cadence", "expected to play Cadence, got " .. player().name)
				local state = { x = npc.position.x, y = npc.position.y }
				state.shrines = roomShrines(state)
				assert(#state.shrines == 3, "three shrines in front of the Shriner")
				player().goldCounter.amount = spec.gold or 0
				goTo(state.x + spec.at[1], state.y + spec.at[2])
				testsApi.play(spec.actions, function(index)
					if spec.checks[index] then
						spec.checks[index](state)
					end
				end, finish)
			end)
		end,
	})
end

-- The game's own shrine choice for the shriner, run until it runs out of
-- shrines it has not yet given.
testsApi.registerTest({
	name = "shrinerPool",
	onLoad = function()
		local seen = {}
		local count = 0
		for _ = 1, 40 do
			local typeName = ShrineGeneration.choice({ shriner = true, seenCounts = seen, depletionLimit = 1 })
			if not typeName then
				break
			end
			assert(POOL[typeName], "unexpected shriner shrine " .. typeName)
			seen[typeName] = 1
			count = count + 1
		end
		assert(count == 9, "nine shrines in the pool, got " .. count)
	end,
})

-- The Shriner at the back, three different shrines of the pool in a row two
-- tiles in front of him, the rune out two tiles in front of the middle one.
testsApi.registerTest({
	name = "shrinerRoomLayout",
	async = true,
	timeoutTicks = 30000,
	onLoad = function(_, finish)
		withShriner(function(npc)
			local x, y = npc.position.x, npc.position.y
			local shrines = roomShrines({ x = x, y = y })
			assert(#shrines == 3, "three shrines, got " .. #shrines)
			local kinds = {}
			for index, shrine in ipairs(shrines) do
				assert(shrine.position.x == x + index - 2, "the shrines stand side by side")
				assert(POOL[shrine.name], "unexpected shrine " .. shrine.name)
				assert(not kinds[shrine.name], "two of " .. shrine.name)
				kinds[shrine.name] = true
			end
			local runes = named("TravelRune7")
			local inner = false
			for _, rune in ipairs(runes) do
				inner = inner or (rune.position.x == x and rune.position.y == y + 4)
			end
			assert(inner, "the rune out is two tiles in front of the shrines")
			finish()
		end)
	end,
})

-- Each shrine costs 50 gold: walking into one pays and uses it, and the
-- other two vanish. The same price on the first floor of every zone.
for zone = 1, 5 do
	roomScene("shrinerShrineCosts50Zone" .. zone, {
		zone = zone,
		gold = 500,
		at = { 0, 3 },
		actions = { "up" },
		checks = {
			function(state)
				assert(gold() == 450, "paid 50, have " .. gold())
				assert(state.shrines[2].shrine.active, "the middle shrine was used")
				assert(#roomShrines(state) == 1, "the other two shrines vanished")
			end,
		},
	})
end

-- With 49 gold, walking into a shrine does nothing; 50 is enough.
roomScene("shrinerShrineNeedsFullPrice", {
	gold = 49,
	at = { 0, 3 },
	actions = { "up", "idle", "up" },
	checks = {
		function(state)
			assert(gold() == 49, "kept the gold")
			assert(not state.shrines[2].shrine.active, "the shrine was not used")
			assert(#roomShrines(state) == 3, "all three shrines stay")
			fixtures.assertAt(player(), state.x, state.y + 3, "stayed in front of the shrine")
			player().goldCounter.amount = 50
		end,
		nil,
		function(state)
			assert(gold() == 0, "paid exactly 50")
			assert(state.shrines[2].shrine.active, "the shrine was used")
		end,
	},
})

-- The weapon cannot hurt the Shriner: attacking him does nothing.
roomScene("shrinerWeaponDoesNothing", {
	gold = 500,
	at = { 0, 1 },
	actions = { "up", "up", "up", "idle", "idle" },
	checks = {
		[5] = function(state)
			assert(health() == player().health.maxHealth, "the Shriner never hit back")
			assert(shriner(), "the Shriner is still there")
			fixtures.assertAt(shriner(), state.x, state.y, "the Shriner did not move")
			assert(dragons() == "", "no fight started")
			assert(gold() == 500, "no gold taken")
			assert(#roomShrines(state) == 3, "the shrines stay")
		end,
	},
})

-- A bomb kills the Shriner and starts a fight with three dragons; the
-- shrines are free from then on, still one of them only. The bomb goes off
-- beside him, out of reach of the shrine row.
roomScene("shrinerBombStartsDragonFight", {
	gold = 0,
	at = { -1, 0 },
	actions = { "bomb", "left", "down", "down", "right", "idle" },
	checks = {
		[4] = function(state)
			assert(shriner() == nil, "the bomb killed the Shriner")
			assert(dragons(state) == "Dragon,Dragon2,Dragon3", "the dragons in the room: " .. dragons(state))
			assert(#roomShrines(state) == 3, "the blast missed the shrines")
		end,
		[5] = function(state)
			assert(state.shrines[1].shrine.active, "the left shrine was used for free")
			assert(gold() == 0, "no gold needed")
			assert(#roomShrines(state) == 1, "the other two shrines vanished")
		end,
	},
})

-- A bomb dropped between the Shriner and the shrines destroys them too.
roomScene("shrinerBombInFrontDestroysShrines", {
	gold = 0,
	at = { 0, 1 },
	actions = { "bomb", "left", "left", "down", "idle" },
	checks = {
		[4] = function(state)
			assert(shriner() == nil, "the bomb killed the Shriner")
			assert(#roomShrines(state) == 0, "the blast destroyed the shrines")
		end,
	},
})

-- Played to the beat. The rune out takes you back to the level, but not while
-- the dragons live.
local function runeTest(name, fight)
	testsApi.registerTest({
		name = name,
		async = true,
		timeoutTicks = 60000,
		onLoad = function(_, finish)
			withShriner(function(npc)
				local x, y = npc.position.x, npc.position.y
				local function stepOntoRune()
					goTo(x, y + 3)
					testsApi.afterTicks(300, function()
						testsApi.play({ "down" }, nil, function()
							testsApi.afterTicks(1500, function()
								local position = player().position
								local inRoom = math.abs(position.x - x) <= 2 and position.y >= y - 2 and position.y <= y + 5
								if fight then
									assert(inRoom, string.format("left the room during the fight, to (%d,%d)", position.x, position.y))
									fixtures.assertAt(player(), x, y + 4, "stayed on the rune")
								else
									assert(not inRoom, "the rune took the player out of the room")
								end
								finish()
							end)
						end)
					end)
				end
				if not fight then
					stepOntoRune()
					return
				end
				goTo(x - 1, y)
				testsApi.afterTicks(300, function()
					testsApi.play({ "bomb" }, nil, function()
						goTo(x, y + 3)
						-- The blast comes a few beats later, which the
						-- restarted session plays at normal speed: 1700 to
						-- 2600 ticks over 20 runs.
						local waited = 0
						local function poll()
							waited = waited + 100
							local started = dragons() == "Dragon,Dragon2,Dragon3"
							if not started and waited < 10000 then
								testsApi.afterTicks(100, poll)
								return
							end
							assert(started, "the fight started: " .. dragons())
							stepOntoRune()
						end
						testsApi.afterTicks(100, poll)
					end)
				end)
			end)
		end,
	})
end
runeTest("shrinerRuneLeaves", false)
runeTest("shrinerRuneHeldDuringFight", true)
