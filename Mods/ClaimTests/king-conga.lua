local Boss = require "necro.game.level.Boss"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Entities = require "system.game.Entities"
local GameSession = require "necro.client.GameSession"
local Inventory = require "necro.game.item.Inventory"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local Tile = require "necro.game.tile.Tile"

-- Optional dependency on TestFramework; see HelloWorld/tests.lua.
local ok, testsApi = pcall(require, "TestFramework.api")
if not ok then
	return
end
local fixtures = require "TestFramework.fixtures"

-- Each test plays Cadence in no-beat mode on the 1-4 boss level, with the
-- boss forced to King Conga and the room's other enemies (bats, ghosts)
-- removed. The player starts at (0,0) below the boss room; the throne is at
-- (0,-17), and the first step onto y = -7 starts the fight.

local THRONE_X, THRONE_Y = 0, -17

local forceKingConga = false
event.levelGenerate.add("ClaimTestsKingCongaBoss", {}, function(ev)
	if forceKingConga and ev.options and ev.options.boss then
		ev.options.boss = Boss.Type.KING_CONGA
	end
end)

-- Goes to level 4 as Cadence. A run keeps the character of the run before
-- it, so another character starts a new run first. A level change from the
-- first level takes effect late, so go through level 2 and poll.
local function goToBossLevel(andThen)
	forceKingConga = true
	local restart = fixtures.player().name ~= "Cadence"
	if restart then
		Player.setCharacterType(1, "Cadence")
		testsApi.afterTicks(100, function()
			GameSession.start({ mode = GameSession.Mode.SingleZone })
		end)
	end
	testsApi.afterTicks(restart and 800 or 1, function()
		assert(fixtures.player().name == "Cadence", "playing as " .. fixtures.player().name)
		GameSession.goToLevel(2)
		testsApi.afterTicks(400, function()
			GameSession.goToLevel(4)
			local function whenLoaded()
				if CurrentLevel.getNumber() ~= 4 then
					testsApi.afterTicks(10, whenLoaded)
					return
				end
				forceKingConga = false
				testsApi.afterTicks(300, andThen)
			end
			whenLoaded()
		end)
	end)
end

local function each(test)
	local list = {}
	for entity in Entities.entitiesWithComponents({ "position" }) do
		if test(entity) then
			table.insert(list, entity)
		end
	end
	return list
end

local function king()
	return each(function(e)
		return e.name == "KingConga" or e.name == "KingCongaAngry"
	end)[1]
end

local function zombies(name)
	return each(function(e)
		return e.name == name or (not name and (e.name == "ZombieSnake" or e.name == "ZombieSnakeYellow"))
	end)
end

local function zombieAt(x, y)
	for _, zombie in ipairs(zombies()) do
		if zombie.position.x == x and zombie.position.y == y then
			return zombie
		end
	end
end

local function killZombies(filter)
	for _, zombie in ipairs(zombies()) do
		if not filter or filter(zombie) then
			Object.kill(zombie, fixtures.player())
		end
	end
end

local function removeOtherEnemies()
	local doomed = {}
	for entity in Entities.entitiesWithComponents({ "ai" }) do
		if not (entity.name:find("KingConga", 1, true) or entity.name:find("ZombieSnake", 1, true)) then
			table.insert(doomed, entity.id)
		end
	end
	for _, id in ipairs(doomed) do
		Object.delete(Entities.getEntityByID(id))
	end
end

local health = fixtures.health
local assertAt = fixtures.assertAt

local function assertCalmOnThrone(what)
	local k = king()
	assert(k.name == "KingConga", what .. ": expected him calm, got " .. k.name)
	assertAt(k, THRONE_X, THRONE_Y, what)
end

local function assertAngry(what)
	assert(king().name == "KingCongaAngry", what .. ": expected him angry, got " .. king().name)
end

-- sequence({ "up", 3 }, { "idle", 1 }) is { "up", "up", "up", "idle" }.
local function sequence(...)
	local list = {}
	for _, part in ipairs({ ... }) do
		for _ = 1, part[2] do
			table.insert(list, part[1])
		end
	end
	return list
end

local function concat(...)
	local list = {}
	for _, part in ipairs({ ... }) do
		for _, action in ipairs(part) do
			table.insert(list, action)
		end
	end
	return list
end

-- Left and right in turn, so the player moves every beat without going far.
local function wiggle(count)
	local list = {}
	for index = 1, count do
		table.insert(list, index % 2 == 1 and "left" or "right")
	end
	return list
end

-- Up 9 times: one bump opens the start room's door, the 8th step reaches
-- y = -7 and starts the fight, and the 9th stands the player at (0,-8).
local ENTER = 9

-- Plays actions, running checks[index] after each, then after(state, finish)
-- if given.
local function bossScene(name, prepare, actions, checks, after)
	testsApi.registerTest({
		name = name,
		character = "Cadence",
		noBeat = true,
		async = true,
		timeoutTicks = 30000,
		onLoad = function(_, finish)
			goToBossLevel(function()
				removeOtherEnemies()
				fixtures.player().health.maxHealth = 100
				fixtures.player().health.health = 100
				local state = prepare and prepare() or {}
				testsApi.play(actions, function(index)
					if checks[index] then
						checks[index](state)
					end
				end, function()
					if after then
						after(state, finish)
					else
						finish()
					end
				end)
			end)
		end,
	})
