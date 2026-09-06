#!/usr/bin/env bash
#
# Corpus wide checks over a built documentation tree.
#
# The conversion's own tests convert handwritten crawls of two or three pages.
# These run over a whole build instead, which is where a regression that only
# shows up at scale, or only on one odd upstream page, surfaces.
#
#   nix build && nix develop -c ./check-docs.bash result

set -euo pipefail

if [[ -v DEBUG ]]; then
	set -x
fi

readonly MAN_SECTION=3

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

# The relative link targets in `path`, one per line, with any fragment or query
# stripped. Anything that already names where it goes is not ours to resolve.
relative_targets() {
	local path="$1" href
	local -a hrefs=()

	case "$path" in
	*.html) mapfile -t hrefs < <(htmlq --attribute href a <"$path") ;;
	*.md) mapfile -t hrefs < <(grep -oE '\]\([^)]*\)' "$path" | sed -e 's|^](||' -e 's|)$||') ;;
	*) return 0 ;;
	esac

	for href in "${hrefs[@]}"; do
		[[ "$href" != *:* && "$href" != //* && "$href" != '#'* ]] || continue
		href="${href%%[#?]*}"
		[[ -n "$href" ]] || continue
		echo "$href"
	done
}

# Every link that conversion was supposed to follow still lands on a page.
assert_links_resolve() {
	local tree="$1"
	local path target checked=0

	while IFS= read -r path; do
		while IFS= read -r target; do
			checked=$((checked + 1))
			[[ -e "$(dirname "$path")/$target" ]] ||
				fail "$path links to missing $target"
		done < <(relative_targets "$path")
	done < <(find "$tree" -type f)

	# A link extractor that has quietly stopped matching anything would
	# otherwise leave this passing over nothing at all.
	[[ "$checked" -gt 0 ]] || fail "$tree: no relative links found to check"
}

# The trees describe the same corpus, and it is not empty. Every check below
# passes trivially over nothing, so this is what makes them mean anything.
assert_trees_agree() {
	local docs="$1"
	local pages tree count

	pages="$(find "$docs/minimal-html" -name '*.html' | wc -l)"
	[[ "$pages" -gt 0 ]] || fail "$docs: no pages were converted"

	for tree in "markdown:*.md" "share/man/man$MAN_SECTION:*.$MAN_SECTION"; do
		count="$(find "$docs/${tree%%:*}" -name "${tree##*:}" | wc -l)"
		[[ "$count" -eq "$pages" ]] ||
			fail "${tree%%:*} holds $count pages, minimal-html holds $pages"
	done
}

# The generated landing page should surface the sidebar navigation in all
# three output formats.
assert_navigation_is_promoted() {
	local docs="$1"
	local html="$docs/minimal-html/vortexbuffer.com/synchrony/docs/index.html"
	local markdown="$docs/markdown/vortexbuffer.com/synchrony/docs.md"
	local man="$docs/share/man/man$MAN_SECTION/cotn-docs.$MAN_SECTION"

	grep -q 'href="overview/index.html"' "$html" ||
		fail "$html does not show the recovered navigation"
	grep -q 'href="modules/index.html"' "$html" ||
		fail "$html does not show the recovered navigation"
	grep -q '^# Synchrony API Documentation$' "$markdown" ||
		fail "$markdown does not show the recovered navigation"
	grep -q '](docs/modules.md)' "$markdown" ||
		fail "$markdown does not show the recovered navigation"
	grep -q '](docs/overview.md)' "$markdown" ||
		fail "$markdown does not show the recovered navigation"
	grep -qE '^\.SH NAME$' "$man" ||
		fail "$man has no NAME section"
	grep -q '^cotn-docs \\- Synchrony API Documentation navigation$' "$man" ||
		fail "$man does not describe the navigation index"
}

# The upstream chrome that conversion strips has stayed stripped.
assert_no_chrome() {
	local docs="$1"

	! grep -rl '¶' "$docs" ||
		fail "the files above still carry heading permalinks"
}

# Every page can be found by `apropos`, not just read by name.
assert_man_pages_are_indexable() {
	local docs="$1"
	local man="$docs/share/man/man$MAN_SECTION"
	local path

	[[ -e "$docs/share/man/index.db" ]] ||
		fail "$docs: no man index, so nothing is searchable"

	man -k cotn-docs || fail "Could not find cotn-docs"
}

# The docs are reachable as docs, and not merely present as files.
assert_man_pages_are_reachable() {
	local docs="$1"

	if ! man --where cotn-docs >/dev/null; then
		fail "The man pages are not setup correctly"
	fi
}

main() {
	local docs="$1"

	assert_trees_agree "$docs"
	assert_navigation_is_promoted "$docs"
	assert_no_chrome "$docs"
	assert_links_resolve "$docs/minimal-html"
	assert_links_resolve "$docs/markdown"
	assert_man_pages_are_indexable "$docs"
	assert_man_pages_are_reachable "$docs"

	if [[ "$failures" -ne 0 ]]; then
		echo "$failures check(s) failed" >&2
		exit 1
	fi
	echo "all checks passed"
}

if [[ "$#" -ne 1 ]]; then
	echo "usage: ${BASH_SOURCE[0]} DOCS_DIR" >&2
	exit 1
fi

main "$1"
