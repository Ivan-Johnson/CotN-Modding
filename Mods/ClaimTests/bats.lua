local Entities = require "system.game.Entities"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence in no-beat mode on an open floor with the player
-- at (0,0), spawning bats by hand unless it says otherwise; "up" is toward
-- negative y. A test that needs many random outcomes runs its trials inside
-- one test, since every test starts from the same seed.

local TYPES = { "Bat", "Bat2", "Bat3" }
local DAMAGE = { Bat = 1, Bat2 = 2, Bat3 = 3 }

local health = fixtures.health
local assertAt = fixtures.assertAt

-- ai.directions codes: 1 is right, 3 up, 5 left, 7 down, the evens diagonal.
local DX = { 1, 1, 0, -1, -1, -1, 0, 1 }
local DY = { 0, -1, -1, -1, 0, 1, 1, 1 }

-- Walls in every tile around (x, y) except those named in open ("x,y").
local function pocket(x, y, open)
	for wx = x - 1, x + 1 do
		for wy = y - 1, y + 1 do
			if not (wx == x and wy == y) and not open[wx .. "," .. wy] then
				Tile.setType(wx, wy, "StoneWall")
			end
		end
	end
end

-- The player loses no health for good: a test that counts hits heals after
-- each one, so the count does not end in death.
local function heal()
	fixtures.player().health.health = 12
end

-- Runs count trials of a bat spawned at (x, y) after prepare(), each on a
-- fresh arena, playing actions and calling afterEach(index, bat, trial) after
-- each; then calls onDone().
local function trials(typeName, count, x, y, prepare, actions, afterEach, onDone)
	local trial = 0
	local function nextTrial()
		trial = trial + 1
		if trial > count then
			onDone()
			return
		end
		fixtures.openArena(12)
		if prepare then
			prepare()
		end
		heal()
		local bat = fixtures.spawn(typeName, x, y)
		testsApi.play(actions, function(index)
			afterEach(index, bat, trial)
		end, nextTrial)
	end
	nextTrial()
end

local function asyncTest(name, body)
	testsApi.registerTest({ name = name, noBeat = true, async = true, timeoutTicks = 120000, onLoad = body })
end

