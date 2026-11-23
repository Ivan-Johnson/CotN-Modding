# Behavior test for the live-test classifier: feeds it fixture path lists and
# checks its answer. Needs no live game. Expects `itj-impure-scope` on PATH.
set -u

failures=0

# expect ANSWER PATH...: with no paths, feeds empty input.
expect() {
	local want=$1 got
	shift
	got=$(printf '%s\n' "$@" | itj-impure-scope)
	if [ "$want" != "$got" ]; then
		echo "FAIL: [$*] gave '$got', wanted '$want'" >&2
		failures=$((failures + 1))
	fi
}

expect none AuthoredDocs/Src/testing.md
expect none Docs/Adr/0001-crawl-is-mirrored-not-built.md AGENTS.md
expect none GameData/foo.nix DocDownloader/bar.rs
expect none "Mods/ScrapeGameData/ScrapeGameData.lua" "Mods/Gary the Cowardly Sheep/mod.json"
expect none open_files.txt Tmp/scratch/notes.txt README.md
expect none Mods/HelloWorld/notes.md

expect all Mods/HelloWorld/HelloWorld.lua
expect weapon-tests.lua Mods/HelloWorld/weapon-tests.lua
expect weapon-tests.lua Docs/a.md Mods/HelloWorld/weapon-tests.lua
expect "$(printf 'bomb-tests.lua\nweapon-tests.lua')" Mods/HelloWorld/weapon-tests.lua Mods/HelloWorld/bomb-tests.lua Mods/HelloWorld/weapon-tests.lua
expect all Mods/HelloWorld/tests.lua
expect all Mods/HelloWorld/weapon-tests.lua Mods/HelloWorld/HelloWorld.lua
expect all Mods/HelloWorld/sub/weapon-tests.lua
expect all Mods/HelloWorld/weapon-tests.lua Mods/HelloWorldTests/api.lua
expect all Mods/HelloWorldTests/README.md
expect all Mods/install-mods.bash
expect all Mods/flake-module.nix flake.nix flake.lock
expect all Docs/a.md Mods/unknown.txt
expect all some/new/place.txt
expect all

if [ "$failures" -ne 0 ]; then
	exit 1
fi
