# Behavior test for the live-test classifier: feeds it fixture path lists and
# checks its answer. Needs no live game. Expects `itj-impure-scope` on PATH and
# the repo's tracked files (the flake source) at the path in $1.
set -u

root=$1

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
expect none Mods/ScrapeGameData/ScrapeGameData.lua
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

# Each listed prefix matches a tracked path, so a list cannot drift out of step
# with the tree. Sourcing the classifier with no input only sets its lists and
# prints `all`.
# shellcheck source=Mods/itj-impure-scope.bash
source "$root/Mods/itj-impure-scope.bash" </dev/null >/dev/null
if ((${#suitePrefixes[@]} == 0 || ${#harmlessPrefixes[@]} == 0)); then
	echo "FAIL: sourcing the classifier did not set its prefix lists" >&2
	failures=$((failures + 1))
fi
shopt -s nullglob
for prefix in "${suitePrefixes[@]}" "${harmlessPrefixes[@]}"; do
	matches=("$root/$prefix"*)
	if ((${#matches[@]} == 0)); then
		echo "FAIL: prefix '$prefix' matches no tracked path" >&2
		failures=$((failures + 1))
	fi
done

if [ "$failures" -ne 0 ]; then
	exit 1
fi
