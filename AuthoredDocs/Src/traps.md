# Traps

For players. Traps seen in zone one, measured as Cadence in no-beat mode on
CotN 4.2.1.

* `SpikeTrap`: stepping onto one cost 4 health. A `SpikeTrap` and a
  `Sync_AutoSpikeTrap` each killed a `Slime3` that walked onto them.
* `Sync_AutoSpikeTrap` ("Automatic Spike Trap", 4 damage): its sprite frame
  flips every beat, but stepping onto it did no damage at once. The hit of 4
  came 3 actions after stepping on (5 trials; once it came at the 2nd
  action, as the player stepped off) and did not repeat in 12 more beats on
  the tile. Stepping off during the delay did not avoid it. Natural trap in a
  dug-out vault, no-beat mode; what restarts the cycle was not found beyond
  stepping on again, which hit again, and a hit at 4 health killed the
  player.
* `BounceTrapUp` (and presumably Down, Left and Right, which were listed but
  not stepped on): walking onto it moved the player one more tile in its
  direction in the same action, from (7,-1) via the trap at (8,-1) to
  (8,-2). Entering it against its direction, from (8,-2) down, left the
  player where they started. It kept the coin multiplier (x3 until an
  `idle`).
* `Trapdoor`: stepping on one drops the player to the next level with health
  unchanged; see [stairs-and-levels.md](./stairs-and-levels.md).
* Also seen, with their effects untested: `BombTrap`, `BounceTrapLeft`,
  `BounceTrapDown`, `BounceTrapOmni`, `TempoUpTrap` and `TempoDownTrap`.
* `Sync_WallSpike`: set in a wall; digging it out costs 1 health
  ([digging.md](./digging.md)).
