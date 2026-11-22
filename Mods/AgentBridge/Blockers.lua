local Action = require "necro.game.system.Action"
local Entities = require "system.game.Entities"
local Map = require "necro.game.object.Map"
local Tile = require "necro.game.tile.Tile"

local PLAYER_ID = 1

local Blockers = {}

-- What stands on the tile a move would enter: its entities (wares flagged as
-- for sale), else the wall tile. Nil for a non-direction. Call it before the
-- action, because a bumped chest or shopkeeper can be gone afterwards.
function Blockers.at(from, direction)
	if not direction then
		return nil
	end
	local x = from.x + Action.dx(direction)
	local y = from.y + Action.dy(direction)
	local blockers = {}
	for _, id in ipairs(Map.getAll(x, y)) do
		local entity = Entities.getEntityByID(id)
		-- A ware's price tag is its own entity on the same tile.
		local carried = entity.item and entity.item.holder ~= 0 or entity.attachment
		if id ~= PLAYER_ID and not carried and not entity.priceTag then
			local blocker = { type = entity.name, id = id }
			if entity.sale and entity.sale.priceTag ~= 0 then
				blocker.priceTag = true
			end
			blockers[#blockers + 1] = blocker
		end
	end
	if #blockers == 0 and Tile.isSolid(x, y) then
		local info = Tile.getInfo(x, y)
		blockers[1] = { type = info and info.name or "wall" }
	end
	return #blockers > 0 and blockers or nil
end

return Blockers
