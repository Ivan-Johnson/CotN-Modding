# Reads the repo paths a change touches, one per line on stdin, and prints
# `none` if no live test (`itj-impure-tests`) can be affected by them, `all`
# if every test must run, `args: --small-samples [FILE,...]` if every test
# must run but survey tests may take their small sample, or else the test
# files to run, one basename per line (e.g. `weapons.lua`), which
# `itj-impure-tests --files` runs alone. Called by `build-release` (DevTools)
# from the git hooks, which runs `itj-impure-tests` with the words after
# `args:`. The rules are
# Docs/Adr/0008-claim-tests-run-only-when-their-page-changes.md:
#
# * A claim test file runs when it or its page changes.
# * A code-test mod's tests (its `tests.lua` and `*-tests.lua`) run when
#   anything in that mod changes.
# * A harness path runs everything, with survey tests taking their small
#   sample, except those in the test files the other rules select.
# * Any path no rule names runs everything at full size, so a new kind of
#   file fails safe. So does empty input (e.g. a message-only amend).
#
# Usage: itj-impure-scope [REPO_ROOT] <paths
# REPO_ROOT (default: the git toplevel) is the tree whose claim test and code
# test files exist.

root=${1:-$(git rev-parse --show-toplevel)}

# The test harness: the framework, the scripts that install and run the
# tests, and the flake that builds them. These win over the lists below.
harnessPrefixes=(
	"Mods/TestFramework/"
	"Mods/LiveGame/install-mods.bash"
	"Mods/LiveGame/live-game-run.bash"
	"Mods/LiveGame/itj-impure-tests.bash"
	"Mods/LiveGame/itj-impure-scope.bash"
	"Mods/LiveGame/bundle-layout.lua"
	"Mods/flake-module.nix"
	"flake.nix"
	"flake.lock"
)

# Paths that no live test reads. The suite installs only the code-test mods,
# ClaimTests and TestFramework, so none of these can change it; a claim page is
# matched before this list.
harmlessPrefixes=(
	"AuthoredDocs/"
	"Docs/"
	"GameData/"
	"DocDownloader/"
	"Mods/ScrapeGameData/"
)

# Mods/LiveGame/test-* are the offline tests that `nix flake check` runs, and
# cotn-log-idle-notify.bash is a dev-shell tool; the live suite reads neither.
harmlessGlobs=(
	"*.md"
	"Mods/LiveGame/test-*"
	"Mods/LiveGame/cotn-log-idle-notify.bash"
	"open_files.txt"
	"Tmp/*"
)

hasPrefix() {
	local path=$1 prefix
	shift
	for prefix in "$@"; do
		if [[ $path == "$prefix"* ]]; then
			return 0
		fi
	done
	return 1
}

isHarmless() {
	local path=$1 glob
	if hasPrefix "$path" "${harmlessPrefixes[@]}"; then
		return 0
	fi
	for glob in "${harmlessGlobs[@]}"; do
		# shellcheck disable=SC2053 # The glob is meant to match as a pattern.
		if [[ $path == $glob ]]; then
			return 0
		fi
	done
	return 1
}

# Each code-test mod's test files, as they exist in the tree and as
# itj-impure-tests.bash also finds them: space-separated, keyed by mod.
declare -A codeTestFiles=()
shopt -s nullglob
for path in "$root"/Mods/*/tests.lua "$root"/Mods/*/*-tests.lua; do
	mod=${path%/*}
	mod=${mod##*/}
	if [[ $mod != ClaimTests ]]; then
		codeTestFiles[$mod]+="${path##*/} "
	fi
done
shopt -u nullglob

seen=0
harness=0
testFiles=()
while IFS= read -r path; do
	if [[ -z $path ]]; then
		continue
	fi
	seen=$((seen + 1))
	# The mod directory a `Mods/<mod>/...` path is in.
	mod=${path#Mods/}
	mod=${mod%%/*}
	if hasPrefix "$path" "${harnessPrefixes[@]}"; then
		harness=1
	elif [[ $path == Mods/ClaimTests/*.lua && $path != Mods/ClaimTests/*/* ]]; then
		# A deleted claim test file has nothing left to run.
		if [[ -e $root/$path ]]; then
			testFiles+=("${path##*/}")
		fi
	elif [[ $path == AuthoredDocs/Src/*.md && $path != AuthoredDocs/Src/*/* ]]; then
		# A page with no claim test file, or one deleted with its page, has
		# nothing to run.
		page=${path##*/}
		if [[ -e $root/Mods/ClaimTests/${page%.md}.lua ]]; then
			testFiles+=("${page%.md}.lua")
		fi
	elif [[ $path == Mods/*/* && -n ${codeTestFiles[$mod]:-} ]]; then
		if [[ $path == *.md ]]; then
			continue
		fi
		read -ra files <<<"${codeTestFiles[$mod]}"
		testFiles+=("${files[@]}")
	elif ! isHarmless "$path"; then
		echo all
		exit 0
	fi
done

if ((seen == 0)); then
	echo all
elif ((harness)); then
	# The files the other rules selected keep their survey tests' full sample.
	full=$(printf '%s\n' "${testFiles[@]}" | sort -u | paste -sd, -)
	echo "args: --small-samples${full:+ $full}"
elif ((${#testFiles[@]} == 0)); then
	echo none
else
	printf '%s\n' "${testFiles[@]}" | sort -u
fi
