# Behavior test for the live-test classifier: feeds it fixture path lists and
# checks its answer. Needs no live game. Expects `itj-impure-scope` on PATH and
# the repo's tracked files (the flake source) at the path in $1, whose claim
# test files (e.g. Mods/ClaimTests/weapons.lua) and code test file
# (Mods/HelloWorld/tests.lua) the answers depend on.
set -u

root=$1

failures=0

# expect ANSWER PATH...: with no paths, feeds empty input.
expect() {
	local want=$1 got
	shift
	got=$(printf '%s\n' "$@" | itj-impure-scope "$root")
	if [ "$want" != "$got" ]; then
		echo "FAIL: [$*] gave '$got', wanted '$want'" >&2
		failures=$((failures + 1))
	fi
}

# Harmless paths run nothing.
expect none AuthoredDocs/Src/testing.md
expect none AuthoredDocs/AGENTS.md AuthoredDocs/Src/Sub/weapons.md
expect none Docs/Adr/0001-crawl-is-mirrored-not-built.md AGENTS.md
expect none GameData/foo.nix DocDownloader/bar.rs
expect none Mods/ScrapeGameData/ScrapeGameData.lua
expect none open_files.txt Tmp/scratch/notes.txt README.md
expect none Mods/HelloWorld/notes.md

# A claim test file runs when it or its page changes, and not when it is gone.
expect weapons.lua Mods/ClaimTests/weapons.lua
expect weapons.lua AuthoredDocs/Src/weapons.md
expect weapons.lua Docs/a.md Mods/ClaimTests/weapons.lua AuthoredDocs/Src/weapons.md
expect "$(printf 'bombs.lua\nweapons.lua')" Mods/ClaimTests/weapons.lua AuthoredDocs/Src/bombs.md Mods/ClaimTests/weapons.lua
expect none Mods/ClaimTests/deleted.lua AuthoredDocs/Src/deleted.md

# HelloWorld's code tests run when anything in HelloWorld changes.
expect tests.lua Mods/HelloWorld/HelloWorld.lua
expect tests.lua Mods/HelloWorld/tests.lua
expect "$(printf 'tests.lua\nweapons.lua')" Mods/HelloWorld/mod.json AuthoredDocs/Src/weapons.md

# The harness, and anything no rule names, runs everything.
expect all Mods/ClaimTests/sub/weapons.lua
expect all Mods/ClaimTests/mod.json
expect all Mods/ClaimTests/weapons.lua Mods/TestFramework/api.lua
expect all Mods/TestFramework/README.md
expect all Mods/install-mods.bash
expect all Mods/itj-impure-tests.bash
expect all Mods/flake-module.nix flake.nix flake.lock
expect all Docs/a.md Mods/unknown.txt
expect all some/new/place.txt
expect all

# Each listed prefix matches a tracked path, so a list cannot drift out of step
# with the tree. Sourcing the classifier with no input only sets its lists and
# prints `all`; it takes the root from this script's $1.
# shellcheck source=Mods/itj-impure-scope.bash
source "$root/Mods/itj-impure-scope.bash" </dev/null >/dev/null
if ((${#harnessPrefixes[@]} == 0 || ${#harmlessPrefixes[@]} == 0)); then
	echo "FAIL: sourcing the classifier did not set its prefix lists" >&2
	failures=$((failures + 1))
fi
shopt -s nullglob
for prefix in "${harnessPrefixes[@]}" "${harmlessPrefixes[@]}"; do
	matches=("$root/$prefix"*)
	if ((${#matches[@]} == 0)); then
		echo "FAIL: prefix '$prefix' matches no tracked path" >&2
		failures=$((failures + 1))
	fi
done

if [ "$failures" -ne 0 ]; then
	exit 1
fi
