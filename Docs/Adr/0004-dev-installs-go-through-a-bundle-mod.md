# Dev installs go through one generated bundle mod

The game only loads mods it already has enabled; a new mod folder dropped into
its mods directory is ignored until someone enables it in the Mods menu. To
install and uninstall mods without that manual step, `live-game-run` (through
its internal `install-mods`; ADR 0009) stages the chosen `Mods/<name>/`
directories as subfolders of one generated bundle mod, which is enabled once
by hand. Installing a different set replaces the
bundle's contents. Each mod stays a standalone `Mods/<name>/` so it can still
be shared on its own.

A module's name is `<mod name>.<path>`, so inside the bundle every module of an
installed mod gains the bundle's name as a prefix. `install-mods` rewrites
`require "<Mod>.…"` to `require "<Bundle>.<Mod>.…"` for the installed mods.

## Considered options

* **Enable each mod by hand.** Rejected: one manual step per new mod defeats
  the point.
* **Host dev mods inside an already-enabled mod** such as `HelloWorld`.
  Rejected: this is the same bundle idea, but it pollutes a real mod.
* **A `namespace.lua` per mod** that finds its own prefix at load time, with
  `namespace.require "api"` everywhere. It works, but every file that requires
  another module needs the extra line, and an install-time rewrite is still
  needed for the one hardcoded `require`.
* **Rewriting `require` strings at install time.** Chosen: mods keep plain,
  standalone-correct `require` calls.

## Consequences

* `Mods/<name>/` must equal the `namespace` and `name` in its `mod.json`.
* Every mod in `Mods/` declares the same `synchronyVersion`, and the generated
  bundle takes it from the mods it holds.
* A string that names a mod's modules (such as `"TestFramework.api"`) may
  appear only as the whole, static argument of a `require` (any quote style,
  also `pcall(require, …)`); the rewrite touches nothing else, and comments
  are ignored. Dynamic requires built by concatenation fail the check.
* The rules, the rewrite, and the dependency refusal below live in one place,
  `Mods/bundle-layout.lua`, which tokenizes the Lua instead of matching text.
  The `mods-layout` check and the `bundle-layout` fixture test run it.
* `install-mods` refuses to install a mod that depends on another mod from
  `Mods/` that is not also being installed, since a bundled mod can only find
  mods bundled with it.
* `install-mods` copies from the source tree rather than the Nix store, which
  only contains git-tracked files.
