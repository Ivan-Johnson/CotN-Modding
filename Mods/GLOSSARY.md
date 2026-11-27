# CotN Modding

Vocabulary for Synchrony, the Lua modding API of Crypt of the NecroDancer
(CotN), as used when writing the mods in `Mods/`.

This file is likely to contain errors; it is entirely AI generated from the
official docs (`result/docs/official/markdown/`). If this file defines terms differently
than how they are used in that directory, then that is a bug.

## Mods and scripts

**Mod**:
A unit of content loaded by Synchrony: a `mod.json` manifest plus Lua scripts.
_Avoid_: Plugin, addon

**Unpacked mod**:
A mod loaded from a plain directory rather than a packaged archive. Only
unpacked mods are live-reloaded.
_Avoid_: Unzipped mod

**Enabled mod**:
A mod the game remembers, by name, as one to load. The game does not load a mod
merely because it appears in the mods directory.
_Avoid_: Installed mod (a mod can be on disk without being enabled)

**Bundle mod**:
A generated mod, enabled once, whose subfolders are the mods currently being
developed. It exists only in the game's mods directory, never in `Mods/`.
_Avoid_: Install target, dev mod

**Script**:
A single Lua file belonging to a mod.

**Module**:
A script as imported via `require()`, identified by its dotted name
`<mod name>.<path from the mod root>`. The base game's modules are grouped into
packages.
_Avoid_: Library

**Load-time**:
The period while a module is being initialized (its global scope runs). Events
may be registered but the entity system and event firing are off-limits.

**Run-time**:
Any time after a module has finished loading, e.g. inside an event handler.

**Live-reload**:
Re-running changed scripts in a running game while preserving game state.
_Avoid_: Hot-reload

**Transient variable**:
A `local` module variable; it resets to its declared value whenever the module
reloads. Contrast with a global variable.

**Global variable**:
A variable assigned without `local` at module scope. Unlike standard Lua, it is
private to its module and keeps its value across live-reloads. Not the same as
a snapshot variable.

## Events

**Event**:
A named, globally fired signal. Any module may listen without requiring the
module that fires it. Handlers receive one table, `ev`.

**Handler**:
A function registered to an event, with a name that is prefixed by its mod's
namespace.
_Avoid_: Listener, callback

**Selector**:
The mechanism by which an event picks its handlers: Ordered, Enum, Entity, or
Object.

**Order key**:
A string naming a slot in an event's ordering list; handlers sort by it first.

**Sequence number**:
A number that orders handlers sharing an order key. Built-in handlers are 0,
so negative runs before them and positive after.

**Filter**:
A component name restricting an event handler to entities that have it.

**Object event**:
An entity-selected event (`objectXYZ`) that also lets characters respond based
on their equipment.

**Holder event**:
The `holderXYZ` twin of an object event, fired per item in the character's
inventory. `ev.holder` is the character and `ev.entity` is the item.

**Override**:
A replacement for an existing handler, matched by exact name, which receives
the original function and decides whether to call it. A last resort.

## Entity Component System

**Entity**:
A game object, identified by a numeric ID. ID 0 is the null reference.

**Component**:
A named bundle of typed fields attached to an entity, such as `position`.

**Field**:
A typed value inside a component. Constant fields are fixed per entity type;
mutable fields vary per instance.

**Entity type**:
The static definition of an entity's components and initial field values.
Every entity has exactly one.
_Avoid_: Class, prefab

**Entity wrapper**:
The Lua handle used to read and write an entity. It becomes invalid when the
entity despawns, so store the ID instead.

**Conversion**:
Changing an entity's type in place, keeping its ID and any fields that the old
and new types share.

## Time and synchronization

**Turn**:
A simulated step of gameplay, identified by a turn ID in units of 1/30 second.
Rhythm-bound characters' actions snap to the beatmap, so a turn is not the same
as a beat.

**Beat**:
A pulse of the song's rhythm, on which rhythm-bound characters and enemies
act. The docs count an entity's beats as the turns in which it has been active.
Entity-level counters such as beat delay and beat counter are measured in beats.

