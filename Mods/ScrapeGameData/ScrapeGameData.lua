-- Dumps the game's own data to NecroDancer.log, the only output channel a mod
-- has. Each dataset is a string, base64-encoded and split over lines:
--   [ScrapeGameData] DATA <name> <index>/<total> <base64 chunk>
-- `nix run .#scrape-game-data` reassembles them into files. Each dump is
-- pcall'd so one failure doesn't hide the others.
local Base64 = require "system.utils.serial.Base64"
local Components = require "necro.game.data.Components"
local Entities = require "system.game.Entities"
local FileIO = require "system.game.FileIO"
local GameSession = require "necro.client.GameSession"
local GameXML = require "necro.game.data.GameXML"
local Tick = require "necro.cycles.Tick"

local CHUNK_SIZE = 4000
local MAX_DEPTH = 12

local function out(fmt, ...)
	print("[ScrapeGameData] " .. string.format(fmt, ...))
end

local function emit(name, str)
	local encoded = Base64.encode(str)
	local total = math.max(1, math.ceil(#encoded / CHUNK_SIZE))
	for i = 1, total do
		local chunk = encoded:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
		out("DATA %s %d/%d %s", name, i, total, chunk)
	end
	out("emitted %s: %d bytes", name, #str)
end

local function dump(name, produce)
	local ok, result = pcall(produce)
	if ok then
		emit(name, result)
	else
		out("ERROR %s: %s", name, tostring(result))
	end
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function isSequence(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n > 0 and #t == n
end

-- Deterministic JSON. Values JSON can't hold (functions, userdata, cycles,
-- non-finite numbers, anything past MAX_DEPTH) become strings.
local toJSON
function toJSON(value, depth, seen)
	local kind = type(value)
	if kind == "string" then
		local escaped = value:gsub('[%c"\\]', function(c)
			if c == '"' then
				return '\\"'
			elseif c == "\\" then
				return "\\\\"
			end
			return string.format("\\u%04x", c:byte())
		end)
		return '"' .. escaped .. '"'
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return toJSON(tostring(value))
		end
		return string.format("%.14g", value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind ~= "table" then
		return toJSON(tostring(value))
	end

	if seen[value] or depth > MAX_DEPTH then
		return toJSON("<" .. tostring(value) .. ">")
	end
	seen[value] = true
	local parts = {}
	local result
	if isSequence(value) then
		for i = 1, #value do
			parts[i] = toJSON(value[i], depth + 1, seen)
		end
		result = "[" .. table.concat(parts, ",") .. "]"
	else
		for _, k in ipairs(sortedKeys(value)) do
			parts[#parts + 1] = toJSON(tostring(k)) .. ":" .. toJSON(value[k], depth + 1, seen)
		end
		result = "{" .. table.concat(parts, ",") .. "}"
	end
	seen[value] = nil
	return result
end

local function json(value)
	return toJSON(value, 0, {})
end

-- Entity types can only be read once a level has loaded.
event.levelLoad.add("ScrapeProbes", { order = "extraEntities", sequence = 100 }, function()
	out("begin")

	dump("necrodancer.xml", GameXML.getXMLString)

	dump("component-defaults.json", function()
		return json(Components.getComponentDefaults())
	end)

	dump("entity-prototypes.json", function()
		local prototypes = {}
		for _, typeName in ipairs(Entities.getEntityTypesWithComponents({})) do
			prototypes[typeName] = Entities.getEntityPrototype(typeName)
		end
		return json(prototypes)
	end)

	dump("script-files.json", function()
		return json(FileIO.listFiles("scripts", FileIO.List.FILES + FileIO.List.RECURSIVE + FileIO.List.SORTED))
	end)

	out("end")
end)

-- Each (re)load of this script starts a fresh single-zone run, so the dumps
-- above fire without anyone starting a level by hand. Tick.delay's result must
-- be bound to a global variable.
-- luacheck: globals ScrapeGameData_startGameSession
ScrapeGameData_startGameSession = Tick.delay(function()
	GameSession.start({ mode = GameSession.Mode.SingleZone })
end)

ScrapeGameData_startGameSession()
