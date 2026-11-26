# Damage

For players. How much a hit costs, what stops it, and how much yours deal,
playing Cadence.

## Taking damage

* A hit costs its damage less your body armor's reduction, and always at
  least 1. Each enemy's damage is in its page's stats table
  ([enemies.md](./enemies.md#stats-tables)); armor values are in
  [chests-and-loot.md](./chests-and-loot.md#gear). A `Skeleton3` hits for 4,
  or 2 through chainmail; platemail still leaves a `Skeleton`'s hit at 1.

| Source | Armor reduces it | Stopped by |
|--------|------------------|------------|
| An enemy's hit | yes | |
| A bomb's blast, your own included ([bombs.md](./bombs.md)) | yes | Blast Helm (`HeadBlastHelm`) |
| A spike trap ([traps.md](./traps.md#spikes)) | yes: 4 becomes 2 through chainmail | Lead boots (`FeetBootsLead`) |
| The Blood Drum's cost ([action-items.md](./action-items.md)) | | nothing, not even invincibility |

## Invincibility

* **After a hit.** Nothing hurts you on the beat after you take a hit, so a
  blast that goes off on the beat after an enemy's hit costs nothing. A hit
  two beats later lands.
* **One hit per beat.** When several enemies hit you on the same beat, you
  lose only one hit. Enemies strike in a fixed order: minibosses
  ([minibosses.md](./minibosses.md)) first, then the rest, harder hitters
  first. So a `Skeleton` and a `Skeleton3` striking together cost 4, not 5.
* **Level start.** Nothing hurts you on the first beat of a level.
* **The Blood Drum.** Its cost lands while you are invincible, and it leaves
  you open: an enemy can hit you on the next beat.
* **Enemies** have no invincibility: you can hit one on every beat.

## Dealing damage

Your hit deals your weapon's damage ([weapons.md](./weapons.md)), doubled by
a Rapier lunge, then 1 more for each of Sunglasses (`HeadSunglasses`) and the
Ring of Might (`RingMight`). A Titanium Rapier lunge with Sunglasses on deals
2 × 2 + 1 = 5.
