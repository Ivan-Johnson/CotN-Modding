-- Marv the Cowardly Sheep: Muriel, a copy of Mary whose sheep, Marv, cowers
-- while a hostile enemy is near and dies of fright if something gets behind
-- him then.
-- Terms: GLOSSARY.md beside this file.
local Action = require "necro.game.system.Action"
local Color = require "system.utils.Color"
local CustomEntities = require "necro.game.data.CustomEntities"
local Entities = require "system.game.Entities"
local Map = require "necro.game.object.Map"
local Object = require "necro.game.object.Object"
local Render = require "necro.render.Render"
local Team = require "necro.game.character.Team"
local Utilities = require "system.utils.Utilities"

-- Custom entity types are named `<namespace>_<name>`. The namespace is the
-- enabled mod's directory, which a dev install nests in a bundle mod, and a
-- Lua error's location prefix ("<namespace>/.../MarvTheCowardlySheep.lua:N: x")
-- names it.
local NAMESPACE = (function()
	local _, message = pcall(function()
		error("x")
	end)
	return assert(message:match("^([^/]+)/"))
end)()

-- Muriel's entity name, which a custom entity type prefixes with the
-- namespace, and her display name.
local MURIEL = "Muriel"

local M = {
	CHARACTER = NAMESPACE .. "_" .. MURIEL,
	SHEEP = NAMESPACE .. "_Marv",
}

-- Mary's XML id; the template copies everything but a few of her components,
-- which the schema handler below copies too.
local MARY_XML_ID = 12

CustomEntities.extend({
	name = MURIEL,
	template = CustomEntities.template.player(MARY_XML_ID),
})

-- Components Mary has that Muriel must not copy: the XML mapping would make
-- the game treat her as Mary.
local NOT_COPIED = {
	name = true,
	playerXMLMapping = true,
	playableCharacterDLC = true,
}

-- Vanilla Marv is the entity type Marv, which no template reaches, so Marv is
-- a copy of Vanilla Marv's finished definition, added once every custom entity
-- is built. Vanilla Marv has no gameplay facing, so Marv gets one; Muriel gets
-- her own display name and every component of Mary's that the XML template
-- left out.
event.entitySchemaGenerate.add("addMarv", { order = "customEntities", sequence = 1 }, function(ev)
	local mary
	local vanillaMarv
	local character
	for _, entity in pairs(ev.entityTypes) do
		if entity.name == "Mary" then
			mary = entity
		elseif entity.name == "Marv" then
			vanillaMarv = entity
		elseif entity.name == M.CHARACTER then
			character = entity
		end
	end
	for component, fields in pairs(mary) do
		if character[component] == nil and not NOT_COPIED[component] then
			character[component] = Utilities.deepCopy(fields)
		end
	end
	character.friendlyName = { name = MURIEL }
	local sheep = Utilities.deepCopy(vanillaMarv)
	sheep.name = M.SHEEP
	sheep.facingDirection = {}
	sheep.turnStartPosition = {}
	ev.entityTypes[#ev.entityTypes + 1] = sheep
	character.characterWithFollower.followerType = M.SHEEP
end)

-- The Cower zone's reach, by taxicab distance and regardless of walls.
local COWER_DISTANCE = 2

local FRIGHT_ZONE_COLOR = Color.rgba(255, 0, 0, 96)
local COWER_ZONE_COLOR = Color.rgba(255, 255, 0, 96)

-- Calls fn(character, marv) for each living Marv and the Muriel player he follows.
local function eachMarv(fn)
	for character in Entities.entitiesWithComponents({ "characterWithFollower" }) do
		if character.name == M.CHARACTER then
			local marv = Entities.getEntityByID(character.characterWithFollower.followerID)
			if marv and marv.name == M.SHEEP and not marv.killable.dead then
				fn(character, marv)
			end
		end
	end
end

-- Whether entity, which may be anything on a tile, is a Hostile enemy. The
-- game puts crates and barrels on a team hostile to Marv, and a barrel has an
-- `ai`, so only the `enemy` component tells them apart from enemies.
local function isHostileEnemy(marv, entity)
	return entity.enemy ~= nil
		and Team.isHostile(marv, entity)
		and not (entity.provokable and not entity.provokable.active)
end

-- Whether any entity on the {x, y} tiles satisfies predicate(entity).
local function anyOn(tiles, predicate)
	for _, tile in ipairs(tiles) do
		for _, entityID in ipairs(Map.getAll(tile[1], tile[2])) do
			local entity = Entities.getEntityByID(entityID)
			if entity and predicate(entity) then
				return true
			end
		end
	end
	return false
end

-- The Cower zone's tiles, as {x, y} pairs.
local function cowerZone(marv)
	local tiles = {}
	for dx = -COWER_DISTANCE, COWER_DISTANCE do
		local reach = COWER_DISTANCE - math.abs(dx)
		for dy = -reach, reach do
			tiles[#tiles + 1] = { marv.position.x + dx, marv.position.y + dy }
		end
	end
	return tiles
end

local function cowers(marv)
	return anyOn(cowerZone(marv), function(entity)
		return isHostileEnemy(marv, entity)
	end)
end

-- The Fright zone's tiles, as {x, y} pairs; empty when he has none.
local function frightZone(marv)
	local direction = marv.facingDirection.direction
	local dx = Action.dx(direction)
	local dy = Action.dy(direction)
	if (dx == 0) == (dy == 0) then
		return {}
	end
	local tiles = {}
	for depth = 1, 2 do
		for side = -1, 1 do
			tiles[#tiles + 1] = {
				marv.position.x - depth * dx - side * dy,
				marv.position.y - depth * dy + side * dx,
			}
		end
	end
	return tiles
end

-- The game never sets a follower's facing as it moves, so this sets Marv's
-- Facing from his move this turn.
local function updateFacing(marv)
	local dx = marv.position.x - marv.turnStartPosition.x
	local dy = marv.position.y - marv.turnStartPosition.y
	if dx ~= 0 or dy ~= 0 then
		marv.facingDirection.direction = Action.getDirection(dx, dy)
	end
end

local function frightens(character, marv, entity)
	return entity.id == character.id or isHostileEnemy(marv, entity)
end

-- Once per turn, after all movement (traps included) has resolved.
event.turn.add("frightenMarv", { order = "nextTurnEffect", sequence = 1 }, function()
	eachMarv(function(character, marv)
		updateFacing(marv)
		local frightened = cowers(marv)
			and anyOn(frightZone(marv), function(entity)
				return frightens(character, marv, entity)
			end)
		if frightened then
			Object.kill(marv)
		end
	end)
end)

-- Highlights the Fright zone while Marv Cowers, and the Cower zone otherwise.
event.render.add("renderMarvZones", { order = "tells" }, function()
	local buffer = Render.getBuffer(Render.Buffer.FLOOR)
	eachMarv(function(_, marv)
		local tiles
		local color
		if cowers(marv) then
			tiles = frightZone(marv)
			color = FRIGHT_ZONE_COLOR
		else
			tiles = cowerZone(marv)
			color = COWER_ZONE_COLOR
		end
		for _, tile in ipairs(tiles) do
			buffer.draw({ rect = { Render.tileRect(tile[1], tile[2], 1, 1) }, color = color })
		end
	end)
end)

return M
