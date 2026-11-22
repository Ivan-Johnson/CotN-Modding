-- Offline test for AgentBridge/Route.lua on fixture grids. Run from this
-- directory: luajit test-route.lua
package.path = "./AgentBridge/?.lua;" .. package.path
local Route = require "Route"

local failures = 0

local function expect(name, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print(("FAIL %s\n  expected: %s\n  actual:   %s"):format(name, tostring(expected), tostring(actual)))
	end
end

-- `.` costs 1, `d` costs 2 (a dug wall); `#` and everything outside the rows
-- cannot be entered. Row 1 is y = 0 and column 1 is x = `left`.
local function grid(rows, left)
	return function(x, y)
		local row = rows[y + 1]
		local cell = row and row:sub(x - left + 1, x - left + 1)
		if cell == "." then
			return 1
		elseif cell == "d" then
			return 2
		end
		return nil
	end
end

local function describe(route)
	if not route then
		return "none"
	end
	local parts = {}
	for _, tile in ipairs(route.tiles) do
		parts[#parts + 1] = tile.x .. "," .. tile.y
	end
	return route.cost .. ": " .. table.concat(parts, " ")
end

local open = grid({
	"...",
	"...",
}, 0)
expect("open room", Route.find(open, { x = 0, y = 0 }, { { x = 2, y = 1 } }).cost, 3)

local gap = grid({
	".#.",
	".#.",
	"...",
}, 0)
expect("goes around a wall", describe(Route.find(gap, { x = 0, y = 0 }, { { x = 2, y = 0 } })),
	"6: 0,1 0,2 1,2 2,2 2,1 2,0")

local dug = grid({
	".d.",
	".#.",
	"...",
}, 0)
expect("digs when cheaper", describe(Route.find(dug, { x = 0, y = 0 }, { { x = 2, y = 0 } })), "3: 1,0 2,0")

local sealed = grid({
	".#.",
}, 0)
expect("unreachable", describe(Route.find(sealed, { x = 0, y = 0 }, { { x = 2, y = 0 } })), "none")

expect("nearest of several goals", describe(Route.find(open, { x = 0, y = 0 },
	{ { x = 2, y = 1 }, { x = 1, y = 0 } })), "1: 1,0")

local negative = grid({
	"..",
}, -5)
expect("negative coordinates", describe(Route.find(negative, { x = -5, y = 0 }, { { x = -4, y = 0 } })),
	"1: -4,0")

if failures > 0 then
	os.exit(1)
end
print("route tests passed")
