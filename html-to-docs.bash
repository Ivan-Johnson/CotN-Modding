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

# An imaginary root to resolve relative links against. Links are rewritten
# purely lexically, so this only has to be somewhere the real paths are not.
readonly LINK_ROOT=/cotn-docs

# The pages of the pass currently running, as a set of paths relative to that
# pass's source root. Rebuilt by `run_pass`, and read by the converters to tell
# a link that points at another page from one that points anywhere else.
declare -A page_set

usage() {
	echo "Usage: ${BASH_SOURCE[0]} SRC_DIR DST_DIR" >&2
}

# Strip everything outside of the page's <article> element, along with the
# chrome inside it.
to_minimal_html() {
	local old_path="$1" dst="$2" relative_path="$3"

	local new_path="$dst/$relative_path"
	mkdir -p "$(dirname "$new_path")"

	# a.headerlink deletes the ¶s that are created on every header
	htmlq article --ignore-whitespace --pretty \
		--remove-nodes "a.headerlink" \
		--filename "$old_path" --output "$work_file"
	rewrite_links "$work_file" "$new_path" "$relative_path" minimal_html_path
}

to_markdown() {
	local old_path="$1" dst="$2" relative_path="$3"

	local new_path
	new_path="$dst/$(markdown_path "$relative_path")"

	mkdir -p "$(dirname "$new_path")"
	rewrite_links "$old_path" "$work_file" "$relative_path" markdown_path
	pandoc --from=html "--to=$PANDOC_TO" "$work_file" --output "$new_path"
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

# The one line summary that a man page is listed under, taken from the page's
# own heading. A page whose first heading is missing or empty has nothing to be
# summarized by, and would be published as an unfindable man page.
page_summary() {
	local path="$1" summary

	summary="$(htmlq 'h1:first-of-type' --text --ignore-whitespace \
		--filename "$path" | tr '\n' ' ' | sed -e 's|  *| |g' -e 's|^ ||' -e 's| $||')"
	if [[ -z "$summary" ]]; then
		echo "'$path' has no heading to summarize it in its man page's NAME section" >&2
		return 1
	fi
	echo "$summary"
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

	local summary
	summary="$(page_summary "$old_path")" || exit 1

	# `man` itself does not need a NAME section, but `whatis` and `apropos`
	# index nothing without one. The template puts header-includes directly
	# after the .TH line, which is where NAME belongs.
	pandoc --from=html --to=man --standalone \
		--metadata "title=$name" \
		--variable "section=$MAN_SECTION" \
		--variable "header=$MAN_HEADER" \
		--variable "header-includes=.SH NAME
$(quote_roff "$name") \\- $(quote_roff "$summary")" \
		"$old_path" --output "$new_path"
}

# Escape a literal string so that it can be used in a sed basic regex.
quote_bre() {
	printf '%s' "$1" | sed 's|[][\\.*^$]|\\&|g'
}

# Escape a literal string so that it can be used as a sed replacement.
quote_replacement() {
	printf '%s' "$1" | sed 's|[\\&]|\\&|g'
}

# Escape a literal string so that it can be used in roff source. A leading `.`
# or `'` would start a request rather than a line of text.
quote_roff() {
	printf '%s' "$1" | sed -e 's|\\|\\e|g' -e "s|^[.']|\\\\\&&|"
}

# The path, relative to the minimal-html tree's root, of the page crawled to
# `relative_path`. That tree mirrors the crawl, so this is a no-op; it exists so
# that every pass names its output the same way.
minimal_html_path() {
	echo "$1"
}

# The path, relative to the markdown tree's root, of the page at
# `relative_path`.
markdown_path() {
	local relative_path="$1"

	local path="${relative_path%.html}.md"
	# Collapse `foo/index.html` into `foo.md`, but leave a top level
	# `index.html` alone; collapsing it would clobber the output root.
	if [[ "$relative_path" == */index.html ]]; then
		path="${path%/index.md}.md"
	fi
	echo "$path"
}

# The page in the current pass's source tree that `target` names, if any.
resolve_page() {
	local target="$1"

	if [[ -n "${page_set[$target]+set}" ]]; then
		echo "$target"
		return 0
	fi
	# `foo.html` and `foo/index.html` are the same page, and only the latter
	# survives `list_pages` when the crawl caught both. Links written against
	# the crawl still spell it the first way.
	local deep="${target%.html}/index.html"
	if [[ "$target" == *.html && -n "${page_set[$deep]+set}" ]]; then
		echo "$deep"
		return 0
	fi
	return 1
}

# Rewrite the relative links of the page at `in_path` for the tree it is being
# converted into, writing the result to `out_path`.
#
# The crawl's links point at `.html` files, spelled relative to the directory of
# the copy they were written in. Both of those change during conversion: pages
# are renamed by `published_path`, and `foo/index.html` moves up a level when it
# collapses to `foo.md`. So each link is resolved back to the page it means, and
# then respelled from wherever this page has landed.
#
# `relative_path` is the page being converted, relative to the pass's source
# root, and `published_path` names the function that maps a page to its path in
# the output tree.
rewrite_links() {
	local in_path="$1" out_path="$2" relative_path="$3" published_path="$4"

	local hrefs
	hrefs="$(htmlq --attribute href a --filename "$in_path" | LC_ALL=C sort -u)"

	local from_dir
	from_dir="$(dirname "$("$published_path" "$relative_path")")"

	local -a edits=()
	local href path target page new
	while IFS= read -r href; do
		# Anything that already names where it wants to go: absolute and
		# protocol relative URLs, and links into the page itself.
		[[ "$href" != *:* && "$href" != //* && "$href" != '#'* ]] || continue

		path="${href%%[#?]*}"
		[[ -n "$path" ]] || continue

		target="$(realpath -m --relative-to="$LINK_ROOT" \
			"$LINK_ROOT/$(dirname "$relative_path")/$path")"
		# A link out of the crawl has nothing to be pointed at instead.
		page="$(resolve_page "$target")" || continue

		new="$(realpath -m --relative-to="$LINK_ROOT/$from_dir" \
			"$LINK_ROOT/$("$published_path" "$page")")${href#"$path"}"
		edits+=(-e "s|href=\"$(quote_bre "$href")\"|href=\"$(quote_replacement "$new")\"|g")
	done <<< "$hrefs"

	if [[ "${#edits[@]}" -eq 0 ]]; then
		cp "$in_path" "$out_path"
		return
	fi
	sed "${edits[@]}" "$in_path" >"$out_path"
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
# path within DST and creates whatever subdirectories it needs. `page_set` holds
# the pass's pages while it runs, so that `convert` can resolve links into them.
run_pass() {
	local src="$1" dst="$2" convert="$3"

	mkdir -p "$dst"

	# Collected up front rather than streamed in, so that a failed assertion in
	# `list_pages` aborts the run. `set -e` does not fire inside the subshell
	# of a command substitution, so the failure is propagated by hand.
	local pages
	pages="$(list_pages "$src")" || return 1

	local old_path relative_path
	page_set=()
	while IFS= read -r old_path; do
		[[ -n "$old_path" ]] || continue
		page_set["${old_path#"$src"/}"]=1
	done <<< "$pages"

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

# Scratch space for the converters, which each rewrite a page's links into it
# on the way past.
work_file="$(mktemp)"
readonly work_file
trap 'rm -f "$work_file"' EXIT

run_pass "$src_dir" "$dst_dir/minimal-html" to_minimal_html
run_pass "$dst_dir/minimal-html" "$dst_dir/markdown" to_markdown
run_pass "$dst_dir/minimal-html" "$dst_dir/share/man/man$MAN_SECTION" to_man
