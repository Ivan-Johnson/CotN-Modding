local Beatmap = require "necro.audio.Beatmap"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Music = require "necro.audio.Music"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local Tile = require "necro.game.tile.Tile"
local testsApi = require "TestFramework.api"

--[[
Scene setup for tests that watch enemies, shared by any mod's tests. Like
api.lua it never depends on a mod under test.
]]

local PLAYER_ID = 1

local function player()
	return Player.getPlayerEntity(PLAYER_ID)
end

-- Entities.despawn leaves an entity occupying its tile, so a later enemy
-- could never step there; Object.delete does the game's own cleanup.
local function deleteAll(entityIDs)
	for _, entityID in ipairs(entityIDs) do
		Object.delete(Entities.getEntityByID(entityID))
	end
end

local function isWall(entity)
	return entity.name:find("Wall", 1, true) ~= nil
end

-- Removes every enemy (except those named keepType, if given) and turns the square of tiles within radius of the
-- player into floor, so neither the random enemies nor the level's walls
-- skew a test. Entities attached to a wall (torches, spike traps) go with it.
local function openArena(radius, keepType)
	local doomed = {}
	for entity in Entities.entitiesWithComponents({ "ai" }) do
		if entity.name ~= keepType then
			table.insert(doomed, entity.id)
		end
	end
	deleteAll(doomed)

	local center = player().position
	for y = center.y - radius, center.y + radius do
		for x = center.x - radius, center.x + radius do
			local info = Tile.getInfo(x, y)
			if not (info and info.isFloor) then
				Tile.setType(x, y, "Floor")
			end
		end
	end

	doomed = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local position = entity.position
		if
			isWall(entity)
			and not entity.item
			and not entity.attachment
			and math.abs(position.x - center.x) <= radius
			and math.abs(position.y - center.y) <= radius
		then
			table.insert(doomed, entity.id)
		end
	end
	deleteAll(doomed)
end

-- Spawns at absolute tile coordinates. Spawned outside a turn, an entity would
-- stay invulnerable until the next turn, unlike the enemies a level starts with.
-- A Ghost spawned here stays frozen until the player's next move to a new tile.
local function spawn(typeName, x, y)
	local entity = Object.spawn(typeName, x, y)
	if entity.spawnInvincibility then
		entity.spawnInvincibility.active = false
	end
	return entity
end

local function health()
	return player().health.health
end

-- Fills the tiles (x, firstY) to (x, lastY) with tileType.
local function wallColumn(x, firstY, lastY, tileType)
	for y = firstY, lastY do
		Tile.setType(x, y, tileType or "StoneWall")
	end
end

local function tileName(x, y)
	local info = Tile.getInfo(x, y)
	return info and info.name or "nil"
end

local function whenOnLevel(mode, number, andThen)
	if CurrentLevel.isLoading() or CurrentLevel.getNumber() ~= number or CurrentLevel.getMode().id ~= mode then
		testsApi.afterTicks(10, function()
			whenOnLevel(mode, number, andThen)
		end)
		return
	end
	testsApi.afterTicks(100, andThen)
end

local function countOnce(counts, seen, name)
	if not seen[name] then
		seen[name] = true
		counts[name] = (counts[name] or 0) + 1
	end
end

