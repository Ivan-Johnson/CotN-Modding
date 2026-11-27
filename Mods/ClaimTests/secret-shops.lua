local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Move = require "necro.game.system.Move"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

--[[
Each test starts its own runs, since a test needs a secret room on level 1 or
many runs' level sequences. A run's sequence names each level's secret room
as `secretRoom = "TravelRune<N>"`. To get a chosen room, a test sets `forced`
and starts a single-zone run: the handler below then puts that room on level 1
and no other. The level is still generated from the framework's fixed seed, so
on it the cracked wall is at (-10,14) and the room's rune at (-19,-13).
]]

local sequence
local forced
local loaded = false

event.levelSequenceUpdate.add("ClaimTestsSecretShopsForce", { order = "secretRooms", sequence = 10 }, function(ev)
	if forced then
		for index, level in ipairs(ev.sequence) do
			level.secretRoom = index == 1 and forced or nil
		end
	end
end)

event.levelSequenceUpdate.add("ClaimTestsSecretShopsSequence", { order = "markFinal", sequence = 10 }, function(ev)
	sequence = ev.sequence
end)

event.levelLoad.add("ClaimTestsSecretShopsLoaded", { order = "extraEntities", sequence = 20 }, function()
	loaded = true
end)

-- Starts a run (options as for GameSession.start) and calls andThen once its
-- first level has loaded. A start made at once from onLoad is lost, so wait.
local function startRun(options, andThen)
	testsApi.afterTicks(100, function()
		sequence = nil
		loaded = false
		GameSession.start(options)
		local function poll()
			if sequence == nil or not loaded or CurrentLevel.isLoading() then
				testsApi.afterTicks(10, poll)
				return
			end
			testsApi.afterTicks(20, andThen)
		end
		testsApi.afterTicks(30, poll)
	end)
end

-- A single-zone run with the given room on level 1.
local function startWithRoom(kind, andThen)
	forced = "TravelRune" .. kind
	startRun({ mode = GameSession.Mode.SingleZone }, function()
		forced = nil
		andThen()
	end)
end

