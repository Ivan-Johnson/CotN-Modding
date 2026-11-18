# Lua gotchas

## Reverse-engineering

To find which components/fields drive an existing entity's behavior, temporarily
register:

```
event.entitySchemaLoadEntity.add("dump", {order = "finalize", sequence = 1}, function(ev) print(ev) end)
```

When run, every entity in the base game (and any other loaded mods) gets logged
to `NecroDancer.log` with its full component/field table. Search it by the
entity's `friendlyName` or internal `name` to see exactly which component
provides a given behavior (e.g.  `consumableHeal` on `Food1`/Apple).

The same `print(ev)` trick works inside any other event handler to inspect an
unfamiliar event's fields (e.g. `ev.caster`, `ev.spell` inside `spellcast`) when
the API docs don't spell out its payload.

## Load time and deferral

* Calling anything that fires an event (e.g. `GameSession.start`,
  `ExtraMode.setActive`, `NetRNG.setSeed`) directly at a script's top level,
  instead of from inside an event handler, throws "Cyclic dependency
  involving ... 'system.mod.ModLoader'" and aborts the whole script load.
  Defer such calls to inside a handler instead.
* For deferred calls, use `Tick.delay(func)` like so:
  ```lua
  -- luacheck: globals myDelayedCall
  myDelayedCall = Tick.delay(function() ... end)
  myDelayedCall()
  ```
  Define the wrapper once and reuse the same global for every deferred call
  (e.g. one per test in a suite): the sandbox rejects dynamically creating new
  globals (`_G[name] = ...` throws "Attempt to write to non-existent global
  variable"), and re-`Tick.delay`-ing a fresh wrapper under the same global
  name each time breaks its "must be bound to a global variable" binding
  check instead.

## Events and game state

* When two handlers share an order key and neither specifies `sequence`, the
  tie does not necessarily break in dependency-load order: empirically, a
  dependent mod's handler ran before the mod it depends on's handler at the
  same order/sequence, the opposite of a literal reading of the "mods sorted
  by load order" doc wording. Don't assume; confirm actual firing order with
  temporary debug `print()`s before relying on it.
* `Marker.Type.STAIRS` markers aren't unique to a level's exit: "All
  Characters Mode" reuses them for its post-run character-select room (one
  staircase per remaining character), and the game lobby reuses them for its
  mode-select room. Logic that keys off stairs markers must account for this
  or disable Extra Modes first (`ExtraMode.setActive`).
