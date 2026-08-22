#!/usr/bin/env bash
#
# Convert a tree of raw CotN documentation HTML into markdown.
#
# SRC_DIR is searched recursively for *.html files; anything else in it is
# ignored. Both output trees mirror SRC_DIR's directory structure.
#
# Writes: DST_DIR/minimal-html/  (just the <article> of each page)
#         DST_DIR/markdown/
#
# Usage:
#   ./html-to-markdown.bash SRC_DIR DST_DIR

set -euo pipefail

readonly PANDOC_TO='commonmark-alerts-ascii_identifiers-attributes-autolink_bare_uris-bracketed_spans-definition_lists-east_asian_line_breaks-emoji-fancy_lists-fenced_divs-footnotes-gfm_auto_identifiers-hard_line_breaks-implicit_figures-implicit_header_references-pipe_tables-raw_attribute-raw_html-rebase_relative_paths-smart-sourcepos-strikeout-subscript-superscript-task_lists-tex_math_dollars-tex_math_gfm-wikilinks_title_after_pipe-wikilinks_title_before_pipe-yaml_metadata_block'

usage() {
	echo "Usage: ${BASH_SOURCE[0]} SRC_DIR DST_DIR" >&2
}

# Strip everything outside of the page's <article> element.
to_minimal_html() {
	local old_path="$1" new_path="$2"
	htmlq article --ignore-whitespace --pretty --filename "$old_path" --output "$new_path"
}

to_markdown() {
	local old_path="$1" new_path="$2" relative_path="$3"

	new_path="${new_path%.html}.md"
	# Collapse `foo/index.html` into `foo.md`, but leave a top level
	# `index.html` alone; collapsing it would clobber the output root.
	if [[ "$relative_path" == */index.html ]]; then
		new_path="${new_path%/index.md}.md"
	fi

	pandoc --from=html "--to=$PANDOC_TO" "$old_path" --output "$new_path"
}

# Run `convert` over every *.html file in `src`, writing the results into `dst`.
# `convert` is called as `convert OLD NEW REL`, where REL is OLD's path relative
# to `src` and NEW is REL resolved against `dst`; the converter is free to
# change NEW's extension.
run_pass() {
	local src="$1" dst="$2" convert="$3"

	mkdir -p "$dst"

	local old_path relative_path new_path
	while IFS= read -r old_path; do
		relative_path="${old_path#"$src"/}"
		new_path="$dst/$relative_path"
		mkdir -p "$(dirname "$new_path")"
		"$convert" "$old_path" "$new_path" "$relative_path"
	done < <(find "$src" -name '*.html' | LC_ALL=C sort)
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
