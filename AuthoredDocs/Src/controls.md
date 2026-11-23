# Controls

For players. What each input does as Cadence, and what it costs.

Every action takes one beat, and enemies move on the beat. The beat keeps
coming when you do not act: enemies still move, and your coin chain breaks
([coin-multiplier.md](./coin-multiplier.md)).

## Directions

The four directions move you one tile. Diagonal inputs are ignored: no beat
passes, and nothing changes, not even your facing or the coin chain.

Pressing toward something that blocks you acts on it instead of moving. You
stay where you are, and the action still takes a beat:

* **An enemy**: attacks it with your weapon ([weapons.md](./weapons.md)).
* **Dirt**: digs it, turning it into floor. The next press walks onto the
  tile, so a dug wall takes two actions ([digging.md](./digging.md)).
* **A door**: opens it, leaving floor. Going through takes a second press.
* **A chest**: opens it ([chests-and-loot.md](./chests-and-loot.md)).
* **A crate**: slides it one tile without breaking it.
* **Stone, or the edge of the level**: nothing happens, and the starting
  shovel does not dig stone. This is a failed action (below).

Walking onto an item picks it up. Picking up an action item while holding one
swaps them: the old one stays on that tile. Moving, attacking, digging,
opening, pushing and picking up all keep the coin chain.

## Facing

You face the way of your last direction press that did something: a move, an
attack, a dig, a door, a chest, a crate, or a bump into stone or the level's
edge. Facing decides which enemies a weapon hits and when a
[ghost](./ghost.md) moves.

Idling, using an item, casting a spell, placing a bomb, a failed use and an
ignored diagonal all leave your facing as it was.

## Idle, items, spells and bombs

* **Idle** passes a beat and breaks the coin chain.
* **Item (`item1`)** uses your action item. Food is an action item: `Food1`
  heals 2. A used item is gone. Using one keeps the chain.
* **Spell (`spell1`)** casts your spell. The Earth Spell is free once, then
  recharges after 10 kills; casting it before then costs 1 health each time.
  Casting keeps the chain.
* **Throw** followed by a direction throws a dagger, spear or trident
  ([weapons.md](./weapons.md)). Other weapons cannot be thrown: the direction
  just moves you.
* **Bomb (`bomb`)** drops a lit bomb on your tile and spends it
  ([bombs.md](./bombs.md)). Placing it keeps the chain.

## Failed actions

An action that cannot do anything is a failed action. It still passes a beat,
so enemies move, and it breaks the coin chain. Failed actions:

* pressing toward stone or the level's edge;
* using an item, a spell or a bomb you do not have.
