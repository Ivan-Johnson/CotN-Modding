local Currency = require "necro.game.item.Currency"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Damage = require "necro.game.system.Damage"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Marker = require "necro.game.tile.Marker"
local Move = require "necro.game.system.Move"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

local player = fixtures.player

-- The fixed seed does not fix the level's secret room: the run's random seed
-- picks it, if any. So a test restarts the run with the first level's secret
-- room set to the arena (TravelRune2) in the level sequence, after the game
-- has picked its own. Only withArena sets the flag, and the first sequence
-- built clears it, so no other file's run gets the arena.
local forceArena = false
event.levelSequenceUpdate.add("ClaimTestsArenaForce", { order = "secretRooms", sequence = 10 }, function(ev)
	if forceArena and ev.sequence[1] then
		forceArena = false
		ev.sequence[1].secretRoom = "TravelRune2"
	end
end)

-- The arena's two runes: the one on the room's floor, and the one under the
-- cracked wall in the level.
local function runes()
	local room, entrance
	for entity in Entities.entitiesWithComponents({ "trapTravel" }) do
		if entity.name == "TravelRune2" then
			if Tile.isSolid(entity.position.x, entity.position.y) then
				entrance = entity
			else
				room = entity
			end
		end
	end
	return room, entrance
end

-- Restarts the run with the arena forced, then calls andThen(room, entrance)
-- with its two runes.
local function withArena(andThen)
	forceArena = true
	local function wait()
		local room = not CurrentLevel.isLoading() and runes()
		if not room then
			testsApi.afterTicks(10, wait)
			return
		end
		testsApi.afterTicks(100, function()
			andThen(runes())
		end)
	end
	testsApi.afterTicks(10, function()
		GameSession.start({ mode = GameSession.Mode.SingleZone })
		testsApi.afterTicks(50, wait)
	end)
end

-- Some fighters' deaths raise a Lua error inside the game after the damage
-- lands; they still die.
local function kill(entity)
	pcall(Damage.inflict, {
		victim = entity,
		attacker = player(),
		damage = 99,
		type = Damage.Type.PHYSICAL + Damage.Flag.BYPASS_INVINCIBILITY,
	})
end

local function gold()
	return Currency.get(player(), Currency.Type.GOLD)
end

