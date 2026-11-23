# King Conga

For players. The 1-4 boss seen in one single-zone run as Cadence with 2
health and `Sync_WeaponTitaniumTrident`, in no-beat mode on CotN 4.2.1. The
level-1-4 boss is random: other runs had `Fortissimole` and `Deathmetal`,
which were not fought. Level layout: [stairs-and-levels.md](./stairs-and-levels.md).

## The room

* `KingConga` (2 HP, damage 3) sits on a `KingCongaThrone` at (0,-17).
* Two 8-snake `ZombieSnake` lines (1 HP, damage 2, speed 2, each led by a
  `ZombieSnakeYellow`) sit at y = -16 and -17 on either side.
* Two `Bat`, one `Bat2` and two `Ghost` are also in the room. The start room
  was empty.
* The first step past y = -7 sealed the entrance with `BossWall` at y = -6,
  and the snake heads headed down the room, one tile every second beat.

## The fight

* A failed press at the throne from the tile below logged
  `multiplier_lost(because=a failed action)`, and the king became
  `KingCongaAngry` (speed 1) after one idle beat next to him. That is the only
  observation tying a missed beat to the fight.
* With both snake lines alive, a trident hit, a trident hit through
  `BloodDrum` did 0 damage to `KingCongaAngry`. A `Crate2`
  also took 0 from the trident, so 0 is not special to bosses. In a later
  attempt the player killed every snake first (one hit each, 2 damage) and
  then one trident hit killed him (2 damage), which won the run. Whether the
  live snake lines made him immune is not isolated, since the earlier 0-damage
  tests were also done next to the throne.
* `KingCongaAngry` walks straight down column 0, one tile per beat: in a
  tracked replay he was at (0,-16) after beat 1 and (0,-9) after beat 8, and
  killed a player left standing at (0,-8) (3 damage) around beat 9 to 11. The
  snake heads walk down at x = -3 and 3, one tile every 2 beats, then
  converge; they reach the player's row after about 20 beats.
* Stepping away from the throne made him step next to the player; after the
  0-damage hit he went back to the throne, and a bomb at the throne made him
  jump to (6,-15). He killed the player (3 damage) on the 3rd beat the player
  spent next to him.

## What worked

`SpellEarth` (`spell1`) raised `EarthWall` on the 8 tiles around the player at
(0,-8). The walls held for 30+ beats: the King stopped at (0,-10) and the
snake heads at (-2,-8) and (2,-8). Pressing toward a wall with the shovel
destroyed it, after which the next snake head stepped adjacent and could be
killed, one hit each, from inside the box. With one wall opened per side, both
lines were cleared with no damage taken; the King then stepped into the
opening dug on his side and died to one hit. See also
[action-items.md](./action-items.md).
