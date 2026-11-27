# Glass shop

For players. The secret shop that sells glass gear at half price, what glass
gear costs you later, and its shopkeeper. Applies to Cadence in Single Zone
mode. Finding the shop, its cracked wall and the travel rune that takes you
there and back: [secret-shops.md](./secret-shops.md).

## The room

* A closed room of 5 by 7 tiles, walled with shop wall. The Glass
  Shopkeeper (`Shopkeeper3`) stands one tile from the back wall, and the
  travel rune back to the level is 4 tiles in front of him.
* Three glass wares lie in a row two tiles in front of him, such as Glass
  Armor (`ArmorGlass`), a Glass Shovel (`ShovelGlass`) and a Glass
  Broadsword (`WeaponGlassBroadsword`).

## Buying

* Each ware is priced in gold at half what the regular shop charges for it,
  rounded up: Glass Armor 25, a Glass Shovel 10, a Glass Broadsword 38.
* Buying works as in the regular shop ([shops.md](./shops.md#buying)): walk
  onto a ware with at least its price in gold. With less, the move fails and
  you keep your gold. The item a ware replaces, such as your dagger, stays on
  that tile, free to take back.

## What glass costs you

Glass gear breaks, leaving you without it:

* Glass Armor takes all the damage of the next hit, such as a bomb's blast,
  then shatters.
* A glass weapon shatters the first time you take damage, leaving a Glass
  Shard on your tile: [weapons.md](./weapons.md#materials).
* A Glass Shovel digs one shop wall, then shatters:
  [digging.md](./digging.md#shovels).

## The Glass Shopkeeper

* Until he is provoked, attacking him with your weapon does nothing, and he
  never attacks you.
* He has 8 health. A bomb that hurts him takes 4 and provokes him, and so
  does a thrown dagger, which takes 1.
* Provoked, he hits for 20 every second beat while beside you. Your weapon
  now hurts him: a dagger takes 1 per hit. His wares keep their price while
  he lives.
* Killed, he drops his Glass Jaw (`HeadGlassJaw`) where he stood, and the
  wares left are free.
