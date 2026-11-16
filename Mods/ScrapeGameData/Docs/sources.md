# Game data sources

What a mod can read out of a running game, found by probing it live. Every
entry was tried in CotN with Synchrony API 4.2.1 at run-time (inside an
`event.levelLoad` handler), and results were read from `NecroDancer.log`.

## Confirmed to work and useful

* **`GameXML.getXMLString()`**: returns the game's own `necrodancer.xml` as one
  string (about 250 KB). It describes items, enemies and characters in the
  game's original data format, including localization-tagged names, hints, and
  per-zone drop weights. This looks like the richest source of design-level
  data.
* **`GameXML.getItemData(name)`**: returns a parsed table for one XML item.
  Tried on `food_1`: `coinCost`, `slot`, `isFood`, `hint`, `shopChance` and
  `chestChance` (both pipe-separated, probably one value per zone), `texture`
  and `unlocked`. Values are strings, so numbers need parsing. `getEnemyData`
  and `getCharacterData` exist with the same idea but are untried.
* **`Components.getComponentDefaults()`**: returns every registered component
  (2,105) mapped to its fields and default values. Tried on `consumableHeal`:
  `health`, `maxHealth`, `cursedHealth`, `overheal`, `invincibility`,
  `silent`, `noParticles`. This is the authoritative field list, which the
  mirrored docs lack.
* **`Entities.listComponentNames()` and
  `Entities.getEntityTypesWithComponents({})`**: enumerate all component names
  and all 1,064 entity type names. An empty component list matches every type.
* **`Entities.getEntityPrototype(typeName)`**: returns a type's component table
  with its constant field values. Reading a field a component doesn't have
  throws and suggests the closest name ("Did you mean health?"). My probe
  used the wrong field, `consumableHeal.heal`, and only learned the real names
  from the defaults above.
* **`FileIO.listFiles("scripts", FILES + RECURSIVE)`**: lists all 1,066 of the
  game's Lua files (e.g. `necro/game/item/Currency.lua`), which gives a
  complete module inventory. `listFiles("")` and `listFiles("mods")` also
  return entries. Directories come back as entries when `DIRECTORIES` is set.
* **`entitySchemaLoadEntity` event**: already documented in
  `Mods/docs/gotchas.md`. Printing `ev` dumps every entity type with its full
  component table to the log.
* **`GameMod.getPatchVersion()`**: returns the game's patch version (`"4.2.1"`
  here). It is the only version a mod can read: `Session.getVersion()` and
  `necro.mod.Mods` can't be required (Permission denied), `_VERSION` is
  absent, and `Netplay` has no `getVersion`. There is no build number.

## Confirmed not to work or not be useful

TODO - fact check. This is all AI generated. Just because the AI said it's
"confirmed not to work or not be useful" doesn't mean we can't/shouldn't use
these options.

* **Enumerating modules, `_G` or `event` with `pairs()`/`next()`**: all return
  nothing. `Entities`, `_G` and `event` are all empty to iteration, though
  their members work when named. Use the file listing and the docs to learn
  what exists.
* **Lua introspection globals**: `getmetatable`, `rawget`, `debug`, `package`,
  `load`, `loadstring`, `os`, `io` and `collectgarbage` are all absent.
  Reading an undefined global throws. Only `math`, `string`, `table`, `next`,
  `select`, `setmetatable` and `require` were present.
* **`Localization.get("entity.Food1.name", ...)`**: returned only my fallback,
  and `getLoadedLanguageID()` returned nil. The key was a guess, so this isn't
  proof that localization is unreadable (see below).
* **`FileIO.listFiles("data")` and `("data/xml")`**: both returned zero
  entries. Those paths don't exist in the virtual filesystem.
* **Game install directory on disk**: it holds only `NecroDancer.log`. There
  is nothing to read from outside the game.
* **Writing output files**: `FileIO` is read-only, and
  `DebugDump.writeTextFile` is documented as internal-only. The log is the
  only output channel found so far.
* **`FileIO.readFileToString` on `scripts/*.lua`**: it works, but the files
  are LuaJIT bytecode (header `\27LJ`), so they aren't readable source.
  Decompiling is a separate decision, gated on the TODO's last-resort item.

## Worth investigating further

* **Bytecode string tables**: the compiled scripts still carry their string
  constants (module paths, function names, field names). Extracting them
  offline would give a function-name inventory per module, without decompiling.
  Getting the bytes out means dumping hex or base64 through the log.
* **`GameXML.getEnemyData(name, type)` and `getCharacterData(id)`**: should
  yield enemy stats and character starting items. Their argument and return
  shapes are undocumented, so each needs a live probe.
* **`XMLMapping` getters** (`getEnemyTypeByID`, `getPlayerTypeByID`,
  `getTrapTypeByID` and so on): map XML IDs to entity type names, which would
  join the XML data to the ECS data.
* **`ItemGeneration`, `PriceTag`, `ItemSlot`, `EnemySubstitutions`,
  `LevelSequence`, `ProgressionXML`**: probably hold loot pools, shop prices,
  slot capacities, enemy swaps and level order. All untried.
* **Localization keys**: find the real key format (e.g. by dumping the
  `friendlyName` fields from entity prototypes, or `Components.getLocalizableFields`)
  and read the English text.
* **Enum tables** (damage types, item slots, extra modes, and so on): the
  docs list these, but reading the live values would confirm them. Their
  members may not be iterable (see the `pairs()` result above).
* **Log volume**: resolved. 4,000-character base64 chunk lines carried the
  250 KB XML and the other dumps through the log intact (byte counts matched
  the mod's `emitted` lines). `nix run .#scrape-game-data` reassembles them.
