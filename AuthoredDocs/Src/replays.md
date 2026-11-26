# Replays

For mod authors. Where the game saves replays, on CotN 4.2.1 under Proton.

## Directory structure

Replays live in the game's user-data directory, beside `mods/` and `saves/`.
Under Proton that is:

```
~/.local/share/Steam/steamapps/compatdata/247080/pfx/drive_c/users/steamuser/AppData/Local/NecroDancer/replays/
├── bundles/
│   ├── 2026-08/
│   │   ├── 2026-08-19.necroplay
│   │   └── …
│   └── 2026-11/
│       └── 2026-11-26.necroplay
└── favorites/
```

* `bundles/` holds one `YYYY-MM/` directory per month and one
  `YYYY-MM-DD.necroplay` file per day the game was played. Days without play
  have no file.
* Each day's file is named for its UTC date: `2026-11-23.necroplay` was last
  written at 22:58 on 22 November, US Eastern time.
* The files observed range from about 2 KB to 180 KB.
* `favorites/` was empty, with no replay favorited.
* The install directory has no `replays/`; the game warns at startup that
  `'../replays'` does not exist.
