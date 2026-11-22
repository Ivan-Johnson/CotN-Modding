local Entities = require "system.game.Entities"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local Tile = require "necro.game.tile.Tile"

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
local function spawn(typeName, x, y)
	local entity = Object.spawn(typeName, x, y)
	if entity.spawnInvincibility then
		entity.spawnInvincibility.active = false
	end
	return entity
end

return {
	openArena = openArena,
	player = player,
	spawn = spawn,
}
