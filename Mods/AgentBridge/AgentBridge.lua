-- Lets an AI agent drive a live game; dev-only. See
-- Docs/Adr/0006-agent-bridge-uses-command-file-and-log.md and
-- AuthoredDocs/Src/synchrony-game-control.md.
--
-- Commands arrive as one line in cmd.txt beside this script:
--   <id> <command> [args...]
-- Replies go to NecroDancer.log, the only output a mod has, as lines
--   [AgentBridge] <id> DATA <index>/<total> <base64 chunk of JSON>
--   [AgentBridge] <id> ERROR <message>
-- `agent-bridge` (a flake app) hides all of this.
local Action = require "necro.game.system.Action"
local Base64 = require "system.utils.serial.Base64"
local ClientActionBuffer = require "necro.client.ClientActionBuffer"
local Components = require "necro.game.data.Components"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local ExtraMode = require "necro.game.data.modifier.ExtraMode"
local FileIO = require "system.game.FileIO"
local GameSession = require "necro.client.GameSession"
local GrooveChain = require "necro.game.character.GrooveChain"
local Input = require "necro.client.Input"
local Json = require "AgentBridge.Json"
local Move = require "necro.game.system.Move"
local Marker = require "necro.game.tile.Marker"
local Music = require "necro.audio.Music"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local Rollback = require "necro.client.Rollback"
local RunSummary = require "necro.client.RunSummary"
local Route = require "AgentBridge.Route"
local RhythmMode = require "necro.game.data.modifier.RhythmMode"
local Tile = require "necro.game.tile.Tile"
local Turn = require "necro.cycles.Turn"

local CHUNK_SIZE = 4000
local MAX_STEPS = 200
local MAX_TILES = 400
local MAX_INPUTS = 50
-- The basic shovel digs dirt walls (resistance 1) but not stone (2) or shop walls (4).
local DIG_STRENGTH = 1
local JOB_TIMEOUT_TICKS = 5000
-- Ticks to wait after a turn advances before the next action. Queuing the next
-- one right away made enemies skip a move about every 24 beats (measured with
-- Slime3, which moves every beat); 10 ticks still skipped, 25 did not.
local SETTLE_TICKS = 30
local TILE_SCAN_RADIUS = 2
local ENTITY_RADIUS = 12
local MAX_ARENA_RADIUS = 10
local MAX_REPEATS = 100
local ARENA_FLOOR = "Floor"
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
-- The seed `new-run seed=N` asked for; every level generated until the next
-- `new-run` uses it.
local pendingSeed


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

-- `show=@name` expands to a group of components; names an entity lacks are
-- skipped, so one preset covers every enemy type.
local SHOW_PRESETS = {
	-- What decides how an enemy moves and attacks.
	ai = {
		"position", "health", "facingDirection", "hasMoved",
		"ai", "aiBasicSeek", "aiPattern", "aiMoveOnFallbackCollision", "aiTeamCollision",
		"activationRange", "aggro", "beatDelay", "beatCounter",
		"random", "randomInitialFacingDirection", "turnOnMoveFail",
		"stasis", "stasisAI", "stasisOnApproach",
		"charge", "chargeStartOnDirection",
		"grab", "grabAI", "grabIncreaseHealth",
		"innateAttack",
	},
}

local function parseShow(text)
	if text == "all" then
		return "all"
	end
	local show = {}
	for name in (text or ""):gmatch("[^,]+") do
		local presetName = name:match("^@(.+)$")
		if presetName then
			local preset = assert(SHOW_PRESETS[presetName], "unknown preset '@" .. presetName .. "'")
			for _, component in ipairs(preset) do
				show[component] = true
			end
		else
			show[name] = true
		end
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

-- The post-game screen swallows every action, so inputs time out with the
-- turn stuck. Reports the summary that is up, or nil.
local function runSummaryScreen()
	local summary = RunSummary.getActiveSummary()
	if summary then
		return { victory = summary.victory, level = summary.level, turnID = summary.turnID }
	end
end

