# Dev installs go through one generated bundle mod

The game only loads mods it already has enabled; a new mod folder dropped into
its mods directory is ignored until someone enables it in the Mods menu. To
install and uninstall mods without that manual step, `install-mods` stages the
chosen `Mods/<name>/` directories as subfolders of one generated bundle mod,
which is enabled once by hand. Installing a different set replaces the
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
* A string that names a mod's modules (such as `"HelloWorldTests.api"`) may
  appear only as the argument of a `require`; the rewrite touches nothing
  else. Dynamic requires built by concatenation are not rewritten.
* Both rules are enforced by the `mods-layout` check
  (`Mods/check-layout.bash`).
* `install-mods` refuses to install a mod that depends on another mod from
  `Mods/` that is not also being installed, since a bundled mod can only find
  mods bundled with it.
* `install-mods` copies from the source tree rather than the Nix store, which
  only contains git-tracked files.
