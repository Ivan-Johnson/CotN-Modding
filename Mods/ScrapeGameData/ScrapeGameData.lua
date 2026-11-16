-- Proof of concept: logs a sample of each confirmed-working data source (see
-- Docs/sources.md) to NecroDancer.log, with a "[ScrapeGameData]" prefix. Each
-- probe is pcall'd so one failure doesn't hide the others.
local Components = require "necro.game.data.Components"
local Entities = require "system.game.Entities"
local FileIO = require "system.game.FileIO"
local GameSession = require "necro.client.GameSession"
local GameXML = require "necro.game.data.GameXML"
local Tick = require "necro.cycles.Tick"

local function out(fmt, ...)
	print("[ScrapeGameData] " .. string.format(fmt, ...))
end

local function probe(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		out("%s: ERROR %s", name, tostring(err))
	end
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	return keys
end

local function dumpTable(label, t)
	for _, k in ipairs(sortedKeys(t)) do
		out("%s.%s = %s", label, k, tostring(t[k]))
	end
end

-- Entity types can only be read once a level has loaded.
event.levelLoad.add("ScrapeProbes", { order = "extraEntities", sequence = 100 }, function()
	out("begin")

	probe("xml", function()
		local xml = GameXML.getXMLString()
		out("xml: length=%d", #xml)
		out("xml head: %s", (xml:sub(1, 300):gsub("%s+", " ")))
	end)

	probe("xml-item", function()
		dumpTable("xml-item food_1", GameXML.getItemData("food_1"))
	end)

	probe("component-defaults", function()
		local defaults = Components.getComponentDefaults()
		out("components: %d", #Entities.listComponentNames())
		dumpTable("consumableHeal", defaults.consumableHeal)
	end)

	probe("entity-types", function()
		out("entity types: %d", #Entities.getEntityTypesWithComponents({}))
		local prototype = Entities.getEntityPrototype("Food1")
		dumpTable("Food1.consumableHeal", prototype.consumableHeal)
	end)

	probe("scripts-listing", function()
		local files = FileIO.listFiles("scripts", FileIO.List.FILES + FileIO.List.RECURSIVE + FileIO.List.SORTED)
		out("scripts: %d files, first %s, last %s", #files, files[1], files[#files])
	end)

	out("end")
end)

-- Each (re)load of this script starts a fresh single-zone run, so the probes
-- above fire without anyone starting a level by hand. Tick.delay's result must
-- be bound to a global variable.
-- luacheck: globals ScrapeGameData_startGameSession
ScrapeGameData_startGameSession = Tick.delay(function()
	GameSession.start({ mode = GameSession.Mode.SingleZone })
end)

ScrapeGameData_startGameSession()
