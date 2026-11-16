#!/usr/bin/env bash
#
# THIS IS A PROOF OF CONCEPT
# (CotN-Modding/TODO/better-docs.md, step "Big picture doc cleanup/reorg")
#
# Distill a rendered Markdown tree down to the pages worth keeping as prose.
#
# Reads SRC_DIR (the `markdown/` tree from `html-to-docs.bash`) and writes
# DST_DIR/:
#   docs.md                 the landing page, verbatim
#   overview/NN-title.md    `overview.md`, one file per top-level section
#   components/NAME.md      each component page minus its field tables, and
#                           only the pages with a meaningful amount of prose
#
# Everything else (module and event pages) is API signatures, which this tree
# deliberately leaves out.
#
# Usage:
#   ./useful-docs.bash SRC_DIR DST_DIR

set -euo pipefail

# A component page with fewer prose words than this is mostly one-liners that
# only make sense next to the API reference.
readonly MIN_COMPONENT_WORDS=100

usage() {
	echo "Usage: ${BASH_SOURCE[0]} SRC_DIR DST_DIR" >&2
}

# A component page without its field tables, keeping only the `###` headings
# that still have a description under them.
strip_component() {
	awk '
		function flush() {
			if (heading != "" && body ~ /[^[:space:]]/) {
				printf "%s\n%s", heading, body
			}
			heading = ""
			body = ""
		}
		/^# / { print $0 "\n"; next }
		/^### / { flush(); heading = $0 "\n"; next }
		/^\|/ { next }
		heading != "" { body = body $0 "\n" }
		END {
			flush()
		}
	' "$1" | cat -s
}

# `overview.md` is one file for every top-level `#` section, with whatever
# precedes the first section as an introduction.
split_overview() {
	local src="$1" dst="$2"

	mkdir -p "$dst"
	awk -v dst="$dst" '
		function slug(title) {
			title = tolower(title)
			gsub(/[^a-z0-9]+/, "-", title)
			gsub(/^-|-$/, "", title)
			return title
		}
		/^```/ { fenced = !fenced }
		!fenced && /^# / {
			n++
			title = substr($0, 3)
			out = sprintf("%s/%02d-%s.md", dst, n, slug(title))
		}
		{
			if (out == "") {
				out = sprintf("%s/00-introduction.md", dst)
			}
			print > out
		}
	' "$src"
}

word_count() {
	wc -w <"$1"
}

if [[ "$#" -ne 2 ]]; then
	usage
	exit 1
fi

src_dir="$1"
dst_dir="$2"
readonly src_dir dst_dir

if [[ ! -d "$src_dir" ]]; then
	echo "SRC_DIR '$src_dir' is not a directory" >&2
	exit 1
fi

mkdir -p "$dst_dir/components" "$dst_dir/overview"

landing="$(find "$src_dir" -name docs.md | head -n 1)"
if [[ -z "$landing" ]]; then
	echo "No docs.md found under '$src_dir'" >&2
	exit 1
fi
cp "$landing" "$dst_dir/docs.md"

overview="$(find "$src_dir" -name overview.md | head -n 1)"
if [[ -z "$overview" ]]; then
	echo "No overview.md found under '$src_dir'" >&2
	exit 1
fi
split_overview "$overview" "$dst_dir/overview"

scratch="$(mktemp)"
trap 'rm -f "$scratch"' EXIT

while IFS= read -r page; do
	strip_component "$page" >"$scratch"
	if [[ "$(word_count "$scratch")" -lt "$MIN_COMPONENT_WORDS" ]]; then
		continue
	fi
	cp "$scratch" "$dst_dir/components/$(basename "$page")"
done < <(find "$src_dir" -path '*/components/*.md' | LC_ALL=C sort)
