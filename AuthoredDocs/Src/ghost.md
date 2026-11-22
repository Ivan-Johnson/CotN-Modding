# Ghost

For players. How this was measured: [enemies.md](./enemies.md).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Ghost` | 1 | 1 | 2 | 1, only on the action that turns the player to face it |

* A `Ghost` reacts to which way the player faces. It moves toward the player,
  one tile a beat, x first, only while the player faces away from it, and
  stands still while the player faces it.
* Facing away means the ghost is behind the player: after the player moved up,
  a ghost at the lower right closed in; after the player moved down with the
  ghost level to the right, it stayed. It keeps closing in while the player
  idles, because the facing persists.
* An adjacent `Ghost` hits for 2 on a beat when the player faces away.
* Pressing toward a ghost while already facing it did nothing at all in 6
  tries: no hit, no move. It dies on the action that turns the player to face
  it: facing left, then pressing right with the ghost adjacent on the right,
  killed it in one hit.
* A natural `Ghost` (level 1-3) sat in a one-tile cell behind a `DirtWall`.
  Adjacent and faced, it did nothing, and pressing toward it did nothing.
  After one step away (the ghost followed into the player's old tile), one
  press back toward it killed it with no damage taken.
* A trident does nothing to a ghost 1 or 2 tiles ahead while the player
  already faces it; see [weapons.md](./weapons.md).
* How a ghost moves from a diagonal position, and whether it keeps the x-first
  rule when blocked, is untested.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md) (not measured).
