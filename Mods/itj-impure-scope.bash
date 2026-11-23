# Reads the repo paths a change touches, one per line on stdin, and prints
# `none` if the live test suite (`itj-impure-tests`) cannot be affected by
# them, `all` if it must run in full, or else the changed test files, one
# basename per line (e.g. `weapon-tests.lua`), which `itj-impure-tests --files`
# runs alone. Called by `build-release` (DevTools) from the git
# hooks, so a docs-only commit or push skips the ~90 s live run.
#
# Only known-harmless paths give `none` and only `Mods/HelloWorld/*-tests.lua`
# gives a file list; every other path, and empty input (e.g. a message-only
# amend), gives `all`, which wins over a file list, so a new kind of file fails
# safe.
# The suite installs only HelloWorld and HelloWorldTests, so none of the
# `none` paths can change it.

# Suite paths that win over the harmless lists below.
suitePrefixes=(
	"Mods/HelloWorldTests/"
)

harmlessPrefixes=(
	"AuthoredDocs/"
	"Docs/"
	"GameData/"
	"DocDownloader/"
	"Mods/ScrapeGameData/"
	"Mods/Gary the Cowardly Sheep/"
)

harmlessGlobs=(
	"*.md"
	"open_files.txt"
	"Tmp/*"
)

isHarmless() {
	local path=$1 prefix glob
	for prefix in "${suitePrefixes[@]}"; do
		if [[ $path == "$prefix"* ]]; then
			return 1
		fi
	done
	for prefix in "${harmlessPrefixes[@]}"; do
		if [[ $path == "$prefix"* ]]; then
			return 0
		fi
	done
	for glob in "${harmlessGlobs[@]}"; do
		# shellcheck disable=SC2053 # The glob is meant to match as a pattern.
		if [[ $path == $glob ]]; then
			return 0
		fi
	done
	return 1
}

# The tests of each of these files register independently of the other files'
# tests (checked live: each file alone passes the same tests as in the full run).
isTestFile() {
	[[ $1 == Mods/HelloWorld/*-tests.lua && $1 != Mods/HelloWorld/*/* ]]
}

seen=0
testFiles=()
while IFS= read -r path; do
	if [[ -z $path ]]; then
		continue
	fi
	seen=$((seen + 1))
	if isTestFile "$path"; then
		testFiles+=("${path##*/}")
	elif ! isHarmless "$path"; then
		echo all
		exit 0
	fi
done

if ((seen == 0)); then
	echo all
elif ((${#testFiles[@]} == 0)); then
	echo none
else
	printf '%s\n' "${testFiles[@]}" | sort -u
fi