--[[
Surveys the regular levels (floors 1 to 3) of one zone as Cadence, over
`runs` runs with different seeds, and calls andThen(census). The runs are
all-zones runs, or single-zone runs if singleZone is set (zone 1 only):
census.levels is the number of levels surveyed, and census.tiles and
census.entities map each tile and entity type name to the number of those
levels that hold it. Give the test a timeoutTicks of about 1500 per run. For
a small sample (api.smallSample) it surveys one run.
]]
local function zoneCensus(zone, runs, singleZone, andThen)
	if testsApi.smallSample() then
		runs = 1
	end
	local mode = singleZone and GameSession.Mode.SingleZone or GameSession.Mode.AllZones
	local census = { levels = 0, tiles = {}, entities = {} }
	local run, floor = 0, 3
	local function surveyLevel()
		local seen = {}
		for y = -80, 80 do
			for x = -80, 80 do
				local info = Tile.getInfo(x, y)
				if info and info.name then
					countOnce(census.tiles, seen, info.name)
				end
			end
		end
		for entity in Entities.entitiesWithComponents({ "position" }) do
			countOnce(census.entities, seen, entity.name)
		end
		census.levels = census.levels + 1
	end
	local nextLevel
	local function goToFloor()
		local number = singleZone and floor or 4 * (zone - 1) + floor
		if number ~= CurrentLevel.getNumber() then
			GameSession.goToLevel(number)
		end
		whenOnLevel(mode, number, function()
			surveyLevel()
			nextLevel()
		end)
	end
	nextLevel = function()
		floor = floor + 1
		if floor <= 3 then
			goToFloor()
			return
		end
		run = run + 1
		floor = 1
		if run > runs then
			testsApi.setSeedOverride(nil)
			andThen(census)
			return
		end
		-- Each run gets different levels, the same ones every time.
		local runSeed = 1000003 * run
		testsApi.setSeedOverride(function(options)
			return runSeed + (options.number or 0) * 7919
		end)
		GameSession.start({ mode = mode })
		testsApi.afterTicks(50, function()
			whenOnLevel(mode, 1, goToFloor)
		end)
	end
	Player.setCharacterType(PLAYER_ID, "Cadence")
	testsApi.afterTicks(100, nextLevel)
end

