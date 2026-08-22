#!/usr/bin/env bash
#
# Tests for html-to-docs.bash.
#
# Each case builds a throwaway crawl in a temporary directory, converts it, and
# checks the result. The fixtures are written here rather than committed so that
# a case and its near-miss variants stay side by side.
#
# Needs the same tools as the conversion itself, so run it in the dev shell:
#
#   nix develop -c ./test-html-to-docs.bash
#
# `nix flake check` runs it too, as a derivation.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly under_test="$script_dir/html-to-docs.bash"

work="$(mktemp -d)"
readonly work
trap 'rm -rf "$work"' EXIT

failures=0
current_case=

fail() {
	echo "  FAIL: $*" >&2
	failures=$((failures + 1))
}

# Start a new case. Sets `src` to an empty crawl directory and `dst` to the
# directory its conversion should be written to.
begin() {
	current_case="$1"
	echo "$current_case"

	src="$work/$current_case/src"
	dst="$work/$current_case/dst"
	mkdir -p "$src"
}

# Write a page containing `body` to `path`, creating parent directories. Every
# crawled page leads with a heading, and the conversion insists on one to
# summarize the page by, so `body` is given a placeholder unless it brings its
# own.
write_page() {
	local path="$1" body="$2"

	[[ "$body" == *"<h1"* ]] || body="<h1>Heading</h1>$body"
	write_raw_page "$path" "$body"
}

# Write a page whose body is used exactly as given, heading or not.
write_raw_page() {
	local path="$1" body="$2"

	mkdir -p "$(dirname "$path")"
	printf '<html><body><article>%s</article></body></html>\n' "$body" >"$path"
}

# Convert `src` into `dst`, capturing all output. Returns the exit status of the
# script under test.
convert() {
	bash "$under_test" "$src" "$dst" >"$work/output" 2>&1
}

convert_expecting_success() {
	if ! convert; then
		fail "conversion failed:"$'\n'"$(cat "$work/output")"
		return 1
	fi
}

# Assert that the conversion fails, and that it explains itself by printing
# something matching `pattern`.
convert_expecting_failure() {
	local pattern="$1"

	if convert; then
		fail "conversion unexpectedly succeeded"
		return 0
	fi
	if ! grep -q -- "$pattern" "$work/output"; then
		fail "expected an error matching '$pattern', but got:"$'\n'"$(cat "$work/output")"
	fi
}

assert_exists() {
	[[ -e "$1" ]] || fail "expected '${1#"$dst"/}' to exist"
}

assert_missing() {
	[[ ! -e "$1" ]] || fail "expected '${1#"$dst"/}' not to exist"
}

assert_matches() {
	local path="$1" pattern="$2"

	if [[ ! -e "$path" ]]; then
		fail "expected '${path#"$dst"/}' to exist"
		return
	fi
	grep -q -- "$pattern" "$path" ||
		fail "expected '${path#"$dst"/}' to match '$pattern'"
}

assert_not_matches() {
	local path="$1" pattern="$2"

	if [[ ! -e "$path" ]]; then
		fail "expected '${path#"$dst"/}' to exist"
		return
	fi
	! grep -q -- "$pattern" "$path" ||
		fail "expected '${path#"$dst"/}' not to match '$pattern'"
}

# The crawl mirrors a page reachable at `foo` as both `foo.html` and
# `foo/index.html`, which must be recognized as one page rather than two.
test_duplicate_pages_are_converted_once() {
	begin duplicate-pages-are-converted-once

	write_page "$src/page.html" '<a href="bar.html">b</a><a href="page/child.html">c</a>'
	write_page "$src/page/index.html" '<a href="../bar.html">b</a><a href="child.html">c</a>'
	write_page "$src/bar.html" 'bar'

	convert_expecting_success || return

	assert_missing "$dst/minimal-html/page.html"
	assert_exists "$dst/minimal-html/page/index.html"
	assert_exists "$dst/markdown/page.md"
	assert_exists "$dst/share/man/man3/page.3"
}

