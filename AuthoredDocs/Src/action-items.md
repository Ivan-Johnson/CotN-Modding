# Action items and spells

For players. Items used with `item1` and spells cast with `spell1`, measured as
Cadence in no-beat mode on CotN 4.2.1.

* `BloodDrum` ("Takes health, increases damage"): using it cost 1 health
  (`damage_taken source=BloodDrum`) and gave +999 damage for 1 turn. Used with
  `WeaponTitaniumBroadsword` on the next beat, a swing killed a `Minotaur2`
  that had 3 of 5 health left and a `Skeleton2` behind it, each taking 1001
  damage. The `Minotaur2` was adjacent and had not yet attacked.
* `FamiliarIceSpirit` ("Freeze enemies"): using it and then a direction spawns
  a `FollowerSnowbro` on that tile. It follows the player and freezes what it
  touches for about 2 turns. A `FollowerSnowbro` standing on a `Dragon`'s tile
  blocked the player's melee: 4 or more dagger hits did no damage and the
  dragon killed the player.
* `SpellEarth` ("Raise walls", `spell1`) raises `EarthWall` on the 8 tiles
  around the player. The walls held for 30+ beats and the shovel destroys
  them; see [king-conga.md](./king-conga.md).
