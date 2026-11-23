# Ghost

For players. Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Ghost` | 1 | 1 | 2 | 1, only while it is behind you |

A ghost only moves while you have your back to it.

* **Frozen in front or beside you.** Picture a line through you at right angles
  to the way you face. A ghost on your side of it, or on it, never moves or
  attacks. Dagger bumps and bomb blasts do nothing to it; only the Dagger of
  Phasing hurts it ([weapons.md](./weapons.md#materials)). The
  way you face is set by [what you press](./controls.md#facing); standing
  still keeps it.
* **Chasing from behind.** A ghost past that line, diagonals included, follows
  one tile a beat. It steps horizontally first, even when it is farther away
  vertically, and steps vertically if a wall or an enemy blocks the horizontal
  step. It does not walk around walls.
* **Waking.** A ghost sleeps until you come within two tiles of it with
  nothing in the way. Once awake it stays awake at any distance.
* **Attacking.** Adjacent behind you, it hits for 2 on the beat after it
  arrives and every second beat after that. It spends its beats following while
  you keep moving, so it cannot hit you then.
* **Killing.** Turn to face a ghost that is behind you and hit it: a dagger
  needs it adjacent, a trident reaches two tiles. A bomb also kills a chasing
  ghost. A ghost you already face is frozen, so you only get the kill on the
  turn that faces it.
* **Reward.** A kill counts for the coin multiplier, and the ghost's
  [base gold](./coin-multiplier.md#gold-per-kill) is 2.
