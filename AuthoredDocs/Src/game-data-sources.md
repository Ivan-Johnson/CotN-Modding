# Game data sources

For mod authors. What a mod can read from the running game at run-time (in an
`event.levelLoad` handler), on CotN 4.2.1 with Synchrony API 4.2.1.

## Readable

* **`GameXML.getXMLString()`** returns the game's own `necrodancer.xml` as one
  string of about 250 KB. It describes items, enemies and characters in the
  game's original data format, including localization-tagged names, hints and
  per-zone drop weights.
* **`GameXML.getItemData(name)`** returns a parsed table for one XML item. Its
  values are strings, so numbers need parsing. `shopChance` and `chestChance`
  are pipe-separated, probably one value per zone (`guess`). `getEnemyData`
  and `getCharacterData` exist; their arguments and results are untried.
* **`Components.getComponentDefaults()`** maps every registered component to
  its fields and default values. It is the authoritative field list; the
  official docs lack one.
* **`Entities.listComponentNames()`** and
  **`Entities.getEntityTypesWithComponents({})`** enumerate component names and
  entity type names. An empty component list matches every type.
* **`Entities.getEntityPrototype(typeName)`** returns a type's components with
  their constant field values. Reading a field a component lacks throws and
  suggests the closest name ("Did you mean health?").
* **`FileIO.listFiles("scripts", FILES + RECURSIVE)`** lists the game's Lua
  files, which gives a module inventory. `listFiles("")` and
  `listFiles("mods")` also return entries; directories appear when
  `DIRECTORIES` is set.
* **`entitySchemaLoadEntity`**: printing `ev` dumps every entity type with its
  component table (see [gotchas.md](./gotchas.md)).
* **`GameMod.getPatchVersion()`** returns the patch version (`"4.2.1"`). It is
  the only version a mod can read: `Session.getVersion()` and `necro.mod.Mods`
  cannot be required (Permission denied), `_VERSION` is absent and `Netplay`
  has no `getVersion`.
* **Module APIs** come from bytecode, because `pairs()` over a module returns
  nothing. `FileIO.readFileToString` on `scripts/*.lua` returns LuaJIT bytecode
  (header `\27LJ`) that is not stripped, so function parameter names survive.
  `Mods/ScrapeGameData/BytecodeApi.lua` recovers each module's public API from
  it and publishes `module-apis.json`; it also lists functions the official
  docs lack (for example `Currency.lookUpEntityType`) and the commands of
  `DebugCommands`, which only work as `DebugCommands.commands.<name>(...)`.
  Two scripts, `necro/audio/Beatmap.lua` and
  `necro/patch/SkinSupporterHotfix.lua`, ship as plain source, and the game has
  no `load`, `loadstring` or `lpeg` for mods, so those are scanned with Lua
  patterns.

## Not available

Each item below came from one probe on 4.2.1, not a systematic check:

* `pairs()` or `next()` over a module, `_G`, `event` or `Entities` returns
  nothing, though their members work when named.
* `getmetatable`, `rawget`, `debug`, `package`, `load`, `loadstring`, `os`,
  `io` and `collectgarbage` are absent, and reading an undefined global
  throws. `math`, `string`, `table`, `next`, `select`, `setmetatable` and
  `require` are present.
* `FileIO.listFiles("data")` and `("data/xml")` return zero entries.
* `FileIO` is read-only and `DebugDump.writeTextFile` is documented as
  internal-only, so the log is the only output channel found (see
  [synchrony-game-control.md](./synchrony-game-control.md)).
* The game install directory holds only `NecroDancer.log`.