-- Unheld entities with a position within the room around the rune at (x0, y0),
-- other than the player and wall entities.
local function inRoom(x0, y0, component)
	local found = {}
	for entity in Entities.entitiesWithComponents({ component or "position" }) do
		local dx, dy = entity.position.x - x0, entity.position.y - y0
		local held = entity:hasComponent("item") and entity.item.holder ~= 0
		local wall = entity.name:find("Wall", 1, true) ~= nil
		if math.abs(dx) <= 3 and dy >= -9 and dy <= 2 and not held and not wall and entity.id ~= player().id then
			found[#found + 1] = entity
		end
	end
	return found
end

local function floorRows(x0, y0)
	local first, last
	for y = y0 - 12, y0 + 6 do
		if not Tile.isSolid(x0, y) then
			first = first or y
			last = y
		end
	end
	return first - y0, last - y0
end

-- The room's width in floor tiles along row y.
local function floorWidth(x0, y)
	local width = 0
	for x = x0 - 6, x0 + 6 do
		if not Tile.isSolid(x, y) then
			width = width + 1
		end
	end
	return width
end

local FIGHTS = {
	"Armoredskeleton3,Banshee,Nightmare2,Skeleton2",
	"Armoredskeleton2,Bat,BatMiniboss2,Dragon3",
	"Bat,Dragon2,Minotaur2,Skeletonmage",
}

local function fighters(room)
	local found = {}
	for _, id in ipairs(room.secretFightMarker.enemies) do
		local entity = Entities.getEntityByID(id)
		if entity then
			found[#found + 1] = entity
		end
	end
	return found
end

local function sortedNames(entities)
	local names = {}
	for _, entity in ipairs(entities) do
		names[#names + 1] = entity.name
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- Takes the middle item, 3 tiles in front of the rune, which starts the fight.
local function takeItem(room, andThen)
	Move.absolute(player(), room.position.x, room.position.y - 2, Move.Type.TELEPORT)
	testsApi.afterTicks(30, function()
		testsApi.play({ "up" }, nil, function()
			andThen()
		end)
	end)
end

-- The room: 5 by 7 floor tiles, the rune in the middle of the second row from
-- one end, three items across the middle row, no enemies, and no prices.
for _, zone in ipairs({ 1, 3 }) do
	testsApi.registerTest({
		name = "arenaRoomZone" .. zone,
		zone = zone,
		async = true,
		noBeat = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			withArena(function(room)
				local x0, y0 = room.position.x, room.position.y
				local first, last = floorRows(x0, y0)
				assert(first == -5 and last == 1, string.format("floor rows %d to %d", first, last))
				for y = y0 + first, y0 + last do
					assert(floorWidth(x0, y) == 5, "5 tiles wide at row " .. y - y0)
				end
				assert(#inRoom(x0, y0, "ai") == 0, "no enemies before the fight")
				for dx = -1, 1 do
					local items = {}
					for _, entity in ipairs(inRoom(x0, y0, "item")) do
						if entity.position.x == x0 + dx and entity.position.y == y0 - 3 then
							items[#items + 1] = entity
						end
					end
					assert(#items == 1, "one item at column " .. dx)
					local sale = items[1]:hasComponent("sale") and items[1].sale
					assert(not sale or sale.priceTag == 0, items[1].name .. " has no price tag")
				end
				assert(#inRoom(x0, y0, "item") == 3, "three items in the room")
				assert(room.secretFightMarker.started == false, "the fight has not started")
				finish()
			end)
		end,
	})
end

-- Taking an item costs nothing, makes the other two vanish, and starts the
-- fight: four enemies, one of the three groups, appear in the room.
testsApi.registerTest({
	name = "arenaTakingAnItemStartsTheFight",
	async = true,
	noBeat = true,
	timeoutTicks = 30000,
	onLoad = function(_, finish)
		withArena(function(room)
			local x0, y0 = room.position.x, room.position.y
			local middle
			for _, entity in ipairs(inRoom(x0, y0, "item")) do
				if entity.position.x == x0 then
					middle = entity
				end
			end
			Currency.add(player(), Currency.Type.GOLD, 100)
			takeItem(room, function()
				assert(middle.item.holder == player().id, "the player holds " .. middle.name)
				assert(gold() == 100, "the item cost nothing, gold " .. gold())
				assert(#inRoom(x0, y0, "item") == 0, "the other two items vanished")
				assert(room.secretFightMarker.started, "the fight started")
				local enemies = inRoom(x0, y0, "ai")
				assert(#enemies == 4, "four enemies, got " .. #enemies)
				local names = sortedNames(enemies)
				local known = false
				for _, fight in ipairs(FIGHTS) do
					known = known or fight == names
				end
				assert(known, "one of the three groups, got " .. names)
				finish()
			end)
		end)
	end,
})

-- Killing all four ends the fight: each drops gold, the room grows 3 rows at
-- the rune's end, and the rune moves to stay second from that end.
testsApi.registerTest({
	name = "arenaFightEnds",
	async = true,
	noBeat = true,
	timeoutTicks = 30000,
	onLoad = function(_, finish)
		withArena(function(room)
			local x0, y0 = room.position.x, room.position.y
			takeItem(room, function()
				local enemies = fighters(room)
				assert(#enemies == 4, "four fighters")
				for _, enemy in ipairs(enemies) do
					kill(enemy)
				end
				testsApi.play({ "idle", "idle" }, nil, function()
					assert(#inRoom(x0, y0, "ai") == 0, "the fighters are dead")
					assert(room.secretFightMarker.pending == false, "the fight is over")
					local coins = 0
					for _, entity in ipairs(inRoom(x0, y0, "item")) do
						if entity.name:find("ResourceCoin", 1, true) then
							coins = coins + 1
						end
					end
					assert(coins >= 4, "each fighter dropped gold, coins " .. coins)
					assert(room.position.x == x0 and room.position.y == y0 + 3, "the rune moved 3 tiles")
					local first, last = floorRows(x0, y0)
					assert(first == -5 and last == 4, string.format("floor rows %d to %d", first, last))
					for y = y0 + first, y0 + last do
						assert(floorWidth(x0, y) == 5, "still 5 tiles wide at row " .. y - y0)
					end
					finish()
				end)
			end)
		end)
	end,
})

-- The fighters do not hold the level's stairs locked: killing the level's
-- miniboss during the fight unlocks them.
testsApi.registerTest({
	name = "arenaFightLeavesStairsToTheMiniboss",
	async = true,
	noBeat = true,
	timeoutTicks = 30000,
	onLoad = function(_, finish)
		withArena(function(room)
			local stairs = Marker.lookUpAll(Marker.Type.STAIRS)[1]
			takeItem(room, function()
				local inArena = {}
				for _, enemy in ipairs(fighters(room)) do
					inArena[enemy.id] = true
				end
				local minibosses = 0
				for entity in Entities.entitiesWithComponents({ "stairLocker" }) do
					if not inArena[entity.id] then
						minibosses = minibosses + 1
						kill(entity)
					end
				end
				assert(minibosses > 0, "the level has a miniboss")
				testsApi.play({ "idle" }, nil, function()
					assert(#fighters(room) == 4, "the fight goes on")
					local tile = fixtures.tileName(stairs[1], stairs[2])
					assert(tile == "Stairs", "the stairs unlocked, got " .. tile)
					finish()
				end)
			end)
		end)
	end,
})

local function near(entity, target)
	return math.abs(entity.position.x - target.position.x) <= 1
		and math.abs(entity.position.y - target.position.y) <= 1
end

-- Played to the beat. The rune takes you out before the fight and after it,
-- never during it.
testsApi.registerTest({
	name = "arenaRuneIsShutDuringTheFight",
	async = true,
	timeoutTicks = 60000,
	onLoad = function(_, finish)
		withArena(function(room, entrance)
			local x0, y0 = room.position.x, room.position.y
			Move.absolute(player(), x0, y0 - 1, Move.Type.TELEPORT)
			testsApi.play({ "idle", "down", "idle" }, nil, function()
				assert(near(player(), entrance), "before the fight, the rune takes you out")
				takeItem(room, function()
					assert(room.secretFightMarker.pending, "the fight is on")
					-- Clear the way to the rune: the fighters wait at the far end.
					for index, enemy in ipairs(fighters(room)) do
						Move.absolute(enemy, x0 - 3 + index, y0 - 5, Move.Type.TELEPORT)
					end
					Move.absolute(player(), x0, y0 - 1, Move.Type.TELEPORT)
					testsApi.play({ "down", "idle" }, nil, function()
						fixtures.assertAt(player(), x0, y0, "during the fight, the rune keeps you")
						assert(room.secretFightMarker.pending, "the fight is still on")
						for _, enemy in ipairs(fighters(room)) do
							kill(enemy)
						end
						testsApi.play({ "left", "idle" }, nil, function()
							assert(not room.secretFightMarker.pending, "the fight is over")
							local rx, ry = room.position.x, room.position.y
							Move.absolute(player(), rx, ry - 1, Move.Type.TELEPORT)
							testsApi.play({ "idle", "down", "idle" }, nil, function()
								assert(near(player(), entrance), "after the fight, the rune takes you out")
								finish()
							end)
						end)
					end)
				end)
			end)
		end)
	end,
})
