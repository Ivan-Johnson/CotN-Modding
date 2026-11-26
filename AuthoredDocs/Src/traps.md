# Traps

For players. What each floor trap does to whoever lands on it. A bomb's blast
destroys traps ([bombs.md](./bombs.md)); spikes set in walls are covered in
[digging.md](./digging.md).

Every trap but the bounce traps acts a moment after you land on it, not as
you land.

## Spikes

* **Spike trap** (`SpikeTrap`): hits for 4 (two hearts) when you land on it.
  Standing on it afterwards costs nothing more; step off and back on and it
  hits again. Enemies take the same 4 each time they land on one.
* **Automatic spike trap** (`Sync_AutoSpikeTrap`): springs on its own rather
  than when stepped on, hitting whoever stands on it for 4, so the hit can
  come a few beats after you step on. Once it has hit you, standing still on
  it is safe; step off and back on and it can hit you again.

## Bounce traps

A bounce trap pushes you one more tile in the same action. It pushes enemies
that land on it too.

* An arrow trap (`BounceTrapUp`, `BounceTrapLeft`, ...) pushes you along its
  arrow, whichever way you entered: walking right onto an up arrow leaves
  you one tile up from the trap, and walking into the arrow sends you back to
  the tile you came from. Diagonal arrows, such as `BounceTrapUpRight`, push
  diagonally.
* An omni trap (`BounceTrapOmni`) pushes you on in the direction you were
  moving.
* With a wall in the way you stay on the trap.
* The push sets off a trap you land on: one bounce trap can push you onto the
  next, and a push onto spikes hurts.
* A bounce keeps your coin multiplier
  ([coin-multiplier.md](./coin-multiplier.md)).

## Other traps

* **Bomb trap** (`BombTrap`): drops a lit bomb on itself, which goes off like
  one of yours ([bombs.md](./bombs.md)): 4 damage if you are still within one
  tile, nothing from two tiles away. The blast destroys the trap.
* **Trapdoor** (`Trapdoor`): drops you to the next level a few seconds later,
  with your health and items unchanged
  ([stairs-and-levels.md](./stairs-and-levels.md)).
* **Tempo traps**: `TempoUpTrap` speeds the music up to 1.125 times its speed
  and `TempoDownTrap` slows it to 0.875 times, for a few seconds, before it
  returns to normal.
* **Confusion trap** (`ConfusionTrap`): reverses your directions for about ten
  beats: right moves you left and up moves you down.
* **Scatter trap** (`ScatterTrap`): knocks your weapon, shovel, armor,
  headgear, ring, torch and food out of your inventory onto the tiles within
  two of the trap. Bombs and spells stay.
* **Teleport trap** (`TeleportTrap`): sends you to another spot on the level.
