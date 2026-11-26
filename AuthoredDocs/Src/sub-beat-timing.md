# Sub-beat timing

For players. When within a beat your press lands, and the few things that run
on the clock rather than on the beat: trap fuses and the stairs. Playing
Cadence on 1-1, whose music has a beat every 0.52 s; times are seconds of
music.

## Pressing within a beat

* One press per beat always counts, wherever it falls between two beats.
* A second press soon after the first is a missed beat: you do not act.
  Pressed on the beat, a second press up to 0.29 s later is still a miss;
  from 0.31 s it counts for the next beat.

## Trap fuses

A spike trap ([traps.md](./traps.md#spikes)) strikes 0.2 s after you land on
it, wherever in the beat you stepped. A trapdoor has the same fuse.

* Acting during the fuse springs the trap at once, and it still gets you:
  stepping back off spikes still costs 4, and stepping off a trapdoor still
  drops you.
* Eating food or casting the heal spell (`SpellHeal`) during the fuse blocks
  the spikes: each makes you invincible for a beat, and that takes hold
  before the spikes strike. The heal spell works even on cooldown, so the
  spikes cost you the cast's net 1 health instead of 4.
* To fit that press inside the fuse, step onto the spikes late, 0.15 to
  0.25 s after the beat, and press about 0.33 s after the beat, which counts
  for the next one. Stepped on the beat, the spikes strike before a press
  can count for the next beat.

## The stairs

Stepping onto unlocked stairs ([stairs-and-levels.md](./stairs-and-levels.md))
ends the level 0.6 s later, wherever in the beat you stepped.

* Nothing hurts you in those 0.6 s.
* The heal spell cast up to 0.4 s after the step heals you for free, even on
  cooldown, when it would cost 1 health. The cast must count for the next
  beat, so step on the beat or late, then cast early on the next one. A press
  later than that does nothing.
