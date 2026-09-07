# CotN modding notes

## What the local docs say

* Synchrony is the version of Crypt of the NecroDancer that adds full Lua modding support.
* Mods are opened from the game's **Customize -> Mods** menu.
* The mod browser can show featured mods from mod.io and also browse the full list.
* Synchrony mods can be turned on or off without restarting the game, even during an active run.
* Mods are multiplayer-friendly by default and sync automatically when players join online sessions.
* The Lua API runs on LuaJIT 2.1-beta3, which is mostly Lua 5.1 with some Lua 5.2 extensions.

## Basic process for making a mod

1. Install Crypt of the NecroDancer: Synchrony.
2. Learn the Lua scripting model from the Synchrony API docs.
3. Start from the community beginner guides linked in the docs or the
   API overview.
4. Build your mod around the available modules, components, and events.
5. Test by enabling or disabling the mod in the in-game Mods browser.
6. Iterate with live reload, then ask for help in the modding Discord if
   you get stuck.

## Dev workflow / tooling

* The docs do not describe a separate third-party mod framework or
  compile pipeline for authors.
* Internal APIs exist for creating, compiling, loading, and opening mod
  directories, but they are explicitly marked as not available in mods.
* Unpackaged Lua mods support live reloading on Windows and Linux via
  file watching; macOS needs a manual Shift+F7 reload.
* Load-time code can register events and initialize state, while run-time
  code handles gameplay logic after loading finishes.
* Confirmed live: calling anything that fires an event (e.g.
  `GameSession.start`, `ExtraMode.setActive`, `NetRNG.setSeed`) directly at
  a script's top level, instead of from inside an event handler, throws
  "Cyclic dependency involving ... 'system.mod.ModLoader'" and aborts the
  whole script load. Defer such calls instead.
  `Tick.registerDelay(func)`, the function the game's own deprecation
  warning recommends, was tried live (with and without a `name` argument)
  and never actually ran its callback. `Tick.invokeLater(func)` did run its
  callback, but confirmed live to crash the game the next time
  `Menu.lua`'s `eventHandlersChanged` handler processed the deferred-call
  queue (`Tick.lua:210`, "attempt to index local 'entry' (a function
  value)"): `invokeLater` pushes a bare function into a queue that other
  code expects to hold table entries. `Tick.delay(func)` is the documented,
  non-deprecated replacement and doesn't share that bug; its docs require
  storing the returned wrapper in a global variable (so delayed invocations
  survive mod reloads), then calling the wrapper to schedule the deferred
  call. That required global trips luacheck ("setting non-standard global
  variable" / "accessing undefined variable"); fix it with a per-file
  `-- luacheck: globals <name>` directive next to the declaration, not a
  `.luacheckrc` entry, since the global's name is mod-specific.
* Mod load order and event sequence numbers are used to resolve handler
  priority when multiple mods touch the same event.
* For support and troubleshooting, the docs recommend the Discord
  `#mod-help` channel.
* `Marker.Type.STAIRS` markers aren't unique to a level's exit: the "All
  Characters Mode" extra mode reuses them for its post-run character-select
  room (one staircase per remaining character), and the game lobby reuses
  them for its mode-select room. Any test/logic that keys off stairs
  markers must account for this or disable Extra Modes first (see
  `ExtraMode.setActive` above).

## Installed mod patterns

* Each copied mod ships as a packaged `.zip` with a `mod.json` manifest
  and one or more Lua entrypoints.
* `mod.json` is the key metadata file: it records namespace, display
  name, version, Synchrony version, description, author, icon, banner,
  homepage, and the Lua `scriptPath`.
* Some mods load Lua from the archive root, while others point
  `scriptPath` at a subdirectory such as `scripts/`.
* The entrypoint style is straightforward: require modules, register
  events, and mutate game state or UI from handlers.
* The examples include both gameplay mods and utility/QoL mods, such as
  racing tools, level-start grace, restart tweaks, and practice logging.
* The archives can include extra assets alongside Lua, such as icons,
  banners, sprites, audio, and nested folders like `gfx/`.
* At least one mod includes a `.bak` backup of its Lua file, so unpacked
  archives may contain editor leftovers as well as runtime files.
* Real mods often use `ModEvent.addUnloadHandler()` to clean up settings
  overrides and other state when the mod is disabled.
* The code makes heavy use of shared settings, snapshot variables, and
  event overrides, which is a useful template for future mods.

## Local doc sources

* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/overview.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/modules.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/components.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/modules/necro.client.ClientEvents.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/components/`
  `necro.game.data.component.character.AutoCastComponents.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/modules/necro.game.data.resource.GameMod.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/modules/necro.mod.Mods.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/modules/system.mod.ModLoader.md`
* `Tmp/CotN-docs/vortexbuffer.com/synchrony/docs/modules/necro.mod.ModWizard.md`