-- Asserts that each of names is a key of counts, such as a zoneCensus map.
-- Asserts nothing for a small sample (api.smallSample), which a rare name can
-- miss.
local function assertAllPresent(counts, names, what)
	if testsApi.smallSample() then
		return
	end
	local missing = {}
	for _, name in ipairs(names) do
		if not counts[name] then
			missing[#missing + 1] = name
		end
	end
	assert(#missing == 0, "no " .. what .. " " .. table.concat(missing, ", "))
end

-- A list of count copies of value, e.g. repeated("idle", 4).
local function repeated(value, count)
	local list = {}
	for index = 1, count do
		list[index] = value
	end
	return list
end

local function assertAt(entity, x, y, what)
	local position = entity.position
	assert(
		position.x == x and position.y == y,
		string.format("%s: expected %s at (%d,%d), got (%d,%d)", what, entity.name, x, y, position.x, position.y)
	)
end

-- Missed beats of the player, each recorded by a running timeline below.
local onMissedBeat = nil

event.objectMissedBeatAction.add("TestFrameworkMissedBeat", { order = "grooveChain", sequence = 1 }, function(ev)
	if onMissedBeat and ev.entity == player() then
		onMissedBeat()
	end
end)

--[[
Plays steps at fixed times around a beat, for timing finer than a beat (a
trap's fuse, the stairs' descent). It picks a beat B at least a second away;
each step is { t, action }, run at music time B + t: action is an api.play
name to send, or a function to call. Meanwhile it records, every tick, each
change of watch (a table of name = function returning a value) and each
missed beat, as { key, value, at } with at in seconds from B and key
"missedBeat" for a missed beat. It ends at B + seconds, or when the level
changes (recorded under key "level"): the music, and so its time, restarts
on a new level. Then it calls done(events, lastAt), where lastAt is the last
time seen on the starting level. Steps must be in time order.

The game judges an input against its beatmap, not the music time. The
beatmap skips a beat no one pressed for about 0.31 s after it, but at times
it falls a beat or two behind the music for a while, and an input then
counts for a beat long gone. So each input step first checks that the
beatmap has kept up; if not, before the first step the timeline starts
over at a later beat, and after it the test fails.
]]
local TIMELINE_ATTEMPTS = 5

local function timeline(steps, watch, seconds, done, attempt)
	attempt = attempt or 1
	testsApi.atBeat(-1, function(beat, interval)
		local events = {}
		local function record(key, value)
			events[#events + 1] = { key = key, value = value, at = Music.getMusicTime() - beat }
		end
		local last = {}
		for key, probe in pairs(watch) do
			last[key] = probe()
		end
		local level = CurrentLevel.getNumber()
		local lastAt = Music.getMusicTime() - beat
		local abandoned = false
		-- Kept up: the beatmap's next beat is less than 0.75 of a beat behind the
		-- music, well past the skip at about 0.31 s. A level about to end, as on
		-- the stairs, already has the next level's beatmap; that one is not
		-- checked.
		local beatmap = Beatmap.getPrimary()
		local function beatmapBehind()
			if Beatmap.getPrimary() ~= beatmap then
				return false
			end
			local behind = Music.getMusicTime() - beatmap:getNextBeatTime()
			return behind > 0.75 * interval and behind
		end
		local function runStep(index)
			local step = steps[index]
			if not step then
				return
			end
			testsApi.atMusicTime(beat + step[1], function()
				if abandoned then
					return
				end
				if type(step[2]) == "function" then
					step[2]()
				else
					local behind = beatmapBehind()
					if behind and index == 1 and attempt < TIMELINE_ATTEMPTS then
						print(string.format(
							"[TestFramework] timeline: the beatmap is %.3f s behind the music; starting over",
							behind
						))
						abandoned = true
						onMissedBeat = nil
						timeline(steps, watch, seconds, done, attempt + 1)
						return
					end
					assert(
						not behind,
						string.format("step %d: the beatmap is %.3f s behind the music", index, behind or 0)
					)
					testsApi.send(step[2])
				end
				runStep(index + 1)
			end)
		end
		runStep(1)
		onMissedBeat = function()
			record("missedBeat", true)
		end
		local function poll()
			if abandoned then
				return
			end
			if CurrentLevel.getNumber() ~= level then
				record("level", CurrentLevel.getNumber())
				onMissedBeat = nil
				done(events, lastAt)
				return
			end
			lastAt = Music.getMusicTime() - beat
			for key, probe in pairs(watch) do
				local value = probe()
				if value ~= last[key] then
					record(key, value)
					last[key] = value
				end
			end
			if lastAt < seconds then
				testsApi.afterTicks(1, poll)
			else
				onMissedBeat = nil
				done(events, lastAt)
			end
		end
		poll()
	end, 0.1)
end

-- The events of a timeline with the given key, in order.
local function eventsOf(events, key)
	local found = {}
	for _, item in ipairs(events) do
		if item.key == key then
			found[#found + 1] = item
		end
	end
	return found
end

--[[
Registers a no-beat test that plays actions on an open arena. Fields:
  name, actions (list of action names), checks ({[index] = function(state, resolved)},
  run after the action at that index settles);
  radius (default 10): passed to openArena;
  character (string?): the test's character, as in api.lua's test table;
  prepare (function?): runs after openArena and before setup, e.g. to spawn
    something or change the player;
  setup (function?): runs next; what it returns is passed to every check.
The test is tagged with the file that called scene, so a file selection keeps
it, not with this file.
]]
local function scene(spec)
	local checks = spec.checks or {}
	local file = testsApi.callerFile()
	testsApi.registerTest({
		name = spec.name,
		file = file,
		character = spec.character,
		noBeat = true,
		async = true,
		onLoad = function(_, finish)
			openArena(spec.radius or 10)
			if spec.prepare then
				spec.prepare()
			end
			local state = spec.setup and spec.setup() or {}
			testsApi.play(spec.actions, function(index, _, resolved)
				if checks[index] then
					checks[index](state, resolved)
				end
			end, finish)
		end,
	})
end

return {
	assertAllPresent = assertAllPresent,
	assertAt = assertAt,
	eventsOf = eventsOf,
	health = health,
	openArena = openArena,
	player = player,
	repeated = repeated,
	scene = scene,
	spawn = spawn,
	tileName = tileName,
	timeline = timeline,
	wallColumn = wallColumn,
	zoneCensus = zoneCensus,
}