# Two copies of a page differ only in the depth of their relative links; any
# other difference means they are not the same page after all.
test_mismatched_copies_are_rejected() {
	begin mismatched-copies-are-rejected

	write_page "$src/page.html" '<a href="bar.html">b</a>'
	write_page "$src/page/index.html" '<a href="../bar.html">b</a>EXTRA'

	convert_expecting_failure 'differ by more than'

	assert_missing "$dst/markdown"
	assert_missing "$dst/share"
}

test_copies_with_different_links_are_rejected() {
	begin copies-with-different-links-are-rejected

	write_page "$src/page.html" '<a href="bar.html">b</a>'
	write_page "$src/page/index.html" '<a href="../elsewhere.html">b</a>'

	convert_expecting_failure 'differ by more than'
}

test_output_layout() {
	begin output-layout

	write_page "$src/index.html" 'root'
	write_page "$src/section/index.html" 'section'
	write_page "$src/section/leaf.html" 'leaf'
	printf 'not html\n' >"$src/notes.txt"

	convert_expecting_success || return

	# The HTML and markdown trees mirror the crawl, except that
	# `foo/index.html` collapses to `foo.md`. A top level `index.html` has no
	# `foo` to collapse into, so it stays put.
	assert_exists "$dst/markdown/index.md"
	assert_exists "$dst/markdown/section.md"
	assert_exists "$dst/markdown/section/leaf.md"

	# The man tree is flat.
	assert_exists "$dst/share/man/man3/index.3"
	assert_exists "$dst/share/man/man3/section.3"
	assert_exists "$dst/share/man/man3/leaf.3"
	assert_missing "$dst/share/man/man3/section"

	# Anything that is not a page is ignored.
	assert_missing "$dst/minimal-html/notes.txt"
	assert_missing "$dst/markdown/notes.txt"
}

test_man_pages_are_titled_after_their_page() {
	begin man-pages-are-titled-after-their-page

	write_page "$src/modules/necro.game.object.Map/index.html" '<h1>Module Map</h1>'

	convert_expecting_success || return

	assert_matches "$dst/share/man/man3/necro.game.object.Map.3" \
		'^\.TH "necro.game.object.Map" "3"'
}

# The man namespace is flat, so two distinct pages sharing a name would
# otherwise silently clobber each other.
test_colliding_man_pages_are_rejected() {
	begin colliding-man-pages-are-rejected

	write_page "$src/modules/dup.html" 'one'
	write_page "$src/components/dup.html" 'two'

	convert_expecting_failure 'claimed by more than one page'
}

# Upstream hangs a `¶` permalink off every heading. It is website chrome, and
# survives into both output formats as a stray character if it is not dropped.
test_heading_permalinks_are_dropped() {
	begin heading-permalinks-are-dropped

	write_page "$src/page.html" \
		'<h1 id="t">Title<a class="headerlink" href="index.html#t" title="Permanent link">&para;</a></h1>'

	convert_expecting_success || return

	assert_not_matches "$dst/minimal-html/page.html" 'headerlink'
	assert_not_matches "$dst/markdown/page.md" '¶'
	assert_not_matches "$dst/share/man/man3/page.3" '¶'

	# Only the anchor goes; the heading it was attached to stays.
	assert_matches "$dst/markdown/page.md" '^# Title$'
}

# A link written against the crawl names a `.html` file, relative to the copy of
# the page it was written in. Conversion renames the file and, when
# `foo/index.html` collapses to `foo.md`, moves it up a level; the link has to
# follow it through both.
test_links_between_pages_are_rewritten() {
	begin links-between-pages-are-rewritten

	write_page "$src/index.html" '<a href="page.html">p</a>'
	write_page "$src/page.html" '<a href="index.html">i</a>'
	write_page "$src/page/index.html" '<a href="../index.html">i</a>'

	convert_expecting_success || return

	# `page.html` was dropped as a duplicate, so the link has to name the copy
	# that survived instead.
	assert_matches "$dst/minimal-html/index.html" 'href="page/index.html"'
	assert_matches "$dst/minimal-html/page/index.html" 'href="../index.html"'

	# In markdown the target is `page.md`, a sibling of `index.md`, and
	# `page.md` sits one level above where its own copy was crawled.
	assert_matches "$dst/markdown/index.md" '](page\.md)'
	assert_matches "$dst/markdown/page.md" '](index\.md)'
}