commands.state = {
	run = function()
		local runSummary = runSummaryScreen()
		local player = Player.getPlayerEntity(PLAYER_ID)
		if not player and runSummary then
			return { runSummary = runSummary }
		end
		player = requirePlayer()
		local result = {
			runSummary = runSummary,
			turnID = Turn.getCurrentTurnID(),
			level = CurrentLevel.getNumber(),
			rhythmMode = rhythmModeName(),
			song = { time = Music.getMusicTime(), length = Music.getMusicLength(), endReached = Music.isSongEndReached() },
			player = dumpEntity(player, parseShow("position,health,character,grooveChain,goldCounter")),
			inventory = listInventory(player),
		}
		for name, direction in pairs(DIRECTIONS) do
			if player.facingDirection and player.facingDirection.direction == direction then
				result.facing = name
			end
		end
		return result
	end,
}

-- Items the player holds and wall decorations (torches): the entities that
-- bury the ones an agent asks about.
local function isHeld(entity)
	local holder = entity.item and entity.item.holder
	return holder and holder ~= 0 and Entities.entityExists(holder)
end

local function isBackgroundEntity(entity)
	return isHeld(entity) or entity.name:find("Wall") ~= nil
end

local function parseTypeSet(text)
	local set = {}
	for name in (text or ""):gmatch("[^,]+") do
		set[name] = true
	end
	return set
end

