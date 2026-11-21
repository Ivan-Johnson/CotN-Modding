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
local Input = require "necro.client.Input"
local Json = require "AgentBridge.Json"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local RhythmMode = require "necro.game.data.modifier.RhythmMode"
local Turn = require "necro.cycles.Turn"

local CHUNK_SIZE = 4000
local MAX_STEPS = 200
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
	local mode = RhythmMode.getMode()
	for name, value in pairs(RhythmMode.Type) do
		if value == mode then
			return name
		end
	end
	return tostring(mode)
end

commands.state = {
	run = function()
		local player = requirePlayer()
		return {
			turnID = Turn.getCurrentTurnID(),
			level = CurrentLevel.getNumber(),
			rhythmMode = rhythmModeName(),
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

commands.convert = {
	run = function(args)
		local entity = requireEntity(args[1])
		Object.convertImmediately(entity, requireEntityType(args[2]))
		return summarizeEntity(entity)
	end,
}

commands.input = {
	run = function(args)
		local name = args[1]
		local action = DIRECTIONS[name] or SPECIALS[name]
		assert(action, "unknown input '" .. tostring(name) .. "'")
		queueInput(action, 1)
		return { queued = name }
	end,
}

commands.step = {
	run = function(args)
		local count = tonumber(args[1]) or 1
		assert(count >= 1 and count <= MAX_STEPS, "step count must be 1 to " .. MAX_STEPS)
		queueInput(Action.Special.IDLE, count)
		return { queued = count }
	end,
}

commands["new-run"] = {
	run = function(args)
		local character = args[1]
		if character then
			requireEntityType(character)
		end
		-- The ~1 s command latency leaves several beats between commands.
		ExtraMode.setActive(ExtraMode.Type.NO_BEAT, true)
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		if character then
			Player.setCharacterType(PLAYER_ID, character)
		end
		return { started = "SingleZone", character = character }
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
	local ok, result = pcall(command.handler.run, command.args)
	if ok then
		replyData(command.id, result)
	else
		reply(command.id, "ERROR", (tostring(result):gsub("%s+", " ")))
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
	else
		execute({ id = id, handler = handler, args = args })
	end
end

event.tick.add("AgentBridgePoll", { order = "invokeLater" }, function()
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


print("[AgentBridge] WARNING: dev-only mod; it runs commands from " .. COMMAND_FILE)
