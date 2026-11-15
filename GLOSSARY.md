# CotN Modding

Vocabulary for Synchrony, the Lua modding API of Crypt of the NecroDancer
(CotN), and for the tooling in this repo. Definitions are drawn from the
rendered Synchrony docs (`result/docs/markdown/`). Game-mechanics terms
(characters, enemies, items, bosses) are not covered yet.

## Mods and scripts

**Mod**:
A unit of content loaded by Synchrony: a `mod.json` manifest plus Lua scripts.
_Avoid_: Plugin, addon

**Unpacked mod**:
A mod loaded from a plain directory rather than a packaged archive. Only
unpacked mods are live-reloaded.
_Avoid_: Unzipped mod

**Script**:
A single Lua file belonging to a mod.

**Module**:
A script as imported via `require()`, identified by its dotted name. The base
game's modules are grouped into packages.
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
held outside entities.

**Rollback**:
Restoring a snapshot and resimulating after an action arrives with an earlier
or equal turn ID than the current one.

**Rollback artifact**:
A brief visual or audio inconsistency caused by speculative actions that
rollback later overrules.

## Repo tooling

**Rendered docs**:
The Synchrony API documentation mirrored by `DocDownloader/` and built into
Markdown at `result/docs/markdown/`.
