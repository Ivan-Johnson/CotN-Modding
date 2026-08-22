#!/usr/bin/env bash
#
# Convert the raw HTML produced by ./crawl-and-push.sh into markdown.
#
# Reads:  output/1-original-html.tar.gz
# Writes: output/2-minimal-html.tar.gz  (just the <article> of each page)
#         output/3-html-to-markdown.tar.gz
#
# Usage:
#   ./html-to-markdown.sh

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT
readonly OUTPUT_DIR="$REPO_ROOT/output"
readonly HTML_TARBALL="$OUTPUT_DIR/1-original-html.tar.gz"
readonly MINIMAL_TARBALL="$OUTPUT_DIR/2-minimal-html.tar.gz"
readonly MARKDOWN_TARBALL="$OUTPUT_DIR/3-html-to-markdown.tar.gz"

readonly PANDOC_TO='commonmark-alerts-ascii_identifiers-attributes-autolink_bare_uris-bracketed_spans-definition_lists-east_asian_line_breaks-emoji-fancy_lists-fenced_divs-footnotes-gfm_auto_identifiers-hard_line_breaks-implicit_figures-implicit_header_references-pipe_tables-raw_attribute-raw_html-rebase_relative_paths-smart-sourcepos-strikeout-subscript-superscript-task_lists-tex_math_dollars-tex_math_gfm-wikilinks_title_after_pipe-wikilinks_title_before_pipe-yaml_metadata_block'

declare -a TMP_DIRS=()
cleanup() {
	local dir
	for dir in ${TMP_DIRS[@]+"${TMP_DIRS[@]}"}; do
		rm -rf "$dir"
	done
}
trap cleanup EXIT

# Strip everything outside of the page's <article> element.
to_minimal_html() {
	local old_path="$1" new_path="$2"
	htmlq article --ignore-whitespace --pretty --filename "$old_path" --output "$new_path"
}

to_markdown() {
	local old_path="$1" new_path="$2"

	new_path="${new_path%.html}.md"
	if [[ "$(basename "$new_path")" == 'index.md' ]]; then
		new_path="${new_path%/index.md}.md"
	fi

	pandoc --from=html "--to=$PANDOC_TO" "$old_path" --output "$new_path"
}

# Extract `in_tarball`, run `convert` over every *.html file in it, and pack the
# results up into `out_tarball`. `convert` is called as `convert OLD NEW`, where
# NEW is OLD's path relative to the output tree; the converter is free to change
# NEW's extension.
run_pass() {
	local in_tarball="$1" out_tarball="$2" convert="$3"

	local tmp
	tmp="$(mktemp -d)"
	TMP_DIRS+=("$tmp")

	local src="$tmp/src" dst="$tmp/dst"
	mkdir -p "$src" "$dst"

	tar -zxf "$in_tarball" -C "$src"

	local old_path relative_path new_path
	while IFS= read -r old_path; do
		relative_path="${old_path#"$src"/}"
		new_path="$dst/$relative_path"
		mkdir -p "$(dirname "$new_path")"
		"$convert" "$old_path" "$new_path"
	done < <(find "$src" -name '*.html')

	tar -zcf "$out_tarball.tmp" -C "$dst" .
	mv "$out_tarball.tmp" "$out_tarball"

	rm -rf "$tmp"
}

if [[ ! -f "$HTML_TARBALL" ]]; then
	echo "$HTML_TARBALL does not exist; run ./crawl-and-push.sh first" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR"
run_pass "$HTML_TARBALL" "$MINIMAL_TARBALL" to_minimal_html
run_pass "$MINIMAL_TARBALL" "$MARKDOWN_TARBALL" to_markdown
