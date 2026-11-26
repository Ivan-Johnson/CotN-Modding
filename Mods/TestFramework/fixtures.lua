local Entities = require "system.game.Entities"
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

--[[
Registers a no-beat test that plays actions on an open arena. Fields:
  name, actions (list of action names), checks ({[index] = function(state, resolved)},
  run after the action at that index settles);
  radius (default 10): passed to openArena;
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
	assertAt = assertAt,
	health = health,
	openArena = openArena,
	player = player,
	repeated = repeated,
	scene = scene,
	spawn = spawn,
	tileName = tileName,
	wallColumn = wallColumn,
}