**Beatmap**:
Per-client timing data for the current song, from which a client decides
whether an input landed on a beat. It is local and never synchronized.

**Determinism**:
The requirement that gameplay produces identical results from identical inputs
on every client.

**In-turn / Out-of-turn**:
Whether code runs while `turn`, `gameStateLevel`, or `gameStateReset` is
firing (in-turn: safe to change gameplay state) or elsewhere (out-of-turn).

**Action**:
A player input (`playerID`, `actionID`, `turnID`, `timestamp`, `args`) sent
between clients.

**Action buffer**:
The queue of local and remote actions that a client simulates.

**Snapshot**:
A saved copy of the full game state, which a client restores to resimulate.

**Snapshot variable**:
A global declared via `snapshot.variable`, `levelVariable`, or `runVariable`
so that it is saved and restored with snapshots. Required for gameplay state
held outside entities. `levelVariable` also resets on each new level,
`runVariable` on each new run, and `variable` never resets.

**Rollback**:
Restoring a snapshot and resimulating after an action arrives with an earlier
or equal turn ID than the current one.

**Rollback artifact**:
A brief visual or audio inconsistency caused by speculative actions that
rollback later overrules.

## Run structure

**Run**:
One attempt, from when a mode's gameplay starts (`GameSession.start` or
`restart`) until it ends; completing the run-final level counts as a victory.
It has a run ID and may contain several loops. `runVariable`s and run
attributes (e.g. `RunState.Attribute`) last exactly one run. Source:
`GameSession`, `CurrentLevel.isRunFinal`.
_Avoid_: Game, session, loop

**Game session**:
The API's name for a mode in progress: `GameSession` starts a run in a mode,
`restart` begins a new run, and the mode (`GameSession.Mode`) configures it.
It is not an umbrella over several runs: the docs name no such term. The
lobby is itself a mode, with `isLobby` set. Source: `GameSession`.

