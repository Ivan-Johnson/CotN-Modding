-- Lets an AI agent drive a live game; dev-only. See
-- Docs/Adr/0006-agent-bridge-uses-command-file-and-log.md and
-- AuthoredDocs/Src/live-game-control.md.
--
-- Commands arrive as one line in cmd.txt beside this script:
--   <id> <command> [args...]
-- Replies go to NecroDancer.log, the only output a mod has, as lines
--   [AgentBridge] <id> DATA <index>/<total> <base64 chunk of JSON>
--   [AgentBridge] <id> ERROR <message>
-- `agent-bridge` (a flake app) hides all of this.
local Action = require "necro.game.system.Action"
local Base64 = require "system.utils.serial.Base64"
local Components = require "necro.game.data.Components"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local FileIO = require "system.game.FileIO"
local GameSession = require "necro.client.GameSession"
local GrooveChain = require "necro.game.character.GrooveChain"
local Input = require "necro.client.Input"
local Json = require "AgentBridge.Json"
local Music = require "necro.audio.Music"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local RhythmMode = require "necro.game.data.modifier.RhythmMode"
local Tile = require "necro.game.tile.Tile"
local Turn = require "necro.cycles.Turn"

local CHUNK_SIZE = 4000
local MAX_STEPS = 200
local MAX_TILES = 400
local MAX_INPUTS = 50
local JOB_TIMEOUT_TICKS = 5000
local TILE_SCAN_RADIUS = 2
local ENTITY_RADIUS = 12
local SONG_END_WARNING_SECONDS = 30
local PLAYER_ID = 1

-- A mod's own directory is not exposed, but the location prefix of a Lua error
-- ("<Bundle>/AgentBridge/AgentBridge.lua:N: ...") names it.
local function findOwnDirectory()
	local _, message = pcall(function()
		error("x")
	end)
	return "mods/" .. assert(message:match("^(.*)/[^/]*:%d+: x$"))
end

local COMMAND_FILE = findOwnDirectory() .. "/cmd.txt"

local DIRECTIONS = {
	right = Action.Direction.RIGHT,
	up_right = Action.Direction.UP_RIGHT,
	up = Action.Direction.UP,
	up_left = Action.Direction.UP_LEFT,
	left = Action.Direction.LEFT,
	down_left = Action.Direction.DOWN_LEFT,
	down = Action.Direction.DOWN,
	down_right = Action.Direction.DOWN_RIGHT,
}

local SPECIALS = {
	idle = Action.Special.IDLE,
	item1 = Action.Special.ITEM_1,
	item2 = Action.Special.ITEM_2,
	bomb = Action.Special.BOMB,
	throw = Action.Special.THROW,
	spell1 = Action.Special.SPELL_1,
	spell2 = Action.Special.SPELL_2,
}

-- Local, so a reload resets them; `lastID` then adopts whatever command is
-- already in the file instead of running it a second time.
local started = false
local lastID
local songEndWarned = false
local lastMultiplier = 1
-- The input or step command in progress, if any; see `startJob`.
local job


local function reply(id, kind, payload)
	print(string.format("[AgentBridge] %s %s %s", id, kind, payload))
end

