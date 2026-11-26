#!/usr/bin/env bash
#
# Corpus wide checks over a built documentation tree.
#
# The conversion's own tests convert handwritten crawls of two or three pages.
# These run over a whole build instead, which is where a regression that only
# shows up at scale, or only on one odd upstream page, surfaces.
#
#   nix flake check
#
# The `man` assertions search an index that `man` locates through MANPATH, which
# the `corpus` check gets for free by putting the docs derivation on PATH. Run by
# hand, they fail unless it is supplied:
#
#   docs="$(nix build --no-link --print-out-paths .#docs)"
#   MANPATH="$docs/official/man" nix develop -c ./AuthoredDocs/check-docs.bash "$docs"

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

# The relative links in `path`, one per line, with any query stripped and any
# `#fragment` kept. Anything that already names where it goes is not ours to
# resolve.
relative_targets() {
	local path="$1" href fragment
	local -a hrefs=()

	case "$path" in
	*.html) mapfile -t hrefs < <(htmlq --attribute href a <"$path") ;;
	*.md) mapfile -t hrefs < <(grep -oE '\]\([^)]*\)' "$path" | sed -e 's|^](||' -e 's|)$||') ;;
	*) return 0 ;;
	esac

	for href in "${hrefs[@]}"; do
		[[ "$href" != *:* && "$href" != //* ]] || continue
		fragment=""
		if [[ "$href" == *'#'?* ]]; then
			fragment="#${href#*#}"
		fi
		href="${href%%[#?]*}$fragment"
		[[ -n "$href" ]] || continue
		echo "$href"
	done
}

# The GitHub-style anchor of each heading in Markdown file `path`, one per line:
# lower case, punctuation dropped, spaces turned into hyphens. Headings inside
# fenced code are not headings.
heading_slugs() {
	local path="$1"

	awk '/^```/ { fenced = !fenced; next } !fenced && /^#{1,6} / { sub(/^#+ +/, ""); print }' "$path" |
		tr '[:upper:]' '[:lower:]' |
		sed -e 's/[^a-z0-9 _-]//g' -e 's/ /-/g'
}

# Every link that conversion was supposed to follow still lands on a page.
assert_links_resolve() {
	local tree="$1"
	local path link target checked=0

	while IFS= read -r path; do
		while IFS= read -r link; do
			target="${link%%#*}"
			[[ -n "$target" ]] || continue
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
	local pages tree count dir

	for dir in raw official authored game-data; do
		[[ -d "$docs/$dir" ]] || fail "$docs has no $dir/"
	done

	pages="$(find "$docs/official/minimal-html" -name '*.html' | wc -l)"
	[[ "$pages" -gt 0 ]] || fail "$docs: no pages were converted"

	for tree in "official/markdown:*.md" "official/man/man$MAN_SECTION:*.$MAN_SECTION"; do
		count="$(find "$docs/${tree%%:*}" -name "${tree##*:}" | wc -l)"
		[[ "$count" -eq "$pages" ]] ||
			fail "${tree%%:*} holds $count pages, minimal-html holds $pages"
	done
}

# The generated navigation page should surface the sidebar in all three output
# formats, without displacing the page it was harvested from.
assert_navigation_is_published() {
	local docs="$1"
	local root="vortexbuffer.com/synchrony/docs"
	local html="$docs/official/minimal-html/$root/cotn-docs.html"
	local markdown="$docs/official/markdown/$root/cotn-docs.md"
	local man="$docs/official/man/man$MAN_SECTION/cotn-docs.$MAN_SECTION"

	grep -q 'href="overview/index.html"' "$html" ||
		fail "$html does not show the recovered navigation"
	grep -q 'href="modules/index.html"' "$html" ||
		fail "$html does not show the recovered navigation"
	grep -q '^# Synchrony API Documentation$' "$markdown" ||
		fail "$markdown does not show the recovered navigation"
	grep -q '](modules.md)' "$markdown" ||
		fail "$markdown does not show the recovered navigation"
	grep -q '](overview.md)' "$markdown" ||
		fail "$markdown does not show the recovered navigation"
	grep -qE '^\.SH NAME$' "$man" ||
		fail "$man has no NAME section"
	grep -q '^cotn-docs \\- Synchrony API Documentation navigation$' "$man" ||
		fail "$man does not describe the navigation index"
}

# The upstream landing page is a page like any other, so harvesting its sidebar
# must leave its own content published in all three trees.
assert_landing_page_survives() {
	local docs="$1"
	local marker='Once Synchrony is installed'
	local html="$docs/official/minimal-html/vortexbuffer.com/synchrony/docs/index.html"
	local markdown="$docs/official/markdown/vortexbuffer.com/synchrony/docs.md"
	local man="$docs/official/man/man$MAN_SECTION/docs.$MAN_SECTION"

	grep -q "$marker" "$html" ||
		fail "$html no longer holds the landing page's own content"
	grep -q "$marker" "$markdown" ||
		fail "$markdown no longer holds the landing page's own content"
	grep -q '^docs \\- Crypt of the NecroDancer: Synchrony Modding Documentation$' "$man" ||
		fail "$man is not the landing page's own man page"
}

# The upstream chrome that conversion strips has stayed stripped.
assert_no_chrome() {
	local docs="$1"

	! grep -rl '¶' "$docs/official" ||
		fail "the files above still carry heading permalinks"
}

# Every page can be found by `apropos`, not just read by name.
assert_man_pages_are_indexable() {
	local docs="$1"
	local man="$docs/official/man/man$MAN_SECTION"
	local path

	[[ -e "$docs/official/man/index.db" ]] ||
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

# Every `#fragment` in a Markdown link names a heading of the Markdown page it
# points at.
assert_anchors_resolve() {
	local tree="$1"
	local path link target fragment page checked=0

	while IFS= read -r path; do
		while IFS= read -r link; do
			[[ "$link" == *'#'* ]] || continue
			target="${link%%#*}"
			fragment="${link#*#}"
			page="$(dirname "$path")/$target"
			[[ -n "$target" ]] || page="$path"
			[[ "$page" == *.md && -f "$page" ]] || continue
			checked=$((checked + 1))
			heading_slugs "$page" | grep -qxF -- "$fragment" ||
				fail "$path links to $target#$fragment, which is no heading there"
		done < <(relative_targets "$path")
	done < <(find "$tree" -type f -name '*.md')

	[[ "$checked" -gt 0 ]] || fail "$tree: no anchors found to check"
}

# Player pages that still carry wording the cotn-document-mechanic sweep
# removes: see the player-page bullet under Conventions in AuthoredDocs/AGENTS.md.
readonly UNSWEPT_PLAYER_PAGES=(
	chests-and-loot.md
	king-conga.md
	stairs-and-levels.md
	traps.md
)

# A player page states conclusions, so the wording of an experiment's setup or
# of a claim it could not conclude is not on it. Matched case-blind across line
# breaks, since prose wraps anywhere.
assert_player_pages_state_conclusions() {
	local tree="$1"
	local banned='`guess`|untested|not measured|measured as|seen in one|no-beat mode|CotN 4\.'
	local path page found checked=0

	while IFS= read -r path; do
		checked=$((checked + 1))
		page="$(basename "$path")"
		found="$(tr '\n' ' ' <"$path" | tr -s ' ' | grep -oiE "$banned" | sort -u | paste -sd, -)" || true
		if [[ " ${UNSWEPT_PLAYER_PAGES[*]} " == *" $page "* ]]; then
			[[ -n "$found" ]] ||
				fail "$path is clean: delete it from UNSWEPT_PLAYER_PAGES"
		elif [[ -n "$found" ]]; then
			fail "$path is a player page but says: $found"
		fi
	done < <(grep -l '^For players\.' "$tree"/*.md)

	for page in "${UNSWEPT_PLAYER_PAGES[@]}"; do
		[[ -f "$tree/$page" ]] ||
			fail "UNSWEPT_PLAYER_PAGES names $page, which $tree does not hold"
	done

	[[ "$checked" -gt 0 ]] || fail "$tree: no player pages found to check"
}

main() {
	local docs="$1"

	assert_trees_agree "$docs"
	assert_navigation_is_published "$docs"
	assert_landing_page_survives "$docs"
	assert_no_chrome "$docs"
	assert_links_resolve "$docs/official/minimal-html"
	assert_links_resolve "$docs/official/markdown"
	assert_links_resolve "$docs/authored"
	assert_anchors_resolve "$docs/authored"
	assert_player_pages_state_conclusions "$docs/authored"
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
