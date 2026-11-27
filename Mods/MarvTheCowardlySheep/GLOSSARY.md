# Marv the Cowardly Sheep

Vocabulary for the `MarvTheCowardlySheep` mod's game design: a playable
character, **Muriel**, like Mary but whose sheep is a coward. Synchrony API
terms are in `Mods/GLOSSARY.md`.

## Language

**Muriel**:
A selectable playable character, identical to Mary except for her name and
that her sheep is **Marv** rather than **Vanilla Marv**. Mary herself is
unchanged.
_Avoid_: Marv the Cowardly Sheep (the mod's name), Mary variant

**Marv**:
The cowardly sheep that accompanies **Muriel**, a copy of **Vanilla Marv**
that can suffer **Death by fright**. Always the sheep, never the character.
_Avoid_: Lamb, pet, familiar

**Vanilla Marv**:
Mary's own sheep, the game's entity type `Marv`, unchanged by this mod. The
game shows both sheep as Marv, so say "Vanilla Marv" whenever the two could
be confused.
_Avoid_: Mary's sheep, original Marv

**Hostile enemy**:
An enemy hostile to **Marv** that is not passive, so an unprovoked shopkeeper
or dormant exploding mushroom is not one, and neither is a crate or barrel,
which is no enemy at all.
_Avoid_: Threat, aggressive enemy

**Fright zone**:
Tiles of a square on **Marv**'s far side from **Muriel**, its near edge or
corner touching his tile, less any tile walls hide from his line of sight.
When Muriel is in line with him on a row or column, it is a 5x5 square
straight behind him, less its leading corners (the two ends of its near
edge); otherwise it is a whole 2x2 square on his diagonal. Always highlighted
red; there is none while Muriel shares his tile.
_Avoid_: Cower zone, behind zone, danger zone

**Death by fright**:
**Marv**'s instant death when a **Hostile enemy** occupies the **Fright
zone**. Its consequence is the same as a vanilla sheep's death; only the
cause is new.
_Avoid_: Scare death
