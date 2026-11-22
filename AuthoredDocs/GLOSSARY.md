# AuthoredDocs

Vocabulary for the docs written by hand for this repo, and for the docs tree
that publishes them beside the docs derived from the official docs and the
game.

## Language

**Authored docs**:
Docs written by hand for this repo, as opposed to derived from the official
docs or the game. Published under `authored/` in the docs tree.
_Avoid_: Unofficial docs, handwritten docs

**Docs tree**:
The layout of `result/docs/`, which holds the raw docs, official docs, game
data, and authored docs together.
_Avoid_: Output, result

## Audiences

The authored docs have two **users**, and every authored doc names which it is
for. Material that helps neither, such as how to run or change the `Mods/`
tooling, belongs in `Mods/`. Both audiences read a web of linked pages rather
than a linear guide.
_Avoid_: Reader, agent, human

**Player**:
Someone who wants to know how to play the game and how each player-facing
thing works: an enemy's movement pattern, a weapon's reach, a shrine's cost.
Their docs form a wiki of pages about the game's things.
_Avoid_: Gamer

**Mod author**:
Someone who writes a mod and already knows the basics of the game. Their docs
cover the programming side: the modding APIs and the details of how the game
works underneath, such as ticks and the entity component system.
_Avoid_: Modder, mod developer
