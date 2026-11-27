# Behavior test for the live-test classifier: feeds it fixture path lists and
# checks its answer. Needs no live game. Expects `itj-impure-scope` on PATH and
# the repo's tracked files (the flake source) at the path in $1, whose claim
# test files (e.g. Mods/ClaimTests/weapons.lua) and code test files
# (e.g. Mods/HelloWorld/tests.lua) the answers depend on.
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
expect none AuthoredDocs/Src/gotchas.md
expect none AuthoredDocs/AGENTS.md AuthoredDocs/Src/Sub/weapons.md
expect none Docs/Adr/0001-crawl-is-mirrored-not-built.md AGENTS.md
expect none GameData/foo.nix DocDownloader/bar.rs
expect none Mods/ScrapeGameData/ScrapeGameData.lua
expect none open_files.txt Tmp/scratch/notes.txt README.md
expect none Mods/HelloWorld/notes.md

# The offline tests run under `nix flake check`, never in the live suite.
expect none Mods/LiveGame/test-live-game-run.bash Mods/LiveGame/test-itj-impure-tests.bash
expect none Mods/LiveGame/test-itj-impure-scope.bash
expect none Mods/LiveGame/test-bundle-layout.lua Mods/LiveGame/test-bytecode-api.lua

# A claim test file runs when it or its page changes, and not when it is gone.
expect weapons.lua Mods/ClaimTests/weapons.lua
expect weapons.lua AuthoredDocs/Src/weapons.md
expect weapons.lua Docs/a.md Mods/ClaimTests/weapons.lua AuthoredDocs/Src/weapons.md
expect "$(printf 'bombs.lua\nweapons.lua')" Mods/ClaimTests/weapons.lua AuthoredDocs/Src/bombs.md Mods/ClaimTests/weapons.lua
expect none Mods/ClaimTests/deleted.lua AuthoredDocs/Src/deleted.md

# A code-test mod's tests run when anything in that mod changes.
expect tests.lua Mods/HelloWorld/HelloWorld.lua
expect tests.lua Mods/HelloWorld/tests.lua
expect "$(printf 'tests.lua\nweapons.lua')" Mods/HelloWorld/mod.json AuthoredDocs/Src/weapons.md
expect gary-tests.lua Mods/GaryTheCowardlySheep/GaryTheCowardlySheep.lua
expect "$(printf 'gary-tests.lua\ntests.lua')" Mods/GaryTheCowardlySheep/mod.json Mods/HelloWorld/tests.lua
expect none Mods/GaryTheCowardlySheep/GLOSSARY.md

# The harness runs everything, survey tests at their small sample except in
# the files the other rules select.
small="args: --small-samples"
expect "$small" Mods/TestFramework/README.md
expect "$small" Mods/LiveGame/install-mods.bash
expect "$small" Mods/LiveGame/live-game-run.bash Mods/LiveGame/test-live-game-run.bash
expect "$small" Mods/LiveGame/itj-impure-tests.bash
expect "$small" Mods/LiveGame/itj-impure-scope.bash
expect "$small" Mods/LiveGame/bundle-layout.lua
expect "$small" Mods/flake-module.nix flake.nix flake.lock
expect "$small" Docs/a.md Mods/TestFramework/api.lua
expect "$small weapons.lua" Mods/ClaimTests/weapons.lua Mods/TestFramework/api.lua
expect "$small bombs.lua,tests.lua" flake.nix AuthoredDocs/Src/bombs.md Mods/HelloWorld/mod.json
expect "$small" Mods/TestFramework/api.lua Mods/ClaimTests/deleted.lua

# Anything no rule names runs everything at full size, even beside the harness.
expect all Mods/ClaimTests/sub/weapons.lua
expect all Mods/ClaimTests/mod.json
expect all Mods/TestFramework/api.lua Mods/unknown.txt
expect all Mods/unknown.txt Mods/TestFramework/api.lua
expect all Docs/a.md Mods/unknown.txt
expect all some/new/place.txt
expect all

# Each listed prefix matches a tracked path, so a list cannot drift out of step
# with the tree. Sourcing the classifier with no input only sets its lists and
# prints `all`; it takes the root from this script's $1.
# shellcheck source=Mods/LiveGame/itj-impure-scope.bash
source "$root/Mods/LiveGame/itj-impure-scope.bash" </dev/null >/dev/null
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
