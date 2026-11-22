-- The shortest-route search behind `agent-bridge route`, kept free of game
-- calls so that Mods/test-route.lua can run it under plain LuaJIT.
local Route = {}

local STEPS = {
	{ dx = 0, dy = -1 },
	{ dx = 0, dy = 1 },
	{ dx = -1, dy = 0 },
	{ dx = 1, dy = 0 },
}

local function key(x, y)
	return y * 65536 + x
end

local function push(heap, item)
	heap[#heap + 1] = item
	local i = #heap
	while i > 1 do
		local parent = math.floor(i / 2)
		if heap[parent].cost <= heap[i].cost then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function pop(heap)
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local smallest = i
			for _, child in ipairs({ i * 2, i * 2 + 1 }) do
				if heap[child] and heap[child].cost < heap[smallest].cost then
					smallest = child
				end
			end
			if smallest == i then
				break
			end
			heap[smallest], heap[i] = heap[i], heap[smallest]
			i = smallest
		end
	end
	return top
end

-- `enterCost(x, y)` is what it costs to step onto a tile, or nil when the tile
-- cannot be entered (and so must be nil outside the level, which ends the
-- search). Finds the cheapest orthogonal route from `start` to the nearest of
-- `goals`, all `{ x = , y = }`. Returns `{ goal =, cost =, tiles = }`, where
-- `tiles` lists each tile entered, in order, or nil when no goal is reachable.
function Route.find(enterCost, start, goals)
	local isGoal = {}
	for _, goal in ipairs(goals) do
		isGoal[key(goal.x, goal.y)] = goal
	end
	local best = { [key(start.x, start.y)] = 0 }
	local from = {}
	local coords = { [key(start.x, start.y)] = start }
	local heap = {}
	push(heap, { x = start.x, y = start.y, cost = 0 })
	while #heap > 0 do
		local node = pop(heap)
		local nodeKey = key(node.x, node.y)
		if node.cost <= best[nodeKey] then
			local goal = isGoal[nodeKey]
			if goal then
				local tiles = {}
				local at = nodeKey
				while from[at] do
					table.insert(tiles, 1, coords[at])
					at = from[at]
				end
				return { goal = goal, cost = node.cost, tiles = tiles }
			end
			for _, step in ipairs(STEPS) do
				local x, y = node.x + step.dx, node.y + step.dy
				local cost = enterCost(x, y)
				if cost then
					local total = node.cost + cost
					local nextKey = key(x, y)
					if not best[nextKey] or total < best[nextKey] then
						best[nextKey] = total
						from[nextKey] = nodeKey
						coords[nextKey] = { x = x, y = y }
						push(heap, { x = x, y = y, cost = total })
					end
				end
			end
		end
	end
	return nil
end

return Route