local function crackedTiles()
	local x0, y0, width, height = Tile.getLevelBounds()
	local found = {}
	for y = y0, y0 + height - 1 do
		for x = x0, x0 + width - 1 do
			local info = Tile.getInfo(x, y)
			-- Some levels also have a cracked floor tile, Sync_FloorCracked.
			if info and info.isWall and info.name:find("Cracked", 1, true) then
				found[#found + 1] = { x = x, y = y, info = info }
			end
		end
	end
	return found
end

-- The level's two travel runes: the one under the cracked wall, and the one
-- in the secret room.
local function runes()
	local entrance, inner
	local count = 0
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if entity.name:find("^TravelRune") then
			count = count + 1
			if fixtures.tileName(entity.position.x, entity.position.y):find("Cracked", 1, true) then
				entrance = entity
			else
				inner = entity
			end
		end
	end
	return entrance, inner, count
end

-- Floods from (x, y) through floor and shop wall, as if every shop wall were
-- dug, and returns the tiles reached (name by "x,y") and their count. The level
-- border and the space outside the level stop it.
local function sealedRegion(x, y)
	local region = {}
	local stack = { { x, y } }
	local count = 0
	while #stack > 0 and count < 300 do
		local tile = table.remove(stack)
		local key = tile[1] .. "," .. tile[2]
		local info = Tile.getInfo(tile[1], tile[2])
		local name = info and info.name
		if not region[key] and name and name ~= "LevelBorder" then
			region[key] = info.isFloor and "floor" or name
			count = count + 1
			if info.isFloor or name == "ShopWall" then
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					stack[#stack + 1] = { tile[1] + d[1], tile[2] + d[2] }
				end
			end
		end
	end
	return region, count
end

-- Per travel rune type: the cracked wall in front of it, that wall's plain
-- counterpart, and who keeps the room (the arena has no keeper).
local ROOMS = {
	{ wall = "StoneWallCracked", plain = "StoneWall", keeper = "Transmogrifier" },
	{ wall = "DirtWallCracked", plain = "DirtWall", keeper = "" },
	{ wall = "StoneWallCracked", plain = "StoneWall", keeper = "Shopkeeper2" },
	{ wall = "StoneWallCracked", plain = "StoneWall", keeper = "Shopkeeper3" },
	{ wall = "CatacombWallCracked", plain = "CatacombWall", keeper = "Shopkeeper4" },
	{ wall = "DirtWallCracked", plain = "DirtWall", keeper = "Conjurer" },
	{ wall = "DirtWallCracked", plain = "DirtWall", keeper = "Shriner" },
	{ wall = "CatacombWallCracked", plain = "CatacombWall", keeper = "Pawnbroker" },
}

local FRIENDLY = {
	DirtWallCracked = "Cracked dirt wall",
	StoneWallCracked = "Cracked stone wall",
	CatacombWallCracked = "Cracked catacomb wall",
}

-- Each room sits behind its own kind of cracked wall, as tough as the plain
-- wall, with a travel rune under it and a second one in the room. The room is
-- a closed patch of floor ringed by shop wall, and beyond that only the level
-- border.
testsApi.registerTest({
	name = "secretShopsCrackedWallPerRoom",
	async = true,
	timeoutTicks = 60000,
	onLoad = function(_, finish)
		local kind = 0
		local function nextKind()
			kind = kind + 1
			if kind > #ROOMS then
				finish()
				return
			end
			startWithRoom(kind, function()
				local room = ROOMS[kind]
				local where = "TravelRune" .. kind
				local cracked = crackedTiles()
				assert(#cracked == 1, where .. ": cracked walls " .. #cracked)
				local wall = cracked[1].info
				assert(wall.name == room.wall, where .. ": wall " .. wall.name)
				assert(wall.friendlyName == FRIENDLY[wall.name], where .. ": called " .. tostring(wall.friendlyName))
				Tile.setType(cracked[1].x + 1, cracked[1].y, room.plain)
				local plain = Tile.getInfo(cracked[1].x + 1, cracked[1].y)
				assert(wall.digResistance == plain.digResistance, where .. ": toughness " .. wall.digResistance)
				assert(wall.texture ~= plain.texture, where .. ": looks like the plain wall")
				local entrance, inner, count = runes()
				assert(count == 2 and entrance and inner, where .. ": runes " .. count)
				assert(entrance.name == where and inner.name == where, where .. ": rune types")
				local keepers = {}
				for entity in Entities.entitiesWithComponents({ "shopkeeper" }) do
					if entity.name ~= "Shopkeeper" then
						keepers[#keepers + 1] = entity.name
					end
				end
				assert(table.concat(keepers, ",") == room.keeper, where .. ": keeper " .. table.concat(keepers, ","))
				-- Digging through every shop wall from the room reaches only
				-- the level border.
				local region, size = sealedRegion(inner.position.x, inner.position.y)
				assert(size < 300, where .. ": the room is sealed")
				for _, name in pairs(region) do
					assert(name == "floor" or name == "ShopWall", where .. ": reached " .. name)
				end
				nextKind()
			end)
		end
		nextKind()
	end,
})

-- Single Zone runs, of each zone in turn: each regular floor has a secret room
-- roughly half the time, the boss floor never; a run never repeats a room
-- and never gets the transmogrifier; every other room turns up on every
-- regular floor. Level 1 has a cracked wall exactly when it has a secret room.
-- A small sample (api.smallSample) plays one run of each zone and skips the
-- odds.
testsApi.registerTest({
	name = "secretShopsSingleZoneOdds",
	async = true,
	timeoutTicks = 400000,
	onLoad = function(_, finish)
		local small = testsApi.smallSample()
		local runs = small and 5 or 150
		local done = 0
		local perFloor = { 0, 0, 0 }
		local kindFloors = {}
		local function options()
			return { mode = GameSession.Mode.SingleZone, zone = done % 5 + 1 }
		end
		local function check()
			local seen = {}
			for index, level in ipairs(sequence) do
				local where = "run " .. done .. " level " .. index
				if level.type == "Boss" then
					assert(not level.secretRoom, where .. ": a boss level has a room")
				elseif level.secretRoom then
					assert(level.secretRoom ~= "TravelRune1", where .. ": transmogrifier")
					assert(not seen[level.secretRoom], where .. ": repeated " .. level.secretRoom)
					seen[level.secretRoom] = true
					perFloor[level.floor] = perFloor[level.floor] + 1
					kindFloors[level.secretRoom .. "@" .. level.floor] = true
				end
			end
			local cracked = crackedTiles()
			local message = "run " .. done .. " zone " .. sequence[1].zone .. ": " .. tostring(sequence[1].secretRoom)
			for _, tile in ipairs(cracked) do
				message = message .. " " .. tile.info.name .. "@" .. tile.x .. "," .. tile.y
			end
			assert((#cracked == 1) == (sequence[1].secretRoom ~= nil), message)
			done = done + 1
			if done < runs then
				startRun(options(), check)
				return
			end
			if small then
				finish()
				return
			end
			for floor = 1, 3 do
				testsApi.observe("floor" .. floor, perFloor[floor])
				assert(perFloor[floor] > runs * 0.3 and perFloor[floor] < runs * 0.6, "floor " .. floor .. ": " .. perFloor[floor])
			end
			for kind = 2, 8 do
				for floor = 1, 3 do
					assert(kindFloors["TravelRune" .. kind .. "@" .. floor], "TravelRune" .. kind .. " on floor " .. floor)
				end
			end
			finish()
		end
		startRun(options(), check)
	end,
})

-- All Zones runs: one of each of the eight rooms, each on its own regular
-- level, the blood shop on 1-1 or 1-2.
testsApi.registerTest({
	name = "secretShopsAllZonesOneOfEach",
	async = true,
	timeoutTicks = 200000,
	onLoad = function(_, finish)
		local runs = 30
		local done = 0
		local function check()
			local seen = {}
			local count = 0
			for _, level in ipairs(sequence) do
				local where = "run " .. done .. " " .. level.zone .. "-" .. level.floor
				if level.secretRoom then
					assert(level.type ~= "Boss", where .. ": a boss level has a room")
					assert(not seen[level.secretRoom], where .. ": repeated " .. level.secretRoom)
					seen[level.secretRoom] = true
					count = count + 1
					if level.secretRoom == "TravelRune3" then
						assert(level.zone == 1 and level.floor <= 2, where .. ": blood shop")
					end
				end
			end
			assert(count == 8, "run " .. done .. ": rooms " .. count)
			done = done + 1
			if done < runs then
				startRun({ mode = GameSession.Mode.AllZones }, check)
			else
				finish()
			end
		end
		startRun({ mode = GameSession.Mode.AllZones }, check)
	end,
})

-- Played to the beat: dig the cracked wall, step onto its rune, and a moment
-- later you stand on the rune in the room, with your items and gold;
-- an enemy beside you stays behind. The room's rune takes you back onto the
-- cracked wall's tile, and the runes work every time.
for _, kind in ipairs({ 6, 7 }) do
	testsApi.registerTest({
		name = "secretShopsTravelRune" .. kind,
		async = true,
		timeoutTicks = 60000,
		onLoad = function(_, finish)
			startWithRoom(kind, function()
				local entrance, inner = runes()
				local ex, ey = entrance.position.x, entrance.position.y
				local ix, iy = inner.position.x, inner.position.y
				assert(ex == -10 and ey == 14 and ix == -19 and iy == -13, "the runes are where the test expects")
				-- Only the room's keeper and a skeleton beside the wall stay.
				local doomed = {}
				for entity in Entities.entitiesWithComponents({ "ai" }) do
					if entity.name ~= ROOMS[kind].keeper then
						doomed[#doomed + 1] = entity
					end
				end
				for _, entity in ipairs(doomed) do
					Object.delete(entity)
				end
				local player = fixtures.player()
				Move.absolute(player, -9, 14, Move.Type.TELEPORT)
				local skeleton = fixtures.spawn("Skeleton", -8, 14)
				player.health.maxHealth = 100
				player.health.health = 100
				player.goldCounter.amount = 33
				local items = #Inventory.getItems(player)
				local function arrive(x, y, andThen, waited)
					waited = waited or 0
					local position = fixtures.player().position
					if position.x == x and position.y == y then
						andThen(waited)
					else
						assert(waited < 2000, string.format("never reached (%d,%d), at (%d,%d)", x, y, position.x, position.y))
						testsApi.afterTicks(20, function()
							arrive(x, y, andThen, waited + 20)
						end)
					end
				end
				local function step(direction, andThen)
					testsApi.play({ direction }, nil, function()
						testsApi.afterTicks(600, andThen)
					end)
				end
				-- Wait out the invincibility a level starts with.
				testsApi.afterTicks(1200, function()
					step("left", function()
						assert(fixtures.tileName(ex, ey) == "Floor", "the dig opened the wall")
						fixtures.assertAt(fixtures.player(), -9, 14, "a dig leaves you in place")
						step("left", function()
							arrive(ix, iy, function()
								testsApi.afterTicks(2000, function()
									player = fixtures.player()
									fixtures.assertAt(player, ix, iy, "standing on the room's rune keeps you there")
									assert(#Inventory.getItems(player) == items, "items kept")
									assert(player.goldCounter.amount == 33, "gold kept")
									for entity in Entities.entitiesWithComponents({ "ai" }) do
										local dx = entity.position.x - ix
										local dy = entity.position.y - iy
										local near = math.abs(dx) + math.abs(dy) <= 10
										assert(entity.name ~= "Skeleton" or not near, "the skeleton stayed behind")
									end
									assert(Entities.entityExists(skeleton.id), "the skeleton lives on outside")
									Object.delete(skeleton)
									step("right", function()
										step("left", function()
											arrive(ex, ey, function()
												step("right", function()
													step("left", function()
														arrive(ix, iy, function()
															finish()
														end)
													end)
												end)
											end)
										end)
									end)
								end)
							end)
						end)
					end)
				end)
			end)
		end,
	})
end

-- A cracked wall needs a shovel as strong as its plain wall: the basic shovel
-- digs a cracked dirt wall but not a cracked stone or catacomb wall. A bomb
-- opens each kind, and the rune under it still works.
-- Each case is a room and whether the first action digs at its wall; a dug
-- dirt wall is already open, so the bomb case for dirt idles instead.
for _, case in ipairs({ { 2, "left" }, { 2, "idle" }, { 4, "left" }, { 5, "left" } }) do
	local kind, first = case[1], case[2]
	testsApi.registerTest({
		name = "secretShopsCrackedWallShovelAndBomb" .. kind .. first,
		async = true,
		noBeat = true,
		timeoutTicks = 60000,
		onLoad = function(_, finish)
			startWithRoom(kind, function()
				local wall = ROOMS[kind].wall
				local _, inner = runes()
				local ix, iy = inner.position.x, inner.position.y
				-- Clear the enemies around the cracked wall at (-10,14).
				local doomed = {}
				for entity in Entities.entitiesWithComponents({ "ai" }) do
					if math.abs(entity.position.x + 10) + math.abs(entity.position.y - 14) <= 8 then
						doomed[#doomed + 1] = entity
					end
				end
				for _, entity in ipairs(doomed) do
					Object.delete(entity)
				end
				local player = fixtures.player()
				Move.absolute(player, -9, 14, Move.Type.TELEPORT)
				player.health.maxHealth = 100
				player.health.health = 100
				assert(Inventory.getItemInSlot(player, "shovel").name == "ShovelBasic", "holding the basic shovel")
				local actions = { first, "bomb", "right", "right", "idle", "idle", "idle", "left", "left", "left", "right" }
				testsApi.play(actions, function(index)
					if index == 1 then
						local expected = kind == 2 and first == "left" and "Floor" or wall
						assert(fixtures.tileName(-10, 14) == expected, first .. " at " .. wall)
						fixtures.assertAt(fixtures.player(), -9, 14, "a dig leaves you in place")
					elseif index == 7 then
						assert(fixtures.tileName(-10, 14) == "Floor", "the bomb opened the wall, got " .. fixtures.tileName(-10, 14))
					end
				end, function()
					-- The next action, sent before the rune's delay runs out,
					-- lands the trip first and then steps you off the room's rune.
					local position = fixtures.player().position
					local away = math.abs(position.x - ix) + math.abs(position.y - iy)
					assert(away <= 1, string.format("the rune took you to the room, at (%d,%d)", position.x, position.y))
					finish()
				end)
			end)
		end,
	})
end

-- Some characters never meet some rooms: in their All Zones runs the banned
-- rooms are missing and every other room appears once.
local BANS = { Aria = { 3, 5 }, Coda = { 3, 5 }, Dove = { 2 }, Monk = { 8 } }
testsApi.registerTest({
	name = "secretShopsCharacterBans",
	async = true,
	timeoutTicks = 200000,
	onLoad = function(_, finish)
		local queue = {}
		for character, banned in pairs(BANS) do
			for _ = 1, 3 do
				queue[#queue + 1] = { character = character, banned = banned }
			end
		end
		local index = 0
		local function nextRun()
			index = index + 1
			local entry = queue[index]
			if not entry then
				Player.setCharacterType(1, "Cadence")
				finish()
				return
			end
			Player.setCharacterType(1, entry.character)
			startRun({ mode = GameSession.Mode.AllZones }, function()
				local seen = {}
				local count = 0
				for _, level in ipairs(sequence) do
					if level.secretRoom then
						seen[level.secretRoom] = true
						count = count + 1
					end
				end
				for _, kind in ipairs(entry.banned) do
					assert(not seen["TravelRune" .. kind], entry.character .. " got TravelRune" .. kind)
				end
				assert(count == 8 - #entry.banned, entry.character .. ": rooms " .. count)
				nextRun()
			end)
		end
		nextRun()
	end,
})
