-- Marv the Cowardly Sheep: Muriel, a copy of Mary whose sheep, Marv, dies of
-- fright if a hostile enemy he can see is on his far side from her.
-- Terms: GLOSSARY.md beside this file.
local Collision = require "necro.game.tile.Collision"
local Color = require "system.utils.Color"
local CustomEntities = require "necro.game.data.CustomEntities"
local Entities = require "system.game.Entities"
local LineOfSight = require "necro.game.system.LineOfSight"
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
-- is built. Muriel gets her own display name and every component of Mary's
-- that the XML template left out.
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
	ev.entityTypes[#ev.entityTypes + 1] = sheep
	character.characterWithFollower.followerType = M.SHEEP
end)

-- The Fright zone is a 5x5 square: FRIGHT_REACH tiles either side of its
-- centre tile.
local FRIGHT_REACH = 2

local FRIGHT_ZONE_COLOR = Color.rgba(255, 0, 0, 96)

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

local function sign(n)
	if n > 0 then
		return 1
	elseif n < 0 then
		return -1
	end
	return 0
end

-- The Fright zone's tiles, as {x, y} pairs: the square on the far side of
-- Marv from Muriel, its near edge or corner touching his tile, keeping only the tiles Marv
-- has line of sight to through walls. Empty while Muriel shares his tile.
local function frightZone(character, marv)
	local mx = marv.position.x
	local my = marv.position.y
	local dx = sign(mx - character.position.x)
	local dy = sign(my - character.position.y)
	if dx == 0 and dy == 0 then
		return {}
	end
	local centerX = mx + dx * (FRIGHT_REACH + 1)
	local centerY = my + dy * (FRIGHT_REACH + 1)
	local tiles = {}
	for y = centerY - FRIGHT_REACH, centerY + FRIGHT_REACH do
		for x = centerX - FRIGHT_REACH, centerX + FRIGHT_REACH do
			-- check returns the blocking tile, or nothing when the line is clear.
			if not LineOfSight.check(mx, my, x, y, Collision.Type.WALL) then
				tiles[#tiles + 1] = { x, y }
			end
		end
	end
	return tiles
end

-- Once per turn, after all movement (traps included) has resolved.
event.turn.add("frightenMarv", { order = "nextTurnEffect", sequence = 1 }, function()
	eachMarv(function(character, marv)
		for _, tile in ipairs(frightZone(character, marv)) do
			for _, entityID in ipairs(Map.getAll(tile[1], tile[2])) do
				local entity = Entities.getEntityByID(entityID)
				if entity and isHostileEnemy(marv, entity) then
					Object.kill(marv)
					return
				end
			end
		end
	end)
end)

-- Highlights the Fright zone.
event.render.add("renderMarvZones", { order = "tells" }, function()
	local buffer = Render.getBuffer(Render.Buffer.FLOOR)
	eachMarv(function(character, marv)
		for _, tile in ipairs(frightZone(character, marv)) do
			buffer.draw({ rect = { Render.tileRect(tile[1], tile[2], 1, 1) }, color = FRIGHT_ZONE_COLOR })
		end
	end)
end)

return M
