# Bombs

For players. Measured as Cadence in no-beat mode on CotN 4.2.1.

* The starting `Bomb` (the `bomb` action) drops a lit bomb on the player's
  tile and is spent. A `Bomb` or `Bomb3` pickup adds to the inventory. With no
  bomb left the action logs `multiplier_lost(because=an invalid action)`.
* The bomb explodes on the third beat after the placing beat: placed on beat
  1, the blast came with the idle on beat 4 (once; another test counted the
  fourth action including the placing one, which agrees).
* The blast covers the 3 by 3 around the bomb. It dug the `DirtWall`s directly
  above it and up-left of it, hit a `Crate3` for 1 damage, and did 4 damage to
  a `Minotaur`. It also did 4 damage to a player left 1 tile from it in a King
  Conga attempt.
* It clears `StoneWall` as well as `DirtWall`: a bomb placed in a dead-end
  corridor opened a way into a guarded stairs room that the basic shovel could
  not.
* It destroys the coins lying on its tiles: a bomb in a corridor where enemies
  came in a column killed a `Ghost` and destroyed `ResourceCoin30` and
  `ResourceCoin10`.
* A bomb breaks crates, which melee does not; see
  [chests-and-loot.md](./chests-and-loot.md).

## Timing against a charging enemy

* A `Minotaur` charging along the player's row at one tile a beat, 5 tiles
  away, was undamaged when the player placed the bomb at once and retreated
  2 tiles: it was still 2 tiles from the bomb when it went off, and the blast
  came before its move. Placing the bomb one beat later (a leading `idle`)
  left it 1 tile from the bomb, and it died. In both tries it never hit the
  player.
* A bomb kills a `Dragon` with no damage taken: place it when the dragon is 2
  tiles from the bomb's tile, walk 2 or 3 tiles away, and the dragon walks into
  the blast (4 damage). Done once on 1-1.
