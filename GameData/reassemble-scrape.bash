#!/usr/bin/env bash
#
# Rebuild a scrape's datasets from the chunks the ScrapeGameData mod logged.
#
# Usage:
#   ./reassemble-scrape.bash SCRAPE_DIR
#
# Reads SCRAPE_DIR/NecroDancer.log and writes each dataset beside it. Exits
# non-zero if a dataset is missing chunks or the mod logged an ERROR; the
# datasets that did complete are still written.

set -euo pipefail

readonly CHUNK_PATTERN='\[ScrapeGameData\] DATA [^ ]+ [0-9]+/[0-9]+ [A-Za-z0-9+/=]*'

main() {
	local scrape="$1"
	local log="$scrape/NecroDancer.log"

	local chunks
	chunks="$(mktemp)"
	trap "rm -f '$chunks'" EXIT

	# No chunks at all is not an error here: the dataset checks in
	# push-game-data.bash catch an empty scrape.
	grep -oE "$CHUNK_PATTERN" "$log" > "$chunks" || true

	local status=0
	local name
	while read -r name; do
		local total
		total="$(awk -v n="$name" '$3 == n {split($4, p, "/"); print p[2]; exit}' "$chunks")"
		local count
		count="$(awk -v n="$name" '$3 == n' "$chunks" | wc -l)"
		if ((count != total)); then
			echo "reassemble-scrape: $name has $count of $total chunks" >&2
			status=1
			continue
		fi
		awk -v n="$name" '$3 == n {split($4, p, "/"); print p[1], $5}' "$chunks" \
			| sort -n \
			| cut -d' ' -f2 \
			| tr -d '\n' \
			| base64 -d > "$scrape/$name"
	done < <(awk '{print $3}' "$chunks" | sort -u)

	if grep -F '[ScrapeGameData] ERROR' "$log"; then
		status=1
	fi
	return "$status"
}

main "$@"