-- A bat whose only free neighbour is the player's tile attacks every time it
-- acts, without moving: a Bat every second beat, a Bat2 or Bat3 every beat,
-- but no hit lands on the beat after a hit (nor on the level's first beat), so
-- every bat lands one every second beat. Its damage is the table's, and one
-- dagger hit kills it. A Bat3 attacks diagonally too.
for _, typeName in ipairs(TYPES) do
	local spots = { { 1, 0 } }
	if typeName == "Bat3" then
		table.insert(spots, { 1, 1 })
	end
	for _, spot in ipairs(spots) do
		local x, y = spot[1], spot[2]
		local trace, full
		local checks = {}
		for index = 1, 6 do
			checks[index] = function(bat)
				assertAt(bat, x, y, "a cornered bat never moves")
				table.insert(trace, health())
			end
		end
		checks[7] = function(bat)
			local d = DAMAGE[typeName]
			local f = full
			local expected = typeName == "Bat" and { f, f, f - d, f - d, f - 2 * d, f - 2 * d }
				or { f, f - d, f - d, f - 2 * d, f - 2 * d, f - 3 * d }
			assert(
				table.concat(trace, ",") == table.concat(expected, ","),
				"health after each beat " .. table.concat(trace, ",")
			)
			if y == 0 then
				assert(not Entities.entityExists(bat.id), "one dagger hit kills a bat")
			end
		end
		fixtures.scene({
			name = "batCornered" .. typeName .. "At" .. x .. y,
			setup = function()
				trace = {}
				full = health()
				pocket(x, y, { ["0,0"] = true })
				return fixtures.spawn(typeName, x, y)
			end,
			actions = { "idle", "idle", "idle", "idle", "idle", "idle", y == 0 and "right" or "idle" },
			checks = checks,
		})
	end
end

-- A bat with one free neighbouring tile steps onto it the first time it acts,
-- every time: a step at a wall is never wasted.
for _, typeName in ipairs(TYPES) do
	asyncTest("batTakesTheOnlyFreeTile" .. typeName, function(_, finish)
		trials(typeName, 6, 2, 0, function()
			pocket(2, 0, { ["3,0"] = true })
		end, { "idle" }, function(_, bat, trial)
			assertAt(bat, 3, 0, "trial " .. trial)
		end, finish)
	end)
end

-- A bat boxed in by walls, or by walls and an enemy, stays put and attacks
-- nothing.
for _, typeName in ipairs(TYPES) do
	fixtures.scene({
		name = "batBoxedInStaysPut" .. typeName,
		setup = function()
			pocket(2, 0, { ["3,0"] = true })
			pocket(-2, 0, {})
			return {
				byEnemy = fixtures.spawn(typeName, 2, 0),
				slime = fixtures.spawn("Slime", 3, 0),
				byWalls = fixtures.spawn(typeName, -2, 0),
			}
		end,
		actions = fixtures.repeated("idle", 8),
		checks = {
			[8] = function(scene)
				assertAt(scene.byEnemy, 2, 0, "boxed in by walls and a slime")
				assertAt(scene.byWalls, -2, 0, "boxed in by walls")
				assert(Entities.entityExists(scene.slime.id), "the bat does not attack the slime")
				assert(scene.slime.health.health == scene.slime.health.maxHealth, "the slime is unhurt")
			end,
		},
	})
end

-- In the open a bat steps on nearly every action it takes (a Bat never on two
-- actions in a row), one tile in one of its directions: never diagonally for Bat and
-- Bat2, often diagonally for Bat3. The steps do not lean toward the player:
-- the share that get closer matches a uniform pick among the free tiles.
for _, typeName in ipairs(TYPES) do
	asyncTest("batRandomWalk" .. typeName, function(_, finish)
		local s = { acts = 0, moves = 0, diagonal = 0, closer = 0, expectedCloser = 0, outcomes = {} }
		local last, hp, actedLast
		-- A Bat acts half as often, so it gets twice the trials. A small
		-- sample (api.smallSample) plays one trial and skips the statistics.
		local small = testsApi.smallSample()
		local count = small and 1 or typeName == "Bat" and 16 or 8
		trials(typeName, count, 2, 1, nil, fixtures.repeated("idle", 24), function(index, bat)
			if index == 1 then
				last = { x = 2, y = 1 }
				hp = 12
				actedLast = false
			end
			local x, y = bat.position.x, bat.position.y
			local hit = health() < hp
			if hit then
				heal()
			end
			hp = health()
			if index == 24 then
				s.outcomes[x .. "," .. y] = true
			end
			local moved = x ~= last.x or y ~= last.y
			-- A Bat rests on the action after it moves or hits.
			if typeName == "Bat" and actedLast then
				assert(not moved and not hit, "a Bat acted on two actions in a row")
				actedLast = false
				return
			end
			actedLast = moved or hit
			if not hit then
				s.acts = s.acts + 1
			end
			if moved then
				local dx, dy = x - last.x, y - last.y
				assert(math.max(math.abs(dx), math.abs(dy)) == 1, "a bat steps one tile")
				s.moves = s.moves + 1
				if dx ~= 0 and dy ~= 0 then
					s.diagonal = s.diagonal + 1
				end
				local before = last.x * last.x + last.y * last.y
				if x * x + y * y < before then
					s.closer = s.closer + 1
				end
				local free, closer = 0, 0
				for _, d in ipairs(bat.ai.directions) do
					local tx, ty = last.x + DX[d], last.y + DY[d]
					if not (tx == 0 and ty == 0) then
						free = free + 1
						if tx * tx + ty * ty < before then
							closer = closer + 1
						end
					end
				end
				s.expectedCloser = s.expectedCloser + closer / free
			end
			last = { x = x, y = y }
		end, function()
			for key, value in pairs(s) do
				if type(value) == "number" then
					testsApi.observe(key, value)
				end
			end
			if small then
				finish()
				return
			end
			assert(s.moves >= 0.95 * s.acts, "a bat steps on nearly every action")
			if typeName == "Bat3" then
				assert(s.diagonal >= 0.3 * s.moves, "a Bat3 often steps diagonally")
			else
				assert(s.diagonal == 0, typeName .. " never steps diagonally")
			end
			local ratio = s.closer / s.expectedCloser
			-- A bat that leaned toward the player would get closer on most
			-- steps, about twice the uniform share.
			assert(ratio > 0.7 and ratio < 1.3, "no lean toward the player, ratio " .. ratio)
			local distinct = 0
			for _ in pairs(s.outcomes) do
				distinct = distinct + 1
			end
			assert(distinct >= 4, "trials end in different places")
			finish()
		end)
	end)
end

-- Next to the player in the open, the player's tile is one pick among the
-- free tiles: a Bat or Bat2 hits on about a quarter of its actions, a Bat3 on
-- about an eighth, and it does not move when it hits.
for _, typeName in ipairs(TYPES) do
	asyncTest("batAdjacentHitChance" .. typeName, function(_, finish)
		local hits, total = 0, 0
		trials(typeName, 61, 1, 0, function()
			local player = fixtures.player()
			if player.invincibility then
				player.invincibility.remainingTurns = 0
			end
		end, { "idle" }, function(_, bat, trial)
			-- The level's first beat hurts nobody.
			if trial == 1 then
				return
			end
			total = total + 1
			if health() < 12 then
				hits = hits + 1
				assertAt(bat, 1, 0, "a bat attacks from where it stands")
			end
		end, function()
			testsApi.observe("hits", hits .. "/" .. total)
			if typeName == "Bat3" then
				assert(hits >= 1 and hits <= 16, "about one in eight")
			else
				assert(hits >= 5 and hits <= 27, "about one in four")
			end
			finish()
		end)
	end)
end

-- The first level's own bats move the same way once the player comes close:
-- one orthogonal tile at a time, and never on two actions in a row.
asyncTest("batNaturalBatsMoveTheSame", function(_, finish)
	fixtures.openArena(12, "Bat")
	local watched = {}
	for entity in Entities.entitiesWithComponents({ "ai" }) do
		if entity.name == "Bat" then
			watched[entity.id] = { entity = entity, x = entity.position.x, y = entity.position.y }
		end
	end
	assert(next(watched), "the first level has Bats near the start")
	local actions = { "up", "up", "up", "up", "up", "left" }
	for _ = 1, 12 do
		table.insert(actions, "idle")
	end
	local moves = 0
	testsApi.play(actions, function(index)
		for _, w in pairs(watched) do
			local x, y = w.entity.position.x, w.entity.position.y
			if x ~= w.x or y ~= w.y then
				assert(math.abs(x - w.x) + math.abs(y - w.y) == 1, "one orthogonal tile")
				assert(w.movedAt ~= index - 1, "a Bat does not move on two actions in a row")
				w.movedAt = index
				moves = moves + 1
			end
			w.x, w.y = x, y
		end
	end, function()
		testsApi.observe("moves", moves)
		assert(moves >= 10, "the level's Bats moved")
		finish()
	end)
end)