**Level**:
One generated play space in a run's sequence. Its run-wide level number, visit
sequence number, and unique ID are distinct values. Source: `CurrentLevel`,
`LevelGenerator`.
_Avoid_: Floor (a floor is a level's position within a zone)

**Zone**:
A progression grouping, typically advancing every 4 levels. Counts down from
4 or 5 for certain characters. Source: `CurrentLevel.getZone`.

**Floor**:
A level's position within its zone, typically 1 to 4; resets to 1 on entering
a new zone. Source: `CurrentLevel.getFloor`.

**Depth**:
Starts at 1 for every character and typically increments every 4 levels, so
it differs from zone for characters whose zones count down. Source:
`CurrentLevel.getDepth`.

**Level sequence**:
The per-run ordered list of generator options, one per level. Source:
`LevelSequence`.

**Loop**:
A sub-run within a looping or multi-character run (Deathless, All-Chars),
identified by a loop ID. Source: `CurrentLevel.getLoopID`.
_Avoid_: Run

**Lobby**:
A level flagged by `CurrentLevel.isLobby`; also counts as safe. Source:
`CurrentLevel`.

**Extra mode**:
A game-mode identifier from the `ExtraMode` module, covering built-in, seeded,
and custom modes. The docs list the identifiers and query functions, not what
each mode does. Source: `ExtraMode`.
_Avoid_: Mod (a mod is loaded content, see `GameMod`)

## Players and characters

**Player**:
A participant in the game, identified by a player ID. Covers local and remote
participants (and spectators), whether human or an agent. The player ID is not
the player's entity ID, and spectators have no entity at all. Source:
`overview.md`, `Player`.
_Avoid_: Human (unless contrasting with an agent), character

**Player entity**:
The entity a player currently controls, found via `Player.getPlayerEntity`.
Conversion or replacement can swap it mid-run. Source: `Player`.

**Character type**:
The entity type a player plays as (Cadence, Melody, Aria, ...), found via
`Player.getCharacterType(playerID)`. Chosen in the lobby from entities with
`playableCharacter`. Source: `Player`, `CharacterComponents`.
_Avoid_: Class

**Character**:
In the API, any entity with the `character` component, which lets it perform
actions. That includes enemies, so "character" alone does not mean a
player's. Source: `CharacterComponents`.
_Avoid_: Using it for a player or a character type

## Items and inventory

**Item**:
An entity carrying the `item` component. `itemSlot` assigns it a slot; holder
and equipped state track who carries it. Use the `Inventory` module to add,
equip, unequip, or drop; do not edit inventory fields directly. Source:
`ItemComponents`, `Inventory`.

**Item slot**:
A named inventory category with its own capacity, such as `action` (default
capacity 1) or `spell` (default 2). Some slots are internal and absent from
the HUD: `follower`, `shrine`, `innate`. Source: `ItemSlot`.

**Carried vs. equipped**:
Carrying an item in the inventory does not mean it is equipped. Source:
`ItemComponents`.

## Damage

**Damage type**:
A bitmask of flags, so one hit can combine several (e.g. bypass armor, scale
with strength, explosive). Source: `Damage.Type`.

**Hit pipeline**:
`objectDealDamage` handlers modify, suppress, or apply a hit. By the time
`objectTakeDamage` fires, armor, shield, and invincibility handling may already
have changed the amount. `objectDeath` fires when health reaches zero and
names the attacker and credited killer. The docs do not give one fixed
end-to-end order. Source: `events/object.md`, `overview.md`.

**Health**:
For players 1 heart = 2 health; for enemies 1 heart = 1 health. Source:
`Health`.

**Knockback**:
A damage parameter: tiles the victim is pushed along the hit's direction. It
can be suppressed separately from the damage. Source: `Damage.Parameters`.

## Rhythm and AI

**Groove chain**:
Per-entity kill streak that raises a multiplier (default maximum 3). It
increases on kills credited as `GROOVE_CHAIN`, and resets on non-self damage.
Source: `GrooveChainComponents`.
_Avoid_: Combo

**Coin multiplier**:
The `coinMultiplier` component multiplies gold dropped when the entity kills
something. It is separate from the groove chain's multiplier. Source:
`GrooveChainComponents`.

**Rhythm ignored**:
`rhythmIgnored` lets an entity act regardless of the beatmap. Source:
`RhythmComponents`.

**Missed beat**:
An event for a superfluous input within a single beat; standing still causes
IDLE instead. Source: `ObjectEvents`.

**Beat delay**:
While nonzero, an entity may only perform IDLE (with exceptions). Any non-FAIL
action ticks it down. Source: `BeatDelayComponents`.

**Beat counter**:
Counts turns in which an entity has been active since the floor began. Source:
`BeatDelayComponents`.

**AI type**:
The `ai` component's `id` picks a behavior, e.g. idle, seek, flee, or pattern;
other types are enemy-specific. Source: `AIComponents`, `necro.game.enemy.ai.AI`.

**Target**:
The entity an AI acts on. AI-controlled entities require the `target`
component. Source: `TargetingComponents`.

**Provoked**:
A `provokable` entity's triggered state, which can swap in a different AI.
Source: `ProvokableComponents`.

## Testing

**Code test**:
A live test that checks this repo's own code: a **Mod**'s behavior or the test
framework's.
_Avoid_: Regression test

**Claim test**:
A live test that backs a claim made in one authored doc. Each file of claim
tests backs exactly one doc.
_Avoid_: Doc test, docs test

**Survey test**:
A live test whose claim holds over a sample: odds, or what a set of levels
holds, drawn over many runs or trials. When only the harness changed, it
takes its small sample (`api.smallSample`), which exercises the same code
without the assertions that need the full sample (ADR 0008).
_Avoid_: Statistical test, slow test

**Test framework**:
The **Mod** `TestFramework`, which mods optionally `require` to register
**Code tests** and **Claim tests**, and which runs them. It never depends on a
mod under test (ADR 0003).
_Avoid_: Harness (the framework plus the runner, install scripts and flake
files; ADR 0008)
