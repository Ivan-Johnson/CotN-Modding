-- Gary the Cowardly Sheep: a copy of Mary whose sheep, Gary, cowers while a
-- hostile enemy is near and dies of fright if something gets behind him then.
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
-- Lua error's location prefix ("<namespace>/.../GaryTheCowardlySheep.lua:N: x")
-- names it.
local NAMESPACE = (function()
	local _, message = pcall(function()
		error("x")
	end)
	return assert(message:match("^([^/]+)/"))
end)()

local M = {
	CHARACTER = NAMESPACE .. "_GaryTheCowardlySheep",
	SHEEP = NAMESPACE .. "_Gary",
}

-- Mary's XML id; the template copies everything but a few of her components,
-- which the schema handler below copies too.
local MARY_XML_ID = 12

CustomEntities.extend({
	name = "GaryTheCowardlySheep",
	template = CustomEntities.template.player(MARY_XML_ID),
})

-- Components Mary has that Gary the Cowardly Sheep must not copy: the XML
-- mapping would make the game treat him as Mary.
local NOT_COPIED = {
	name = true,
	playerXMLMapping = true,
	playableCharacterDLC = true,
}

-- Mary's sheep is the entity type Marv, which no template reaches, so Gary is
-- a copy of Marv's finished definition, added once every custom entity is
-- built. Marv has no gameplay facing, so Gary gets one; Gary the Cowardly Sheep
-- also gets every component of Mary's that the XML template left out.
event.entitySchemaGenerate.add("addGary", { order = "customEntities", sequence = 1 }, function(ev)
	local mary
	local marv
	local character
	for _, entity in pairs(ev.entityTypes) do
		if entity.name == "Mary" then
			mary = entity
		elseif entity.name == "Marv" then
			marv = entity
		elseif entity.name == M.CHARACTER then
			character = entity
		end
	end
	for component, fields in pairs(mary) do
		if character[component] == nil and not NOT_COPIED[component] then
			character[component] = Utilities.deepCopy(fields)
		end
	end
	local sheep = Utilities.deepCopy(marv)
	sheep.name = M.SHEEP
	sheep.facingDirection = {}
	sheep.turnStartPosition = {}
	ev.entityTypes[#ev.entityTypes + 1] = sheep
	character.characterWithFollower.followerType = M.SHEEP
end)

-- How far, by taxicab distance and regardless of walls, a Hostile enemy makes
-- Gary Cower.
local COWER_DISTANCE = 2

local FRIGHT_ZONE_COLOR = Color.rgba(255, 0, 0, 96)

-- Calls fn(character, gary) for each living Gary and the Gary the Cowardly
-- Sheep he follows.
local function eachGary(fn)
	for character in Entities.entitiesWithComponents({ "characterWithFollower" }) do
		if character.name == M.CHARACTER then
			local gary = Entities.getEntityByID(character.characterWithFollower.followerID)
			if gary and gary.name == M.SHEEP and not gary.killable.dead then
				fn(character, gary)
			end
		end
	end
end

-- Whether entity, which may be anything on a tile, is a Hostile enemy. The
-- game puts crates and barrels on a team hostile to Gary, and a barrel has an
-- `ai`, so only the `enemy` component tells them apart from enemies.
local function isHostileEnemy(gary, entity)
	return entity.enemy ~= nil
		and Team.isHostile(gary, entity)
		and not (entity.provokable and not entity.provokable.active)
end

local function cowers(gary)
	for entity in Entities.entitiesWithComponents({ "enemy", "position" }) do
		local dx = entity.position.x - gary.position.x
		local dy = entity.position.y - gary.position.y
		local distance = math.abs(dx) + math.abs(dy)
		if distance <= COWER_DISTANCE and isHostileEnemy(gary, entity) then
			return true
		end
	end
	return false
end

-- The Fright zone's tiles, as {x, y} pairs; empty when he has none.
local function frightZone(gary)
	local direction = gary.facingDirection.direction
	local dx = Action.dx(direction)
	local dy = Action.dy(direction)
	if (dx == 0) == (dy == 0) then
		return {}
	end
	local tiles = {}
	for depth = 1, 2 do
		for side = -1, 1 do
			tiles[#tiles + 1] = {
				gary.position.x - depth * dx - side * dy,
				gary.position.y - depth * dy + side * dx,
			}
		end
	end
	return tiles
end

-- The game never sets a follower's facing as it moves, so this sets Gary's
-- Facing from his move this turn.
local function updateFacing(gary)
	local dx = gary.position.x - gary.turnStartPosition.x
	local dy = gary.position.y - gary.turnStartPosition.y
	if dx ~= 0 or dy ~= 0 then
		gary.facingDirection.direction = Action.getDirection(dx, dy)
	end
end

local function frightens(character, gary, entity)
	return entity.id == character.id or isHostileEnemy(gary, entity)
end

-- Once per turn, after all movement (traps included) has resolved.
event.turn.add("frightenGary", { order = "nextTurnEffect", sequence = 1 }, function()
	eachGary(function(character, gary)
		updateFacing(gary)
		if not cowers(gary) then
			return
		end
		for _, tile in ipairs(frightZone(gary)) do
			for _, entityID in ipairs(Map.getAll(tile[1], tile[2])) do
				local entity = Entities.getEntityByID(entityID)
				if entity and frightens(character, gary, entity) then
					Object.kill(gary)
					return
				end
			end
		end
	end)
end)

event.render.add("renderFrightZone", { order = "tells" }, function()
	local buffer = Render.getBuffer(Render.Buffer.FLOOR)
	eachGary(function(_, gary)
		if cowers(gary) then
			for _, tile in ipairs(frightZone(gary)) do
				buffer.draw({ rect = { Render.tileRect(tile[1], tile[2], 1, 1) }, color = FRIGHT_ZONE_COLOR })
			end
		end
	end)
end)

return M