commands.entities = {
	run = function(args)
		local options = parseOptions(args)
		local near = options.near and tonumber(options.near)
		assert(not options.near or (near and near >= 0), "near must be a number of tiles")
		local exclude = parseTypeSet(options.exclude)
		local showBackground = options.all == "true" or options.type or options.component or options.id
		local center = near and requirePlayer().position
		local found = {}
		local hidden = 0
		local function consider(entity)
			local position = entity.position
			if exclude[entity.name] then
				return
			end
			if near and not (position
					and math.abs(position.x - center.x) <= near
					and math.abs(position.y - center.y) <= near) then
				return
			end
			if not showBackground and isBackgroundEntity(entity) then
				hidden = hidden + 1
				return
			end
			found[#found + 1] = entity
		end
		if options.id then
			consider(requireEntity(options.id))
		else
			for entity in Entities.entitiesWithComponents({ options.component or "position" }) do
				if not options.type or entity.name == options.type then
					consider(entity)
				end
			end
		end
		local show = options.show and parseShow(options.show)
		local results = {}
		for i, entity in ipairs(found) do
			results[i] = summarizeEntity(entity)
			if show then
				results[i].components = dumpEntity(entity, show).components
			end
		end
		return { count = #results, hidden = hidden, entities = results }
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

local MAX_MAP_RADIUS = 20
local DEFAULT_MAP_RADIUS = 8
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local MAP_WALL = "#"
local MAP_FLOOR = "."
local MAP_STAIRS = ">"
local MAP_PLAYER = "@"

-- Common types keep one glyph for every call and level; lower case marks a
-- variant of the upper-case type.
local MAP_GLYPHS = {
	Slime = "g",
	Slime2 = "b",
	Slime3 = "y",
	Skeleton = "S",
	Skeleton2 = "s",
	Skeleton3 = "K",
	Zombie = "Z",
	Bat = "V",
	Bat2 = "v",
	Monkey = "M",
	Monkey2 = "m",
	Ghost = "O",
	Armadillo = "D",
	Shopkeeper = "$",
	Crate = "X",
	ChestBlack = "C",
	ChestRed = "R",
	ChestPurple = "P",
	ChestLocked = "L",
}

-- Glyphs given to types outside MAP_GLYPHS, kept until the mod reloads.
local assignedGlyphs = {}
local takenGlyphs = { [MAP_PLAYER] = true, [MAP_STAIRS] = true, [MAP_WALL] = true, [MAP_FLOOR] = true }
for _, glyph in pairs(MAP_GLYPHS) do
	takenGlyphs[glyph] = true
end

-- The first unused letter of the type's name, uppercase, so legends read
-- naturally; then any unused letter or digit. Falls back to "?".
local function glyphFor(typeName)
	local glyph = MAP_GLYPHS[typeName] or assignedGlyphs[typeName]
	if glyph then
		return glyph
	end
	glyph = "?"
	for letter in (typeName:upper() .. ALPHABET):gmatch("%w") do
		if not takenGlyphs[letter] then
			glyph = letter
			break
		end
	end
	if glyph ~= "?" then
		assignedGlyphs[typeName] = glyph
		takenGlyphs[glyph] = true
	end
	return glyph
end

-- `map [N]` draws the tiles within N of the player (default 8, up to 20) as
-- text: `#` solid, `.` floor, `>` stairs, `@` the player, a fixed glyph for each
-- other entity type (see `legend`), and a space beyond the level's edge. Items
-- in the player's inventory, wall decorations and anything on the player's own
-- tile are left out.
commands.map = {
	run = function(args)
		local radius = args[1] and tonumber(args[1]) or DEFAULT_MAP_RADIUS
		assert(radius and radius >= 1 and radius <= MAX_MAP_RADIUS and radius % 1 == 0,
			"radius must be a whole number from 1 to " .. MAX_MAP_RADIUS)
		local player = requirePlayer()
		local px, py = player.position.x, player.position.y
		local cells = {}
		for y = py - radius, py + radius do
			for x = px - radius, px + radius do
				local info = Tile.getInfo(x, y)
				local symbol = " "
				if info and info.name then
					symbol = Tile.isSolid(x, y) and MAP_WALL or MAP_FLOOR
				end
				cells[y * 65536 + x] = symbol
			end
		end
		local allStairs = Marker.lookUpAll(Marker.Type.STAIRS)
		for _, stairs in ipairs(allStairs) do
			local key = stairs[2] * 65536 + stairs[1]
			if cells[key] then
				cells[key] = MAP_STAIRS
			end
		end
		local seen = {}
		local legend = {}
		for entity in Entities.entitiesWithComponents({ "position" }) do
			local pos = entity.position
			if
				entity.id ~= player.id
				and not (pos.x == px and pos.y == py)
				and not isBackgroundEntity(entity)
				and math.abs(pos.x - px) <= radius
				and math.abs(pos.y - py) <= radius
			then
				local symbol = glyphFor(entity.name)
				if not seen[entity.name] then
					seen[entity.name] = true
					legend[#legend + 1] = { symbol = symbol, type = entity.name }
				end
				if cells[pos.y * 65536 + pos.x] ~= " " then
					cells[pos.y * 65536 + pos.x] = symbol
				end
			end
		end
		cells[py * 65536 + px] = MAP_PLAYER
		local rows = {}
		for y = py - radius, py + radius do
			local row = {}
			for x = px - radius, px + radius do
				row[#row + 1] = cells[y * 65536 + x]
			end
			rows[#rows + 1] = table.concat(row)
		end
		return {
			x = px,
			y = py,
			x0 = px - radius,
			y0 = py - radius,
			radius = radius,
			rows = rows,
			legend = legend,
			stairs = allStairs,
		}
	end,
}

-- Costs in actions: a floor tile 1; a dirt wall 2 (dig, then move); a door 2
-- (open, then move); an enemy or a crate 3, since the first action attacks it;
-- other traps and floor items 100, so a route crosses one only when no way
-- around exists; the route lists each one it crosses. Trapdoors and
-- shopkeepers are never entered.
local ENEMY_COST = 3
local HAZARD_COST = 100

local ROUTE_ACTIONS = { ["0,-1"] = "up", ["0,1"] = "down", ["-1,0"] = "left", ["1,0"] = "right" }

-- What stands on each tile that changes the cost of entering it.
local function routeObstacles(player)
	local obstacles = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local pos = entity.position
		local at = pos.y * 65536 + pos.x
		local kind
		if entity.id == player.id or entity.attachment or isHeld(entity) then
			kind = nil
		elseif entity.trapDescend or entity.name:find("^Shopkeeper") then
			kind = "blocked"
		elseif entity.ai or entity.health then
			kind = "enemy"
		elseif entity.trap or entity.item then
			kind = "hazard"
		end
		local previous = obstacles[at]
		if kind == "blocked" or (kind and not previous) then
			obstacles[at] = { kind = kind, entity = entity }
		end
	end
	return obstacles
end

-- `route [stairs|X Y] [dig=true]` finds the cheapest orthogonal route from the
-- player to the stairs (the default) or to X Y, and returns the actions that
-- walk it, at most MAX_INPUTS; `partial` says it was cut short. It avoids
-- traps and floor items unless there is no other way.
commands.route = {
	run = function(args)
		local player = requirePlayer()
		local dig = false
		local target = {}
		for _, arg in ipairs(args) do
			if arg == "dig=true" then
				dig = true
			elseif arg ~= "stairs" then
				target[#target + 1] = assert(tonumber(arg), "expected stairs, X Y or dig=true, got '" .. arg .. "'")
			end
		end
		assert(#target == 0 or #target == 2, "give both X and Y, or neither for the stairs")
		local goals = {}
		if #target == 2 then
			goals[1] = { x = target[1], y = target[2] }
		else
			for _, stairs in ipairs(Marker.lookUpAll(Marker.Type.STAIRS)) do
				goals[#goals + 1] = { x = stairs[1], y = stairs[2] }
			end
			assert(#goals > 0, "this level has no stairs")
		end
		local isGoal = {}
		for _, goal in ipairs(goals) do
			isGoal[goal.y * 65536 + goal.x] = true
		end
		local obstacles = routeObstacles(player)
		local function enterCost(x, y)
			local info = Tile.getInfo(x, y)
			if not (info and info.name) then
				return nil
			end
			local at = y * 65536 + x
			local cost = 1
			if Tile.isSolid(x, y) then
				local resistance = info.digResistance
				if resistance and resistance < 0 then
					cost = 2
				elseif dig and resistance and resistance > 0 and resistance <= DIG_STRENGTH then
					cost = 2
				else
					return nil
				end
			end
			local obstacle = obstacles[at]
			if obstacle and not isGoal[at] then
				if obstacle.kind == "blocked" then
					return nil
				end
				cost = cost + (obstacle.kind == "enemy" and ENEMY_COST - 1 or HAZARD_COST - 1)
			end
			return cost
		end
		local position = player.position
		local found = Route.find(enterCost, { x = position.x, y = position.y }, goals)
		if not found then
			local where = #target == 2 and string.format("(%d,%d)", target[1], target[2]) or "the stairs"
			error("no path to " .. where .. (dig and " even with dig=true" or "; try dig=true"), 0)
		end
		local actions = {}
		local digs = 0
		local enemies = {}
		local hazards = {}
		local partial = false
		local previous = { x = position.x, y = position.y }
		for _, tile in ipairs(found.tiles) do
			local name = ROUTE_ACTIONS[(tile.x - previous.x) .. "," .. (tile.y - previous.y)]
			local info = Tile.getInfo(tile.x, tile.y)
			local solid = Tile.isSolid(tile.x, tile.y)
			local count = solid and 2 or 1
			if #actions + count > MAX_INPUTS then
				partial = true
				break
			end
			for _ = 1, count do
				actions[#actions + 1] = name
			end
			if solid and info.digResistance > 0 then
				digs = digs + 1
			end
			local obstacle = obstacles[tile.y * 65536 + tile.x]
			local entity = obstacle and obstacle.entity
			if obstacle and obstacle.kind == "enemy" then
				enemies[#enemies + 1] = { id = entity.id, type = entity.name, x = tile.x, y = tile.y }
			elseif obstacle and obstacle.kind == "hazard" then
				hazards[#hazards + 1] = { id = entity.id, type = entity.name, x = tile.x, y = tile.y }
			end
			previous = tile
		end
		return {
			target = { x = found.goal.x, y = found.goal.y },
			actions = actions,
			digs = digs,
			enemies = enemies,
			hazards = hazards,
			partial = partial,
		}
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
		local tile = describeTile(x, y)
		if (tile.solid or not tile.tile) and args[4] ~= "force" then
			error(string.format(
				"(%d,%d) is %s; add `force` (`force=true` for scenario) to spawn there anyway",
				x, y, tile.tile and (tile.tile .. ", a solid tile") or "outside the level"
			), 0)
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
-- `Entities.despawn` leaves the entity occupying its tile, so a later enemy
-- cannot step there; `Object.delete` does the game's own cleanup.
local function deleteEntities(ids)
	for _, id in ipairs(ids) do
		Object.delete(Entities.getEntityByID(id))
	end
end

local function clearEnemies()
	local doomed = {}
	for entity in Entities.entitiesWithComponents({ "ai" }) do
		if entity.id ~= PLAYER_ID then
			doomed[#doomed + 1] = entity.id
		end
	end
	deleteEntities(doomed)
	return #doomed
end

-- Turns the square of tiles within `radius` of the player into floor, so
-- walls from the random level cannot skew a test. Whatever is attached to a
-- wall that goes (a wall torch, a spike trap) is despawned with it; walls
-- beyond the square stay as the arena's boundary.
local function carveArena(radius)
	local center = requirePlayer().position
	local carved = 0
	for y = center.y - radius, center.y + radius do
		for x = center.x - radius, center.x + radius do
			local info = Tile.getInfo(x, y)
			if not (info and info.isFloor) then
				Tile.setType(x, y, ARENA_FLOOR)
				carved = carved + 1
			end
		end
	end
	local doomed = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		local position = entity.position
		if
			entity.id ~= PLAYER_ID
			and not entity.item
			and not entity.attachment
			and not entity.ai
			and math.abs(position.x - center.x) <= radius
			and math.abs(position.y - center.y) <= radius
			and entity.name:find("Wall", 1, true)
		then
			doomed[#doomed + 1] = entity.id
		end
	end
	deleteEntities(doomed)
	return carved
end

local function parseArena(text)
	if not text then
		return nil
	end
	local radius = tonumber(text)
	assert(
		radius and radius >= 1 and radius <= MAX_ARENA_RADIUS and radius % 1 == 0,
		"arena must be a whole number from 1 to " .. MAX_ARENA_RADIUS
	)
	return radius
end

-- `clear` removes the enemies; `clear arena=N` also floors the square within N
-- tiles of the player.
commands.clear = {
	run = function(args)
		local options = parseOptions(args)
		local radius = parseArena(options.arena)
		local result = { cleared = clearEnemies() }
		if radius then
			result.arenaTilesCarved = carveArena(radius)
		end
		return result
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

local function validActionNames()
	local names = {}
	for name in pairs(DIRECTIONS) do
		names[#names + 1] = name
	end
	for name in pairs(SPECIALS) do
		names[#names + 1] = name
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function resolveAction(name)
	return assert(
		DIRECTIONS[name] or SPECIALS[name],
		"unknown input '" .. tostring(name) .. "'; the inputs are " .. validActionNames()
	)
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

-- Defined with `scenario`: records a finished run of a `repeat` series and
-- starts the next, or replies with the aggregates.
local finishSeriesRun

local function finishJob(extra)
	local finished = job
	job = nil
	if finished.series then
		finishSeriesRun(finished)
		return
	end
	local payload = extra or {}
	payload.results = finished.results
	payload.player = playerSummary()
	payload.turnID = Turn.getCurrentTurnID()
	payload.level = CurrentLevel.getNumber()
	if finished.watch then
		local watch = finished.watch
		local exists = Entities.entityExists(watch.id)
		payload.watched = {
			before = watch.before,
			after = exists and dumpEntity(Entities.getEntityByID(watch.id), watch.show) or { gone = true },
		}
	end
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
	if outcome.timedOut then
		outcome.runSummary = runSummaryScreen()
	end
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
		if job.resolved and not job.resolvedTick then
			job.resolvedTick = job.ticks
		end
		if not job.resolved and job.ticks < JOB_TIMEOUT_TICKS then
			return
		end
		if job.resolved and job.ticks - job.resolvedTick < SETTLE_TICKS then
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
	job.resolvedTick = nil
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

-- Starts one run of a scenario: spawns the entity and begins the actions.
local function beginScenarioRun(id, spec, series)
	if spec.clear then
		clearEnemies()
	end
	local spawned = commands.spawn.run({ spec.typeName, spec.x, spec.y, spec.force and "force" or nil })
	startJob(id, spec.names, false)
	job.series = series
	job.watch = {
		id = spawned.id,
		show = spec.show,
		before = dumpEntity(Entities.getEntityByID(spawned.id), spec.show),
	}
end

local function sign(n)
	return n > 0 and 1 or (n < 0 and -1 or 0)
end

local function distance(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

-- What one run did to the watched entity: the beats it moved on, each step's
-- direction, and whether it got closer to the player (measured against where
-- the player ended that action, so the player's own moves do not count).
local function summarizeRun(finished)
	local watchID = finished.watch.id
	local run = { moveBeats = {}, steps = {}, closer = 0, farther = 0, damageTaken = 0 }
	for beat, outcome in ipairs(finished.results) do
		for _, moved in ipairs(outcome.entitiesMoved or {}) do
			if moved.id == watchID and moved.to then
				run.moveBeats[#run.moveBeats + 1] = beat
				local dx, dy = moved.to.x - moved.from.x, moved.to.y - moved.from.y
				run.steps[#run.steps + 1] = string.format("%d,%d", sign(dx), sign(dy))
				local before, after = distance(moved.from, outcome.to), distance(moved.to, outcome.to)
				if after < before then
					run.closer = run.closer + 1
				elseif after > before then
					run.farther = run.farther + 1
				end
			end
		end
		for _, event in ipairs(outcome.events or {}) do
			if event.event == "damage_taken" then
				run.damageTaken = run.damageTaken + event.amount
			elseif event.event == "killed" and event.targetID == watchID then
				run.killedOnBeat = beat
			end
		end
	end
	run.firstMoveBeat = run.moveBeats[1]
	local exists = Entities.entityExists(watchID)
	local position = exists and Entities.getEntityByID(watchID).position
	run.final = position and { x = position.x, y = position.y } or nil
	return run
end

local function bump(counts, key)
	key = tostring(key)
	counts[key] = (counts[key] or 0) + 1
end

local function aggregateRuns(runs)
	local aggregate = {
		runs = #runs,
		moves = 0,
		closer = 0,
		farther = 0,
		damageTaken = 0,
		killedRuns = 0,
		stepCounts = {},
		firstMoveBeat = {},
		moveBeats = {},
	}
	for _, run in ipairs(runs) do
		aggregate.moves = aggregate.moves + #run.steps
		aggregate.closer = aggregate.closer + run.closer
		aggregate.farther = aggregate.farther + run.farther
		aggregate.damageTaken = aggregate.damageTaken + run.damageTaken
		aggregate.killedRuns = aggregate.killedRuns + (run.killedOnBeat and 1 or 0)
		bump(aggregate.firstMoveBeat, run.firstMoveBeat or "never")
		for _, step in ipairs(run.steps) do
			bump(aggregate.stepCounts, step)
		end
		for _, beat in ipairs(run.moveBeats) do
			bump(aggregate.moveBeats, beat)
		end
	end
	return aggregate
end

-- Puts the player back where the series began, at full recorded health, so
-- each run starts alike. The coin multiplier is not reset.
local function resetPlayer(start)
	local player = requirePlayer()
	assert(Move.absolute(player, start.x, start.y, Move.Type.TELEPORT), "could not move the player back to the start")
	player.health.health = start.health
end

finishSeriesRun = function(finished)
	local series = finished.series
	series.runs[#series.runs + 1] = summarizeRun(finished)
	if Entities.entityExists(finished.watch.id) then
		deleteEntities({ finished.watch.id })
	end
	if #series.runs < series.total then
		resetPlayer(series.start)
		beginScenarioRun(finished.id, series.spec, series)
		return
	end
	replyData(finished.id, {
		repeated = series.total,
		aggregate = aggregateRuns(series.runs),
		runs = series.runs,
		player = playerSummary(),
		turnID = Turn.getCurrentTurnID(),
		level = CurrentLevel.getNumber(),
	})
end

-- Runs a whole experiment against the current level in one call: optionally
-- carves an arena and clears the enemies, spawns TYPE at X Y, performs the
-- actions, and replies with the actions' outcomes plus the spawned entity's
-- `watch` components before and after. With `repeat=N` it runs the experiment
-- N times from the same start and replies with aggregates instead. Start from
-- a fresh level with `new-run` first.
commands.scenario = {
	run = function(args, id)
		local words, options = {}, {}
		for _, arg in ipairs(args) do
			local key, value = arg:match("^(%w+)=(.*)$")
			if key then
				options[key] = value
			else
				words[#words + 1] = arg
			end
		end
		local typeName, x, y = words[1], words[2], words[3]
		assert(typeName and x and y, "expected TYPE X Y before the actions")
		local names = {}
		for i = 4, #words do
			names[#names + 1] = words[i]
		end
		assert(#names >= 1 and #names <= MAX_INPUTS, "give 1 to " .. MAX_INPUTS .. " actions")
		for _, name in ipairs(names) do
			resolveAction(name)
		end
		local total = options["repeat"] and tonumber(options["repeat"])
		assert(
			not options["repeat"] or (total and total >= 1 and total <= MAX_REPEATS and total % 1 == 0),
			"repeat must be a whole number from 1 to " .. MAX_REPEATS
		)
		local radius = parseArena(options.arena)
		local spec = {
			typeName = typeName,
			x = x,
			y = y,
			names = names,
			show = parseShow(options.watch or "position,health,aggro"),
			clear = options.clear == "true",
			force = options.force == "true",
		}
		local player = requirePlayer()
		if radius then
			carveArena(radius)
		end
		local series
		if total then
			series = {
				total = total,
				spec = spec,
				runs = {},
				start = { x = player.position.x, y = player.position.y, health = player.health.health },
			}
		end
		beginScenarioRun(id, spec, series)
		return PENDING
	end,
}

commands["new-run"] = {
	run = function(args)
		local character, regular, seed
		for _, arg in ipairs(args) do
			local seedText = arg:match("^seed=(.*)$")
			if arg == "rhythm=regular" then
				regular = true
			elseif seedText then
				seed = assert(tonumber(seedText), "seed must be a whole number")
				assert(seed % 1 == 0, "seed must be a whole number")
			else
				assert(
					not arg:find("=", 1, true),
					"unknown option '" .. arg .. "'; the options are rhythm=regular and seed=N"
				)
				character = arg
			end
		end
		if character then
			requireEntityType(character)
		end
		pendingSeed = seed
		-- The ~1 s command latency leaves several beats between commands.
		ExtraMode.setActive(ExtraMode.Type.NO_BEAT, not regular)
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		if character then
			Player.setCharacterType(PLAYER_ID, character)
		end
		return { started = "SingleZone", character = character, rhythmMode = rhythmModeName(), seed = seed }
	end,
}

event.levelGenerate.add("AgentBridgeSeed", { sequence = -1 }, function(ev)
	if pendingSeed and ev.options then
		ev.options.seed = pendingSeed
	end
end)

-- Pins a snapshot of the current turn so `restore` can return to it. Entities
-- the bridge spawned or converted since do not survive a restore (see
-- AuthoredDocs/Src/synchrony-game-control.md).
commands.snapshot = {
	run = function()
		requirePlayer()
		local turnID = Turn.getCurrentTurnID()
		Rollback.saveSnapshot(turnID)
		Rollback.pinSnapshot(turnID)
		return { snapshot = turnID, valid = Rollback.isValidSnapshot(turnID) }
	end,
}

-- `Rollback.loadSnapshot` alone rewinds for one tick, then the game replays the
-- action buffer back to where it was, so the buffer is cleared too.
commands.restore = {
	run = function(args)
		requirePlayer()
		local turnID = assert(tonumber(args[1]), "expected the turn ID that `snapshot` returned")
		assert(Rollback.isValidSnapshot(turnID), "no snapshot for turn " .. turnID)
		Rollback.loadSnapshot(turnID)
		ClientActionBuffer.clear()
		Rollback.saveSnapshot(turnID)
		Rollback.pinSnapshot(turnID)
		return { restored = turnID, turnID = Turn.getCurrentTurnID() }
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
