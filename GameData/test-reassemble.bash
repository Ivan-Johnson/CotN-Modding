#!/usr/bin/env bash
#
# Tests for reassemble-scrape.bash. They build scrape directories from
# generated logs, so nothing needs the game.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly under_test="$script_dir/reassemble-scrape.bash"

work="$(mktemp -d)"
readonly work
trap 'rm -rf "$work"' EXIT

failures=0

fail() {
	echo "  FAIL: $*" >&2
	failures=$((failures + 1))
}

# `chunk NAME INDEX TOTAL TEXT` prints one chunk line as the mod logs it,
# with TEXT as the dataset's piece.
chunk() {
	local encoded
	encoded="$(printf '%s' "$4" | base64 -w0)"
	echo "[ScrapeGameData] DATA $1 $2/$3 $encoded"
}

# `begin CASE` makes an empty scrape directory in `scrape`.
begin() {
	echo "$1"
	scrape="$work/$1"
	mkdir -p "$scrape"
}

reassemble() {
	bash "$under_test" "$scrape" > "$work/out.log" 2>&1
}

begin joins-chunks-in-order-whatever-the-log-order
# Each chunk is base64 on its own, so only whole chunks can be joined if the
# pieces are aligned to 3 bytes.
{
	echo "game noise"
	chunk a.txt 2 3 'DEF'
	chunk b.txt 1 1 'only'
	chunk a.txt 3 3 'GHI'
	echo "[ScrapeGameData] emitted a.txt: 9 bytes"
	chunk a.txt 1 3 'ABC'
} > "$scrape/NecroDancer.log"
if reassemble; then
	[[ "$(cat "$scrape/a.txt")" == ABCDEFGHI ]] || fail "a.txt is $(cat "$scrape/a.txt")"
	[[ "$(cat "$scrape/b.txt")" == only ]] || fail "b.txt is $(cat "$scrape/b.txt")"
else
	fail "reassembly failed: $(cat "$work/out.log")"
fi

begin refuses-a-dataset-with-missing-chunks
{
	chunk a.txt 1 2 'ABC'
	chunk b.txt 1 1 'fine'
} > "$scrape/NecroDancer.log"
if reassemble; then
	fail "accepted a dataset with a missing chunk"
fi
[[ ! -e "$scrape/a.txt" ]] || fail "wrote the incomplete dataset"
[[ "$(cat "$scrape/b.txt")" == fine ]] || fail "dropped the complete dataset"

begin fails-when-the-mod-logged-an-error
{
	chunk a.txt 1 1 'ok'
	echo "[ScrapeGameData] ERROR b.txt: boom"
} > "$scrape/NecroDancer.log"
if reassemble; then
	fail "accepted a scrape with an ERROR"
fi
[[ "$(cat "$scrape/a.txt")" == ok ]] || fail "dropped the dataset that did complete"

if ((failures > 0)); then
	echo "$failures failure(s)" >&2
	exit 1
fi
echo "all passed"
