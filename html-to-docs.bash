#!/usr/bin/env bash
#
# Convert a tree of raw CotN documentation HTML into markdown and man pages.
#
# SRC_DIR is searched recursively for *.html files; anything else in it is
# ignored. The HTML and markdown output trees mirror SRC_DIR's directory
# structure; the man pages are flat, as `man` expects.
#
# Writes: DST_DIR/minimal-html/  (just the <article> of each page)
#         DST_DIR/markdown/
#         DST_DIR/share/man/manN/
#
# Usage:
#   ./html-to-docs.bash SRC_DIR DST_DIR

set -euo pipefail

readonly PANDOC_TO='commonmark-alerts-ascii_identifiers-attributes-autolink_bare_uris-bracketed_spans-definition_lists-east_asian_line_breaks-emoji-fancy_lists-fenced_divs-footnotes-gfm_auto_identifiers-hard_line_breaks-implicit_figures-implicit_header_references-pipe_tables-raw_attribute-raw_html-rebase_relative_paths-smart-sourcepos-strikeout-subscript-superscript-task_lists-tex_math_dollars-tex_math_gfm-wikilinks_title_after_pipe-wikilinks_title_before_pipe-yaml_metadata_block'

# The documented modules are a Lua API, so they belong in the "library calls"
# section.
readonly MAN_SECTION=3
readonly MAN_HEADER='Crypt of the NecroDancer Modding Documentation'

usage() {
	echo "Usage: ${BASH_SOURCE[0]} SRC_DIR DST_DIR" >&2
}

# Strip everything outside of the page's <article> element.
to_minimal_html() {
	local old_path="$1" dst="$2" relative_path="$3"

	local new_path="$dst/$relative_path"
	mkdir -p "$(dirname "$new_path")"
	htmlq article --ignore-whitespace --pretty --filename "$old_path" --output "$new_path"
}

to_markdown() {
	local old_path="$1" dst="$2" relative_path="$3"

	local new_path="$dst/${relative_path%.html}.md"
	# Collapse `foo/index.html` into `foo.md`, but leave a top level
	# `index.html` alone; collapsing it would clobber the output root.
	if [[ "$relative_path" == */index.html ]]; then
		new_path="${new_path%/index.md}.md"
	fi

	mkdir -p "$(dirname "$new_path")"
	pandoc --from=html "--to=$PANDOC_TO" "$old_path" --output "$new_path"
}

# The name a page is published under, e.g. both `foo/index.html` and `foo.html`
# document `foo`. Directories are dropped; the upstream page names are already
# fully qualified, so they are unique on their own.
page_name() {
	local relative_path="$1"

	local name="${relative_path%.html}"
	name="${name%/index}"
	echo "${name##*/}"
}

to_man() {
	local old_path="$1" dst="$2" relative_path="$3"

	local name
	name="$(page_name "$relative_path")"
	local new_path="$dst/$name.$MAN_SECTION"

	# The man namespace is flat, so distinct pages sharing a name would
	# silently clobber each other.
	if [[ -e "$new_path" ]]; then
		echo "Man page name '$name' is claimed by more than one page; '$relative_path' collides" >&2
		exit 1
	fi

	pandoc --from=html --to=man --standalone \
		--metadata "title=$name" \
		--variable "section=$MAN_SECTION" \
		--variable "header=$MAN_HEADER" \
		"$old_path" --output "$new_path"
}

# Escape a literal string so that it can be used in a sed basic regex.
quote_bre() {
	printf '%s' "$1" | sed 's|[][\\.*^$]|\\&|g'
}

# A page's HTML with the depth of its relative links normalized away.
#
# The crawler rewrites each copy of a page so that its links are relative to
# that copy's own directory. Relative to `foo.html`, a sibling `bar` is spelled
# `bar` and a child is spelled `foo/baz`; relative to `foo/index.html`, those
# same targets are spelled `../bar` and `baz`. Dropping every leading `../` and
# `foo/` from quoted attribute values therefore spells both copies alike.
normalize_link_depth() {
	local path="$1" name
	name="$(quote_bre "$2")"

	sed -e "s|\([\"']\)\.\./|\1|g" -e "s|\([\"']\)$name/|\1|g" "$path"
}

# Verify that the two copies of a page really are the same page.
#
# They are never byte-identical, since their relative links are written from
# different directories, but they must agree once that is normalized away.
assert_same_page() {
	local shallow="$1" deep="$2" name="$3"

	if ! cmp --silent \
		<(normalize_link_depth "$shallow" "$name") \
		<(normalize_link_depth "$deep" "$name"); then
		echo "'$shallow' and '$deep' should be two copies of the page '$name', but they differ by more than the depth of their relative links" >&2
		return 1
	fi
}

# The *.html files in `src` that represent distinct pages, in a stable order.
#
# The crawl mirrors a page reachable at `foo` as both `foo.html` and
# `foo/index.html`. The two are the same page, so only the `index.html` copy is
# kept.
list_pages() {
	local src="$1"

	local path deep name
	while IFS= read -r path; do
		deep="${path%.html}/index.html"
		if [[ -f "$deep" ]]; then
			name="${path%.html}"
			assert_same_page "$path" "$deep" "${name##*/}" || return 1
			continue
		fi
		echo "$path"
	done < <(find "$src" -name '*.html' | LC_ALL=C sort)
}

# Run `convert` over every page in `src`, writing the results into `dst`.
# `convert` is called as `convert OLD DST REL`, where REL is OLD's path relative
# to `src` and DST is the output root. The converter picks OLD's destination
# path within DST and creates whatever subdirectories it needs.
run_pass() {
	local src="$1" dst="$2" convert="$3"

	mkdir -p "$dst"

	# Collected up front rather than streamed in, so that a failed assertion in
	# `list_pages` aborts the run. `set -e` does not fire inside the subshell
	# of a command substitution, so the failure is propagated by hand.
	local pages
	pages="$(list_pages "$src")" || return 1

	local old_path relative_path
	while IFS= read -r old_path; do
		[[ -n "$old_path" ]] || continue
		relative_path="${old_path#"$src"/}"
		"$convert" "$old_path" "$dst" "$relative_path"
	done <<< "$pages"
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

mkdir -p "$dst_dir"
run_pass "$src_dir" "$dst_dir/minimal-html" to_minimal_html
run_pass "$dst_dir/minimal-html" "$dst_dir/markdown" to_markdown
run_pass "$dst_dir/minimal-html" "$dst_dir/share/man/man$MAN_SECTION" to_man
