# Ghost

For players. Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Ghost` | 1 | 1 | 2 | 1, while it is chasing; a frozen ghost cannot be hurt |

A ghost only moves while you have your back to it.

* **Frozen in front or beside you.** Picture a line through you at right angles
  to the way you face. A ghost on your side of it, or on it, is frozen: it
  never moves or attacks. Dagger bumps and bomb blasts do nothing to it; only
  the Dagger of Phasing hurts it ([weapons.md](./weapons.md#materials)).
* **Chasing from behind.** A ghost past that line, diagonals included, follows
  one tile a beat. It steps horizontally first, even when it is farther away
  vertically, and steps vertically if a wall or an enemy blocks the horizontal
  step. It does not walk around walls.
* **When it decides.** A ghost works out whether it is frozen or chasing only
  when you move to a new tile, using the way that move made you face. Attacking,
  digging and bumping stone turn you, and idling and using an item do not, but
  none of them changes any ghost ([controls.md](./controls.md#facing)). So a ghost
  that was chasing keeps chasing wherever it ends up, even beside you, until
  your next move, and a frozen ghost that you turn your back on stays frozen
  until you move.
* **Waking.** A ghost sleeps until you come within two tiles of it with
  nothing in the way. Once awake it stays awake at any distance.
* **Attacking.** A chasing ghost next to you hits for 2 on the beat after it
  arrives and every second beat after that. Usually that is from behind, but a
  wall or an enemy that blocks its horizontal step can push it onto your side
  line while it is still chasing, and it then hits from beside you. It spends
  its beats following while you keep moving, so it cannot hit you then.
* **Killing.** Hit a chasing ghost, which is usually behind you: a dagger needs
  it adjacent, a trident reaches two tiles. That includes a dagger bump toward
  a chasing ghost beside you. A bomb also kills a chasing ghost. A ghost you
  already face is frozen, so you only get the kill on the turn that faces it.
* **Reward.** A kill counts for the coin multiplier, and the ghost's
  [base gold](./coin-multiplier.md#gold-per-kill) is 2.
