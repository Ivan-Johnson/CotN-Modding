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
* Mod load order and event sequence numbers are used to resolve handler
  priority when multiple mods touch the same event.
* For support and troubleshooting, the docs recommend the Discord
  `#mod-help` channel.

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
