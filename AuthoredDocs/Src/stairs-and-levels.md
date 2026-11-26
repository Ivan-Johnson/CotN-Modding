# Stairs and levels

For players. How a single-zone run as Cadence moves from 1-1 through 1-3 to
the boss on 1-4. Each level's layout is random.

## Stairs

* On 1-1, 1-2 and 1-3 the stairs start locked (`LockedStairs`), with a
  miniboss standing on them: a `BatMiniboss`, `Minotaur` or `Dragon` on 1-1
  and 1-2, a `Minotaur2` or `Dragon2` on 1-3. How to fight each:
  [minibosses.md](./minibosses.md).
* You can stand on locked stairs, but they take you nowhere.
* Killing the miniboss unlocks the stairs at once. If you are standing on
  them when it dies, you go down without another move.
* Walking onto unlocked stairs takes you to the next level. You keep your
  health, gold, items and coin multiplier
  ([coin-multiplier.md](./coin-multiplier.md)).

## Trapdoors

* A `Trapdoor` drops you to the next level, locked stairs or not, with your
  health and gold unchanged. It ends the coin multiplier's chain
  ([coin-multiplier.md](./coin-multiplier.md)).
* Some of 1-1 to 1-3 hold one or more, at random spots; 1-4 has none. One on
  1-3 drops you straight to the boss.

## 1-4, the boss level

* You start in a small walled room with no enemies. Its exit is a row of three
  doors at the top (y = -6), opening onto a row of `PreBossBarrier`s (y = -7)
  at the foot of the boss room.
* Stepping onto the barriers' row walls the doorway off with `BossWall`
  behind you: there is no way back to the start room.
* The boss is one of five, at random: King Conga (`KingConga`, see
  [king-conga.md](./king-conga.md)), Death Metal (`Deathmetal`), Deep Blues
  (`King`), Coral Riff (`Coralriff`) or Fortissimole (`Fortissimole`).

## Shops

See [shops.md](./shops.md).