local function replyData(id, value)
	local encoded = Base64.encode(Json.encode(value))
	local total = math.max(1, math.ceil(#encoded / CHUNK_SIZE))
	for i = 1, total do
		reply(id, "DATA", string.format("%d/%d %s", i, total, encoded:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)))
	end
end

local function enumName(enum, value)
	for name, candidate in pairs(enum) do
		if candidate == value then
			return name
		end
	end
	return tostring(value)
end

-- Unlike replies, events are not tied to a command: one plain JSON line each,
-- which `agent-bridge` prints after the next command's reply.
local function emitEvent(kind, fields)
	fields.event = kind
	fields.turnID = Turn.getCurrentTurnID()
	fields.level = CurrentLevel.getNumber()
	print("[AgentBridge] EVENT " .. Json.encode(fields))
	if job and job.pending then
		job.events[#job.events + 1] = fields
	end
end

local function dumpEntity(entity, show)
	local defaults = Components.getComponentDefaults()
	local components = {}
	for _, name in ipairs(Entities.listComponentNames()) do
		local component = (show == "all" or show[name]) and entity[name]
		if component then
			local fields = {}
			for field in pairs(defaults[name] or {}) do
				fields[field] = component[field]
			end
			components[name] = fields
		end
	end
	return { id = entity.id, type = entity.name, components = components }
end

local function summarizeEntity(entity)
	local position = entity.position
	return { id = entity.id, type = entity.name, x = position and position.x, y = position and position.y }
end

local function parseShow(text)
	if text == "all" then
		return "all"
	end
	local show = {}
	for name in (text or ""):gmatch("[^,]+") do
		show[name] = true
	end
	return show
end

local function parseOptions(args)
	local options = {}
	for _, arg in ipairs(args) do
		local key, value = arg:match("^(%w+)=(.*)$")
		assert(key, "expected key=value, got '" .. arg .. "'")
		options[key] = value
	end
	return options
end

local function requirePlayer()
	return assert(Player.getPlayerEntity(PLAYER_ID), "no player entity: start a run with new-run")
end

local function requireEntity(idText)
	local id = assert(tonumber(idText), "expected an entity ID, got '" .. tostring(idText) .. "'")
	assert(Entities.entityExists(id), "no entity with ID " .. id)
	return Entities.getEntityByID(id)
end

local function requireEntityType(name)
	assert(name and Entities.isValidEntityType(name), "unknown entity type '" .. tostring(name) .. "'")
	return name
end

local function listInventory(player)
	local items = {}
	for item in Entities.entitiesWithComponents({ "item" }) do
		if item.item.holder == player.id then
			items[#items + 1] = { id = item.id, type = item.name, equipped = item.item.equipped }
		end
	end
	return items
end

local function queueInput(action, count)
	for _ = 1, count do
		Input.add(action, PLAYER_ID)
	end
end

-- Each command runs straight from the tick that read it; `run(args)` returns the
-- reply value.
local commands = {}

local function rhythmModeName()
	return enumName(RhythmMode.Type, RhythmMode.getMode())
end

commands.state = {
	run = function()
		local player = requirePlayer()
		return {
			turnID = Turn.getCurrentTurnID(),
			level = CurrentLevel.getNumber(),
			rhythmMode = rhythmModeName(),
			song = { time = Music.getMusicTime(), length = Music.getMusicLength(), endReached = Music.isSongEndReached() },
			player = dumpEntity(player, parseShow("position,health,character")),
			inventory = listInventory(player),
		}
	end,
}

commands.entities = {
	run = function(args)
		local options = parseOptions(args)
		local found = {}
		if options.id then
			found[1] = requireEntity(options.id)
		else
			for entity in Entities.entitiesWithComponents({ options.component or "position" }) do
				if not options.type or entity.name == options.type then
					found[#found + 1] = entity
				end
			end
		end
		local show = options.show and parseShow(options.show)
		local results = {}
		for i, entity in ipairs(found) do
			results[i] = show and dumpEntity(entity, show) or summarizeEntity(entity)
		end
		return { count = #results, entities = results }
	end,
}

local function describeTile(x, y)
	local info = Tile.getInfo(x, y)
	return {
		x = x,
		y = y,
		tile = info and info.name,
		solid = Tile.isSolid(x, y),
		wall = info and info.isWall or false,
		floor = info and info.isFloor or false,
		digResistance = info and info.digResistance,
	}
end

-- `tile X Y` describes one tile; `tile X1 Y1 X2 Y2` lists the rectangle row by
-- row, from X1 to X2 within each row. Tiles outside the level have no `tile`.
commands.tile = {
	run = function(args)
		local x1 = assert(tonumber(args[1]), "expected X")
		local y1 = assert(tonumber(args[2]), "expected Y")
		if not args[3] then
			return describeTile(x1, y1)
		end
		local x2 = assert(tonumber(args[3]), "expected X2")
		local y2 = assert(tonumber(args[4]), "expected Y2")
		local tiles = {}
		for y = math.min(y1, y2), math.max(y1, y2) do
			for x = math.min(x1, x2), math.max(x1, x2) do
				assert(#tiles < MAX_TILES, "range has more than " .. MAX_TILES .. " tiles")
				tiles[#tiles + 1] = describeTile(x, y)
			end
		end
		return { count = #tiles, tiles = tiles }
	end,
}

commands.spawn = {
	run = function(args)
		local typeName = requireEntityType(args[1])
		local x, y = tonumber(args[2]), tonumber(args[3])
		if not x or not y then
			local position = requirePlayer().position
			x, y = position.x + 1, position.y
		end
		local entity = Object.spawn(typeName, x, y)
		-- Spawned outside a turn, the entity would stay invulnerable until the
		-- next one, unlike the enemies a level starts with.
		if entity.spawnInvincibility then
			entity.spawnInvincibility.active = false
		end
		return summarizeEntity(entity)
	end,
}

-- Removes every enemy so a test sees only what it spawns. Enemies are the
-- entities with an `ai`; the list is built first because despawning while
-- iterating would disturb the iteration.
commands.clear = {
	run = function()
		local doomed = {}
		for entity in Entities.entitiesWithComponents({ "ai" }) do
			if entity.id ~= PLAYER_ID then
				doomed[#doomed + 1] = entity.id
			end
		end
		for _, id in ipairs(doomed) do
			Entities.despawn(id)
		end
		return { cleared = #doomed }
	end,
}

commands.convert = {
	run = function(args)
		local entity = requireEntity(args[1])
		Object.convertImmediately(entity, requireEntityType(args[2]))
		return summarizeEntity(entity)
	end,
}

local PENDING = {}

local function resolveAction(name)
	return assert(DIRECTIONS[name] or SPECIALS[name], "unknown input '" .. tostring(name) .. "'")
end

local function snapshotTiles(center)
	local snapshot = {}
	for y = center.y - TILE_SCAN_RADIUS, center.y + TILE_SCAN_RADIUS do
		for x = center.x - TILE_SCAN_RADIUS, center.x + TILE_SCAN_RADIUS do
			local info = Tile.getInfo(x, y)
			snapshot[#snapshot + 1] = { x = x, y = y, tile = info and info.name }
		end
	end
	return snapshot
end

local function changedTiles(before)
	local changed = {}
	for _, was in ipairs(before) do
		local info = Tile.getInfo(was.x, was.y)
		local now = info and info.name
		if now ~= was.tile then
			changed[#changed + 1] = { x = was.x, y = was.y, from = was.tile, to = now }
		end
	end
	return #changed > 0 and changed or nil
end

local function playerSummary()
	local player = requirePlayer()
	return {
		x = player.position.x,
		y = player.position.y,
		health = player.health and player.health.health,
		maxHealth = player.health and player.health.maxHealth,
	}
end

local function finishJob(extra)
	local finished = job
	job = nil
	local payload = extra or {}
	payload.results = finished.results
	payload.player = playerSummary()
	payload.turnID = Turn.getCurrentTurnID()
	payload.level = CurrentLevel.getNumber()
	replyData(finished.id, payload)
end

-- Positions of the world's entities, minus the player's own: inventory items
-- and the head ride along with the player, so they are not "others moving".
-- With a `center`, only entities within ENTITY_RADIUS of it.
local function snapshotEntities(center)
	local snapshot = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local position = entity.position
		local near = not center
			or (math.abs(position.x - center.x) <= ENTITY_RADIUS and math.abs(position.y - center.y) <= ENTITY_RADIUS)
		if near and entity.id ~= PLAYER_ID and not entity.item and not entity.attachment then
			snapshot[entity.id] = { type = entity.name, x = position.x, y = position.y }
		end
	end
	return snapshot
end

-- Entities that moved or vanished (died) during the action.
local function changedEntities(before)
	local after = snapshotEntities()
	local changed = {}
	for id, was in pairs(before) do
		local now = after[id]
		if not now then
			changed[#changed + 1] = { id = id, type = was.type, from = { x = was.x, y = was.y }, gone = true }
		elseif now.x ~= was.x or now.y ~= was.y then
			changed[#changed + 1] = {
				id = id,
				type = was.type,
				from = { x = was.x, y = was.y },
				to = { x = now.x, y = now.y },
			}
		end
	end
	table.sort(changed, function(a, b)
		return a.id < b.id
	end)
	return #changed > 0 and changed or nil
end

local function recordOutcome()
	local position = requirePlayer().position
	local from = job.from
	local outcome = {
		action = job.names[job.index],
		from = { x = from.x, y = from.y },
		to = { x = position.x, y = position.y },
		moved = position.x ~= from.x or position.y ~= from.y,
		tilesChanged = changedTiles(job.tiles),
		entitiesMoved = changedEntities(job.entities),
		events = #job.events > 0 and job.events or nil,
		timedOut = not job.resolved or nil,
	}
	if
		not job.onlyNoteworthy
		or outcome.moved
		or outcome.tilesChanged
		or outcome.entitiesMoved
		or outcome.events
		or outcome.timedOut
	then
		job.results[#job.results + 1] = outcome
	end
end

-- Runs from the tick: queues one action at a time and waits for the turn to
-- advance, so each outcome is its own action's. A turn that never advances,
-- such as one lost to a level change, ends the action after JOB_TIMEOUT_TICKS.
local function advanceJob()
	if job.pending then
		job.ticks = job.ticks + 1
		job.resolved = Turn.getCurrentTurnID() ~= job.turnBefore
		if not job.resolved and job.ticks < JOB_TIMEOUT_TICKS then
			return
		end
		recordOutcome()
		job.pending = false
	end
	if job.index >= #job.names then
		finishJob()
		return
	end
	local position = requirePlayer().position
	job.index = job.index + 1
	job.from = { x = position.x, y = position.y }
	job.tiles = snapshotTiles(position)
	job.entities = snapshotEntities(position)
	job.turnBefore = Turn.getCurrentTurnID()
	job.events = {}
	job.ticks = 0
	job.pending = true
	queueInput(resolveAction(job.names[job.index]), 1)
end

-- Replies only once every action has resolved, so the agent needs no
-- sleep-then-poll loop. `onlyNoteworthy` drops outcomes where nothing happened.
local function startJob(id, names, onlyNoteworthy)
	requirePlayer()
	job = { id = id, names = names, onlyNoteworthy = onlyNoteworthy, index = 0, results = {}, pending = false }
	return PENDING
end

commands.input = {
	run = function(args, id)
		assert(#args >= 1 and #args <= MAX_INPUTS, "give 1 to " .. MAX_INPUTS .. " inputs")
		for _, name in ipairs(args) do
			resolveAction(name)
		end
		return startJob(id, args, false)
	end,
}

commands.step = {
	run = function(args, id)
		local count = tonumber(args[1]) or 1
		assert(count >= 1 and count <= MAX_STEPS, "step count must be 1 to " .. MAX_STEPS)
		local names = {}
		for i = 1, count do
			names[i] = "idle"
		end
		return startJob(id, names, true)
	end,
}

commands["new-run"] = {
	run = function(args)
		local character, regular
		for _, arg in ipairs(args) do
			if arg == "rhythm=regular" then
				regular = true
			else
				assert(not arg:find("=", 1, true), "unknown option '" .. arg .. "'; the only one is rhythm=regular")
				character = arg
			end
		end
		if character then
			requireEntityType(character)
		end
		-- The ~1 s command latency leaves several beats between commands.
		ExtraMode.setActive(ExtraMode.Type.NO_BEAT, not regular)
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		if character then
			Player.setCharacterType(PLAYER_ID, character)
		end
		return { started = "SingleZone", character = character, rhythmMode = rhythmModeName() }
	end,
}

commands.level = {
	run = function(args)
		local number = assert(tonumber(args[1]), "expected a level number")
		GameSession.goToLevel(number)
		return { level = number }
	end,
}

local function execute(command)
	local ok, result = pcall(command.handler.run, command.args, command.id)
	if not ok then
		reply(command.id, "ERROR", (tostring(result):gsub("%s+", " ")))
	elseif result ~= PENDING then
		replyData(command.id, result)
	end
end

local function parseCommand(line)
	local words = {}
	for word in line:gmatch("%S+") do
		words[#words + 1] = word
	end
	local id, name = table.remove(words, 1), table.remove(words, 1)
	return id, name, words
end

local function receive(line)
	local id, name, args = parseCommand(line)
	if not id then
		return
	end
	local handler = commands[name]
	if not handler then
		reply(id, "ERROR", "unknown command '" .. tostring(name) .. "'")
	elseif Player.getCount() > 1 then
		reply(id, "ERROR", "refusing to act in a multiplayer session")
	elseif job then
		reply(id, "ERROR", "busy: the previous input or step has not finished")
	else
		execute({ id = id, handler = handler, args = args })
	end
end

event.tick.add("AgentBridgePoll", { order = "invokeLater" }, function()
	if job then
		local ok, err = pcall(advanceJob)
		if not ok then
			local failed = job
			job = nil
			reply(failed.id, "ERROR", (tostring(err):gsub("%s+", " ")))
		end
	end
	local text = FileIO.exists(COMMAND_FILE) and FileIO.readFileToString(COMMAND_FILE, 4096)
	local line = text and text:match("^[^\n]*")
	local id = line and line:match("^%S+")
	if not started then
		started = true
		lastID = id
		print("[AgentBridge] ready: accepts commands from " .. COMMAND_FILE)
	elseif id and id ~= lastID then
		lastID = id
		receive(line)
	end
end)


event.objectTakeDamage.add("AgentBridgeDamage", { order = "screenShake" }, function(ev)
	local entity = ev.entity
	if Player.isPlayerEntity(entity) then
		if ev.damage > 0 then
			emitEvent("damage_taken", {
				amount = ev.damage,
				source = ev.attacker and ev.attacker.name or ev.killerName,
				health = entity.health and entity.health.health,
			})
		end
	elseif ev.attacker and Player.isPlayerEntity(ev.attacker) then
		emitEvent("damage_dealt", {
			target = entity.name,
			targetID = entity.id,
			amount = ev.damage,
			survived = ev.survived,
		})
	end
end)

event.objectDeath.add("AgentBridgeDeath", { order = "postDeathVision" }, function(ev)
	local entity = ev.entity
	local killer = ev.killer or ev.attacker
	if Player.isPlayerEntity(entity) then
		emitEvent("player_died", { killer = killer and killer.name or ev.killerName })
	else
		emitEvent("killed", {
			target = entity.name,
			targetID = entity.id,
			by = killer and killer.name or ev.killerName,
		})
	end
end)

event.levelLoad.add("AgentBridgeLevelLoad", { order = "lobbyLevel" }, function()
	songEndWarned = false
	lastMultiplier = 1
	emitEvent("level_loaded", {})
end)

event.objectSongEnd.add("AgentBridgeSongEnd", { order = "spawnEntity" }, function(ev)
	if Player.isPlayerEntity(ev.entity) then
		emitEvent("song_ended", { nextLevel = CurrentLevel.getNumber() + 1 })
	end
end)

event.tick.add("AgentBridgeSongEndWarning", { order = "invokeLater" }, function()
	if songEndWarned or not Player.getPlayerEntity(PLAYER_ID) or RhythmMode.getMode() == RhythmMode.Type.NO_BEAT then
		return
	end
	local remaining = Music.getMusicLength() - Music.getMusicTime()
	if remaining > 0 and remaining <= SONG_END_WARNING_SECONDS then
		songEndWarned = true
		emitEvent("song_ending", { secondsLeft = math.floor(remaining) })
	end
end)

local MULTIPLIER_LOSS_CAUSES = {
	IDLE = "idling",
	FAIL = "a failed action",
	ACTION = "an invalid action",
	TRAPDOOR = "falling down a trapdoor",
	DAMAGE = "taking damage",
}

event.objectGrooveChain.add("AgentBridgeMultiplier", { order = "multiplier" }, function(ev)
	if not Player.isPlayerEntity(ev.entity) then
		return
	end
	if ev.type < 0 then
		if lastMultiplier > 1 then
			local cause = enumName(GrooveChain.Type, ev.type)
			emitEvent("multiplier_lost", {
				previous = lastMultiplier,
				cause = cause,
				because = MULTIPLIER_LOSS_CAUSES[cause],
			})
		end
		lastMultiplier = 1
	else
		lastMultiplier = ev.multiplier or GrooveChain.getCoinMultiplier(ev.entity)
	end
end)

print("[AgentBridge] WARNING: dev-only mod; it runs commands from " .. COMMAND_FILE)
