#!/usr/bin/env bash
#
# Push a scrape of the game's data to the `game-data` branch of the CotN-docs
# mirror.
#
# Usage:
#   ./push-game-data.bash [SCRAPE_DIR]   # default: the newest under Tmp/scrape-game-data/
#
# `REPO_ROOT` can be overridden, which is how the tests avoid needing a
# checkout.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
REPO_ROOT="${REPO_ROOT:-$script_dir}"
readonly REPO_ROOT

# shellcheck source=../DocDownloader/push-to-mirror.bash
source "$script_dir/../DocDownloader/push-to-mirror.bash"

readonly BRANCH='game-data'
readonly DATASETS=(
	necrodancer.xml
	component-defaults.json
	entity-prototypes.json
	script-files.json
	module-apis.json
	versions.json
)

newest_scrape() {
	local scrapes
	scrapes="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)/Tmp/scrape-game-data"
	local newest
	newest="$(find "$scrapes" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
	if [[ -z "$newest" ]]; then
		echo "push-game-data: no scrapes under $scrapes" >&2
		return 1
	fi
	echo "$newest"
}

# Refuse a scrape that is incomplete or that the mod itself flagged as failed.
check_scrape() {
	local scrape="$1"
	local dataset
	for dataset in "${DATASETS[@]}"; do
		if [[ ! -s "$scrape/$dataset" ]]; then
			echo "push-game-data: $scrape/$dataset is missing or empty" >&2
			return 1
		fi
	done
	if [[ ! -f "$scrape/NecroDancer.log" ]]; then
		echo "push-game-data: $scrape/NecroDancer.log is missing, so errors can't be ruled out" >&2
		return 1
	fi
	if grep -qF '[ScrapeGameData] ERROR' "$scrape/NecroDancer.log"; then
		echo "push-game-data: $scrape's log reports a scrape error" >&2
		return 1
	fi
}

main() {
	local scrape="${1:-}"
	if [[ -z "$scrape" ]]; then
		scrape="$(newest_scrape)"
	fi
	check_scrape "$scrape"

	local stage
	stage="$(mktemp -d)"
	echo "$stage"

	local dataset
	for dataset in "${DATASETS[@]}"; do
		if [[ "$dataset" == *.json ]]; then
			# The mod emits each JSON dataset as a single line, which Git
			# handles poorly when it gets this long.
			jq . "$scrape/$dataset" > "$stage/$dataset"
		else
			cp "$scrape/$dataset" "$stage/$dataset"
		fi
	done
	cp "$script_dir/game-data-README.md" "$stage/README.md"
	basename "$scrape" > "$stage/scrape-dir.txt"

	push_to_mirror "$BRANCH" "$REPO_ROOT" "$stage"
}

main "$@"