end

-- The room: the King on his throne and two lines of eight zombies, each led
-- by a yellow one; stats. Nothing moves, and idling does not anger him, until
-- the player steps into the room, which seals the entrance behind them.
bossScene("kingCongaRoomWaitsForThePlayer", function()
	local k = king()
	assertCalmOnThrone("at the start")
	local throne = each(function(e)
		return e.name == "KingCongaThrone"
	end)[1]
	assertAt(throne, THRONE_X, THRONE_Y, "the throne")
	assert(k.health.maxHealth == 2 and k.innateAttack.damage == 3, "King Conga: 2 HP, 3 damage")
	assert(#zombies("ZombieSnakeYellow") == 2, "two yellow leaders")
	assert(#zombies("ZombieSnake") == 14, "seven followers each")
	for _, zombie in ipairs(zombies()) do
		assert(zombie.health.maxHealth == 1 and zombie.innateAttack.damage == 2, "zombie: 1 HP, 2 damage")
		assert(zombie.position.y > THRONE_Y and zombie.position.y <= THRONE_Y + 2, "zombies start beside the throne")
	end
	local heads = {}
	for _, head in ipairs(zombies("ZombieSnakeYellow")) do
		table.insert(heads, { entity = head, x = head.position.x, y = head.position.y })
	end
	return { heads = heads }
end, sequence({ "up", 5 }, { "idle", 3 }, { "up", 3 }), {
	[8] = function(state)
		for _, head in ipairs(state.heads) do
			assertAt(head.entity, head.x, head.y, "idling outside the room")
		end
		assertCalmOnThrone("idling outside the room")
	end,
	[10] = function()
		assert(fixtures.tileName(0, -6) ~= "BossWall", "the entrance is open")
	end,
	[11] = function(state)
		assert(fixtures.player().position.y == -7, "the player stepped into the room")
		assert(fixtures.tileName(0, -6) == "BossWall", "stepping in seals the entrance")
		for _, head in ipairs(state.heads) do
			assertAt(head.entity, head.x, head.y + 1, "the leaders set off")
		end
	end,
})

-- While the player never idles or fails an action, he stays on his throne,
-- even while a zombie hits the player. The leaders come one tile every second
-- beat and the others follow in their footsteps.
bossScene("kingCongaStaysSeatedWhileYouKeepMoving", nil, concat(sequence({ "up", ENTER }), wiggle(14)), {
	[ENTER] = function(state)
		state.head = zombies("ZombieSnakeYellow")[1]
		state.x, state.y = state.head.position.x, state.head.position.y
	end,
	[ENTER + 1] = function(state)
		assertAt(state.head, state.x, state.y + 1, "the leader steps toward the player")
		local follower = zombieAt(state.x, state.y)
		assert(follower and follower.name == "ZombieSnake", "the next zombie steps into the leader's old tile")
	end,
	[ENTER + 2] = function(state)
		assertAt(state.head, state.x, state.y + 1, "the leader waits a beat")
	end,
	[ENTER + 3] = function(state)
		assertAt(state.head, state.x, state.y + 2, "the leader moves again")
	end,
	[ENTER + 12] = function()
		assert(health() == 100, "no hit yet")
	end,
	[ENTER + 13] = function()
		assert(health() == 98, "a leader hits for 2")
	end,
	[ENTER + 14] = function()
		assertCalmOnThrone("after 14 moves and a zombie's hit")
	end,
})

-- An idle angers him. He then comes one tile a beat, hits for 3 on the beat
-- after he arrives and every second beat after that.
bossScene("kingCongaIdleAngersHim", nil, sequence({ "up", ENTER }, { "idle", 12 }), {
	[ENTER] = function()
		assertCalmOnThrone("before the idle")
	end,
	[ENTER + 1] = function()
		assertAngry("after one idle")
		assertAt(king(), 0, THRONE_Y + 1, "he leaves the throne")
	end,
	[ENTER + 2] = function()
		assertAt(king(), 0, THRONE_Y + 2, "one tile a beat")
	end,
	[ENTER + 8] = function()
		assertAt(king(), 0, -9, "next to the player")
		assert(health() == 100, "no hit as he arrives")
	end,
	[ENTER + 9] = function()
		assert(health() == 97, "hits for 3 the beat after he arrives")
	end,
	[ENTER + 10] = function()
		assert(health() == 97, "no hit on the next beat")
	end,
	[ENTER + 11] = function()
		assert(health() == 94, "hits every second beat")
	end,
})

-- A failed action (bumping a wall) angers him too, and he moves diagonally.
bossScene("kingCongaFailedActionAngersHim", nil, concat(sequence({ "up", ENTER }), { "right", "left", "right" }), {
	[ENTER] = function()
		Tile.setType(1, -8, "StoneWall")
		assertCalmOnThrone("before the bump")
	end,
	[ENTER + 1] = function()
		assert(fixtures.player().position.x == 0, "the bump failed")
		assertAngry("after the bump")
		assertAt(king(), 0, THRONE_Y + 1, "he leaves the throne")
	end,
	[ENTER + 2] = function()
		assertAt(king(), -1, THRONE_Y + 2, "a diagonal step toward the player")
	end,
	[ENTER + 3] = function()
		assertAt(king(), 0, THRONE_Y + 3, "a diagonal step back")
	end,
})

-- While a zombie lives, hits do him no damage: hit off the throne, he goes
-- back to it calm; hit on it, he gets angry. Standing next to him while he
-- sits there is safe.
bossScene("kingCongaShieldedWhileZombiesLive", nil, sequence({ "up", ENTER }, { "idle", 1 }, { "up", 10 }), {
	[ENTER + 5] = function()
		assertAngry("before the hit")
		assertAt(king(), 0, -13, "in front of the player")
		assertAt(fixtures.player(), 0, -12, "below him")
	end,
	[ENTER + 6] = function()
		assert(king().health.health == 2, "the hit did no damage")
		assertCalmOnThrone("after the hit")
	end,
	[ENTER + 10] = function()
		assertAt(fixtures.player(), 0, THRONE_Y + 1, "next to the throne")
		assert(health() == 97, "sitting, he does not hit")
	end,
	[ENTER + 11] = function()
		assert(king().health.health == 2, "a hit on the throne does no damage")
		assertAngry("after a hit on the throne")
		assertAt(king(), THRONE_X, THRONE_Y, "he stays on the throne")
	end,
})

-- The action that attacks King Conga if he is next to the player, or else
-- steps toward him, along the longer axis first.
local function chaseAction()
	local k = king()
	local p = fixtures.player().position
	local dx, dy = k.position.x - p.x, k.position.y - p.y
	if math.abs(dx) + math.abs(dy) == 1 or math.abs(dx) >= math.abs(dy) and dx ~= 0 then
		if dx ~= 0 then
			return dx > 0 and "right" or "left"
		end
	end
	return dy > 0 and "down" or "up"
end

-- Kills every zombie as the player steps into the room, which angers him,
-- then chases him until the first hit lands and calls onHit(hpBefore). His
-- path varies between runs, so the beat of the hit does too.
local function chaseScene(name, prepare, onHit)
	bossScene(name, prepare, sequence({ "up", ENTER }), {
		[ENTER - 1] = function()
			killZombies()
		end,
		[ENTER] = function()
			assertAngry("with every zombie dead")
		end,
	}, function(_, finish)
		local beats = 0
		local function step()
			beats = beats + 1
			assert(beats <= 30, "no hit landed in 30 beats")
			local hpBefore = king().health.health
			testsApi.play({ chaseAction() }, nil, function()
				local k = king()
				if k and k.health.health == hpBefore then
					step()
				else
					onHit(hpBefore)
					finish()
				end
			end)
		end
		step()
	end)
end

-- Then a hit hurts him, and one that does not kill sends him away.
chaseScene("kingCongaHurtOnceTheZombiesAreDead", nil, function(hpBefore)
	local k = king()
	assert(hpBefore == 2 and k.health.health == 1, "the dagger hit does 1 damage")
	local p = fixtures.player().position
	local distance = math.max(math.abs(k.position.x - p.x), math.abs(k.position.y - p.y))
	assert(distance >= 3, "he jumps away, got distance " .. distance)
end)

-- Killing him opens a path behind the throne to the stairs. He drops no gold.
chaseScene("kingCongaDeathOpensTheStairs", function()
	Inventory.grant("WeaponTitaniumDagger", fixtures.player())
	assert(fixtures.tileName(0, -20) ~= "Stairs", "no stairs yet")
	return {}
end, function()
	assert(king() == nil, "a 2-damage hit kills him")
	assert(Boss.isDead(), "the boss fight is won")
	assert(fixtures.tileName(0, -20) == "Stairs", "stairs behind the throne")
	for y = -19, -13 do
		assert(Tile.getInfo(0, y).isFloor, "a clear path to the stairs at y = " .. y)
	end
	assert(fixtures.player().goldCounter.amount == 0, "no gold")
	for item in Entities.entitiesWithComponents({ "item" }) do
		assert(not (item.position and item.position.y < -6), "nothing dropped: " .. item.name)
	end
end)

-- When a leader dies, the next zombie in its line takes over.
bossScene("kingCongaNextZombieLeads", nil, sequence({ "up", ENTER }, { "left", 1 }), {
	[ENTER] = function()
		killZombies(function(zombie)
			return zombie.name == "ZombieSnakeYellow" and zombie.position.x < 0
		end)
	end,
	[ENTER + 1] = function()
		assert(#zombies() == 15, "only the leader died")
		local leaders = zombies("ZombieSnakeYellow")
		assert(#leaders == 2, "a new leader replaces the dead one")
	end,
})
