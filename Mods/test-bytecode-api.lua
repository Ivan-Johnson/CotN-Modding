-- Offline test for ScrapeGameData/BytecodeApi.lua. Compiles a fixture with
-- plain LuaJIT, whose `string.dump` makes the same bytecode the game ships.
-- Run from this directory: luajit test-bytecode-api.lua
package.path = "./?.lua;" .. package.path
local BytecodeApi = require "ScrapeGameData.BytecodeApi"

local FIXTURE = [[
local Enum = require "system.utils.Enum"
local Utilities = require "system.utils.Utilities"

local Mod = {}

local function helper(hidden)
end

function Mod.add(entity, amount, ...)
end

Mod.alias = Mod.add
Mod.Type = Enum.string({ GOLD = "gold" })
Mod.label = "hello"
Mod.limit = 7
Mod.Colors = { RED = 1 }
Mod.reexport = Utilities.clamp
Mod._private = 1
Mod.helper = helper

function Mod:method(x)
end

sharedState = {}

local registry = {}
function registry.hidden(x)
end

local commands = setmetatable({}, {})
function commands.bard(enabled)
end
Mod.commands = commands

return Mod
]]

local failures = 0

local function check(description, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print(("FAIL %s: expected %s, got %s"):format(description, tostring(expected), tostring(actual)))
	end
end

local chunk = assert(loadstring(FIXTURE, "=fixture"))
local api = assert(BytecodeApi.parse(string.dump(chunk)))
local exports = api.exports

check("requires", table.concat(api.requires, ","), "system.utils.Enum,system.utils.Utilities")
check("vararg function", exports.add.signature, "add(entity, amount, ...)")
check("alias keeps the parameters", exports.alias.signature, "alias(entity, amount, ...)")
check("method takes self", exports.method.signature, "method(self, x)")
check("local function exported by assignment", exports.helper.signature, "helper(hidden)")
check("call result", exports.Type.call, "Enum.string")
check("call result template", exports.Type.args[1].members.GOLD, "gold")
check("string", exports.label.value, "hello")
check("number", exports.limit.value, 7)
check("table", exports.Colors.members.RED, 1)
check("re-export", exports.reexport.from, "Utilities.clamp")
check("private member is skipped", exports._private, nil)
check("function on a table built by a call", exports.commands.members.bard.signature, "bard(enabled)")
check("private table member", api.privateTables.registry.members.hidden.signature, "hidden(x)")
check("exported table is not private", api.privateTables.commands, nil)
check("returned table is not private", api.privateTables.Mod, nil)
check("global", api.globals.sharedState.kind, "table")

-- Past 256 constants the compiler stops using TSETS, which holds the name.
local crowded = { "local Mod = {}" }
for index = 1, 300 do
	crowded[#crowded + 1] = ("Mod.name%d = 'value%d'"):format(index, index)
end
crowded[#crowded + 1] = "function Mod.late(a, b) end"
crowded[#crowded + 1] = "return Mod"
local crowdedApi = assert(BytecodeApi.parse(string.dump(assert(loadstring(table.concat(crowded, "\n"), "=crowded")))))
check("member named from a register", crowdedApi.exports.late.signature, "late(a, b)")

local sourceApi = assert(BytecodeApi.parse([[
local Enum = require "system.utils.Enum"
local mod = {}
function mod.plain(a,
	b)
end
function mod:method(x)
end
mod.assigned = function(y) end
function mod._private() end
local function hidden() end
return mod
]]))
check("source flagged heuristic", sourceApi.source, true)
check("source function", sourceApi.exports.plain.signature, "plain(a, b)")
check("source method takes self", sourceApi.exports.method.signature, "method(self, x)")
check("source assigned function", sourceApi.exports.assigned.signature, "assigned(y)")
check("source private skipped", sourceApi.exports._private, nil)
check("source local function skipped", sourceApi.exports.hidden, nil)
check("source requires", sourceApi.requires[1], "system.utils.Enum")
check("source without a returned table", select(2, BytecodeApi.parse("local x = 1")), "no returned table")

if failures > 0 then
	os.exit(1)
end
print("ok")
