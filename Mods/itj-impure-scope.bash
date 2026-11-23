# Reads the repo paths a change touches, one per line on stdin, and prints
# `none` if the live test suite (`itj-impure-tests`) cannot be affected by
# them, or `all` otherwise. Called by `build-release` (DevTools) from the git
# hooks, so a docs-only commit or push skips the ~90 s live run.
#
# Only known-harmless paths give `none`; every other path, and empty input
# (e.g. a message-only amend), gives `all`, so a new kind of file fails safe.
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

seen=0
while IFS= read -r path; do
	if [[ -z $path ]]; then
		continue
	fi
	seen=$((seen + 1))
	if ! isHarmless "$path"; then
		echo all
		exit 0
	fi
done

if ((seen == 0)); then
	echo all
else
	echo none
fi
