# Action items and spells

For players. What Cadence's action items (used with `item1`) and spells (cast
with `spell1`) do. What the inputs cost in beats and coin chain, and the Earth
Spell's recharge: [controls.md](./controls.md). Where they are found:
[chests-and-loot.md](./chests-and-loot.md).

## Blood Drum (`BloodDrum`)

Each use costs 1 health and keeps the drum, so you can use it again. The cost
does not break the coin chain, and at 1 health it kills you.

The action on the next beat gets the boost; an idle beat in between wastes it:

* **An attack** does 999 more damage to every enemy it hits, each of a
  broadsword swing's three included.
* **A dig** is 3 stronger: even the starting shovel digs stone, catacomb and
  shop walls, though never an unbreakable wall ([digging.md](./digging.md)).

## Holy Water (`HolyWater`)

It hits every enemy in the 3 by 3 around you, diagonals included, for 5, and
heals you 2 (one heart) per enemy hit, up to your maximum. Enemies two tiles
away take nothing. It is used up, even with no enemy in range.

Its kills are yours: they extend the coin chain, each one counted
([coin-multiplier.md](./coin-multiplier.md)).

## Ice Spirit (`FamiliarIceSpirit`)

Use it, then press a direction: a snowman (`FollowerSnowbro`) appears on that
tile and you stay where you are. The item is spent; the snowman stays with you,
taking the same step as you each time you move.

An enemy that the snowman moves onto, or that walks into the snowman, is frozen
for 3 beats, and cannot attack. A frozen enemy still takes your hits, even
while the snowman shares its tile.

## Earth Spell (`SpellEarth`)

Every floor tile of the 8 around you becomes an earth wall (`EarthWall`); a
tile that is already a wall stays as it was. The walls stand for at least 30
beats, and enemies do not get through them. Opening one:
[digging.md](./digging.md).

An enemy on one of the 8 tiles is pushed one tile farther out, unhurt. If a
wall or another enemy blocks that tile, it dies instead, whatever its health,
and the kill is yours. Used against the boss: [king-conga.md](./king-conga.md).