test_links_survive_nesting() {
	begin links-survive-nesting

	write_page "$src/a/b/index.html" '<a href="../c.html">c</a>'
	write_page "$src/a/c/index.html" 'c'

	convert_expecting_success || return

	assert_matches "$dst/minimal-html/a/b/index.html" 'href="../c/index.html"'
	assert_matches "$dst/markdown/a/b.md" '](c\.md)'
}

test_link_fragments_are_kept() {
	begin link-fragments-are-kept

	write_page "$src/index.html" '<a href="page.html#sec">p</a>'
	write_page "$src/page/index.html" 'p'

	convert_expecting_success || return

	assert_matches "$dst/minimal-html/index.html" 'href="page/index.html#sec"'
	assert_matches "$dst/markdown/index.md" '](page\.md#sec)'
}

# Only links that name another page are ours to redirect.
test_foreign_links_are_left_alone() {
	begin foreign-links-are-left-alone

	write_page "$src/index.html" \
		'<a href="https://example.com/a.html">a</a><a href="#here">h</a><a href="uncrawled.html">u</a>'

	convert_expecting_success || return

	assert_matches "$dst/minimal-html/index.html" 'href="https://example.com/a.html"'
	assert_matches "$dst/minimal-html/index.html" 'href="#here"'
	assert_matches "$dst/minimal-html/index.html" 'href="uncrawled.html"'
}

# `man` works without a NAME section, but `whatis` and `apropos` index nothing
# without one, which leaves a page findable only by guessing its name.
test_man_pages_have_a_name_section() {
	begin man-pages-have-a-name-section

	write_page "$src/modules/necro.game.object.Map/index.html" '<h1>Module Map</h1>'

	convert_expecting_success || return

	local page="$dst/share/man/man3/necro.game.object.Map.3"
	assert_matches "$page" '^\.SH NAME$'
	assert_matches "$page" '^necro\.game\.object\.Map \\- Module Map$'

	# NAME has to come before the body for `whatis` to find it.
	assert_matches "$page" '^\.TH .*$'
	[[ "$(grep -n '^\.SH NAME$' "$page" | cut -d: -f1)" -lt \
		"$(grep -n '^\.SH Module Map$' "$page" | cut -d: -f1)" ]] ||
		fail "expected NAME to precede the body"
}

# Long pages use several top level headings; the first one titles the page.
test_name_summary_comes_from_the_first_heading() {
	begin name-summary-comes-from-the-first-heading

	write_page "$src/overview/index.html" \
		'<h1>Synchrony API   overview</h1><p>x</p><h1>Scripting</h1>'

	convert_expecting_success || return

	# Whitespace inside the heading is collapsed, so NAME stays one tidy line.
	assert_matches "$dst/share/man/man3/overview.3" \
		'^overview \\- Synchrony API overview$'
	assert_not_matches "$dst/share/man/man3/overview.3" '\\- Scripting'
}

# A page with no heading has nothing to be summarized by, and would be
# published as a man page that `apropos` cannot describe.
test_pages_without_a_heading_are_rejected() {
	begin pages-without-a-heading-are-rejected

	write_raw_page "$src/page.html" '<p>no heading here</p>'

	convert_expecting_failure 'no heading to summarize it'
}

test_duplicate_pages_are_converted_once
test_mismatched_copies_are_rejected
test_copies_with_different_links_are_rejected
test_output_layout
test_man_pages_are_titled_after_their_page
test_colliding_man_pages_are_rejected
test_heading_permalinks_are_dropped
test_links_between_pages_are_rewritten
test_links_survive_nesting
test_link_fragments_are_kept
test_foreign_links_are_left_alone
test_man_pages_have_a_name_section
test_name_summary_comes_from_the_first_heading
test_pages_without_a_heading_are_rejected

if [[ "$failures" -ne 0 ]]; then
	echo "$failures assertion(s) failed" >&2
	exit 1
fi
echo "all tests passed"
