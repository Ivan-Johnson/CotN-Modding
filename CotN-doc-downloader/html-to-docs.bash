#!/usr/bin/env bash
#
# Convert a tree of raw CotN documentation HTML into markdown and man pages.
#
# Writes DST_DIR/minimal-html/ (each page's <article>) and DST_DIR/markdown/,
# both mirroring SRC_DIR, plus the flat DST_DIR/share/man/manN/ that `man`
# expects.
#
# Usage:
#   ./html-to-docs.bash SRC_DIR DST_DIR

set -euo pipefail

# GFM preserves the pipe tables that the CommonMark writer flattens to
# `[TABLE]`.
readonly PANDOC_TO='gfm'

# The documented modules are a Lua API, so they belong in the "library calls"
# section.
readonly MAN_SECTION=3
readonly MAN_HEADER='Crypt of the NecroDancer Modding Documentation'

# Links are resolved lexically, against a root chosen not to collide with any
# real path.
readonly LINK_ROOT=/cotn-docs

# The current pass's pages, keyed by path relative to its source root. Rebuilt
# by `run_pass`; it is how a link to another page is told from any other link.
declare -A page_set

usage() {
	echo "Usage: ${BASH_SOURCE[0]} SRC_DIR DST_DIR" >&2
}

# The crawl root is nested in the mirror tree in production, but the tests use
# a small flat fixture. Either shape may serve as the nav source.
nav_source_path() {
	local src="$1"
	local candidate

	for candidate in \
		"$src/vortexbuffer.com/synchrony/docs/index.html" \
		"$src/index.html"; do
		if [[ -f "$candidate" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

# Extract the sidebar navigation from the source tree, stripped down to the
# page links and section labels that matter in the output.
nav_fragment() {
	local path="$1"

	htmlq 'nav.md-nav--primary' --ignore-whitespace --pretty \
		--remove-nodes 'input' \
		--remove-nodes 'span.md-nav__icon' \
		--remove-nodes 'a.md-nav__button' \
		--remove-nodes 'label.md-nav__title' \
		--filename "$path" \
	| sed -e 's|<span class="md-ellipsis">||g' \
		-e 's|</span>||g' \
		-e 's| class="[^"]*"||g'
}

# Wrap the harvested navigation in the article shell used by the output tree.
nav_page() {
	local src="$1"
	local dst="$2"
	local fragment
	local title='Synchrony API Documentation'

	fragment="$(mktemp)"
	if ! nav_fragment "$src" >"$fragment"; then
		rm -f "$fragment"
		return 1
	fi
	if [[ ! -s "$fragment" ]]; then
		rm -f "$fragment"
		return 1
	fi
	{
		printf '<article><h1>%s</h1>\n' "$title"
		cat "$fragment"
		printf '\n</article>\n'
	} >"$dst"
	rm -f "$fragment"
}

# Publish the generated nav landing page into the tree's HTML root.
nav_to_minimal_html() {
	local nav="$1"
	local dst="$2"
	local relative_path="$3"

	rewrite_links "$nav" "$dst/$relative_path" "$relative_path" minimal_html_path
}

# Publish the generated nav landing page into the tree's markdown root.
nav_to_markdown() {
	local nav="$1"
	local dst="$2"
	local relative_path="$3"

	rewrite_links "$nav" "$work_file" "$relative_path" markdown_path
	pandoc --from=html "--to=$PANDOC_TO" "$work_file" \
		--output "$dst/$(markdown_path "$relative_path")"
}

# Publish the generated nav landing page into the tree's man root.
nav_to_man() {
	local nav="$1"
	local dst="$2"
	local relative_path="$3"
	local name='cotn-docs'
	local summary='Synchrony API Documentation navigation'

	rewrite_links "$nav" "$work_file" "$relative_path" minimal_html_path
	pandoc --from=html --to=man --standalone \
		--metadata "title=$name" \
		--variable "section=$MAN_SECTION" \
		--variable "header=$MAN_HEADER" \
		--variable "header-includes=.SH NAME
$(quote_roff "$name") \\- $(quote_roff "$summary")" \
		"$work_file" --output "$dst/$name.$MAN_SECTION"
}

# Strip everything outside the page's <article>, and the chrome inside it.
to_minimal_html() {
	local old_path="$1" dst="$2" relative_path="$3"

	local new_path="$dst/$relative_path"
	mkdir -p "$(dirname "$new_path")"

	# a.headerlink is the ¶ permalink upstream hangs off every heading.
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

# The name a page is published under; `foo.html` and `foo/index.html` are both
# `foo`. Upstream names are fully qualified, so dropping directories keeps them
# unique.
page_name() {
	local relative_path="$1"

	local name="${relative_path%.html}"
	name="${name%/index}"
	echo "${name##*/}"
}

# The summary for the man page's NAME section, taken from the page's first
# heading. Without a NAME section `whatis` and `apropos` index nothing, so a
# page with no heading is refused rather than published unfindable.
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

	# `header-includes` lands directly after .TH, which is where NAME belongs.
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

# Escape a literal string for roff. A leading `.` or `'` would start a request.
quote_roff() {
	printf '%s' "$1" | sed -e 's|\\|\\e|g' -e "s|^[.']|\\\\\&&|"
}

# Where a page is published in each tree. The minimal-html tree mirrors the
# crawl, so that mapping is identity; it exists so both passes can be
# parameterized the same way.
minimal_html_path() {
	echo "$1"
}

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

# The page that `target` names, if any.
resolve_page() {
	local target="$1"

	if [[ -n "${page_set[$target]+set}" ]]; then
		echo "$target"
		return 0
	fi
	# Links written against the crawl still spell a deduped page `foo.html`.
	local deep="${target%.html}/index.html"
	if [[ "$target" == *.html && -n "${page_set[$deep]+set}" ]]; then
		echo "$deep"
		return 0
	fi
	return 1
}

# Copy `in_path` to `out_path`, respelling its links for the tree it is headed
# into.
#
# Conversion moves pages relative to the links pointing at them: `published_path`
# renames them, and `foo/index.html` climbs a level when it collapses to
# `foo.md`. So each link is resolved back to the page it means, then written
# out afresh from where this page has landed.
rewrite_links() {
	local in_path="$1" out_path="$2" relative_path="$3" published_path="$4"

	local hrefs
	hrefs="$(htmlq --attribute href a --filename "$in_path" | LC_ALL=C sort -u)"

	local from_dir
	from_dir="$(dirname "$("$published_path" "$relative_path")")"

	local -a edits=()
	local href path target page new
	while IFS= read -r href; do
		# Anything that already names where it wants to go.
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
# The crawler spells each copy's links relative to that copy's own directory: a
# sibling `bar` is `bar` from `foo.html` but `../bar` from `foo/index.html`, and
# a child is `foo/baz` then `baz`. Dropping every leading `../` and `foo/` from
# quoted attributes therefore spells both copies alike.
normalize_link_depth() {
	local path="$1" name
	name="$(quote_bre "$2")"

	sed -e "s|\([\"']\)\.\./|\1|g" -e "s|\([\"']\)$name/|\1|g" "$path"
}

# The two copies of a page are never byte-identical, since their links are
# written from different directories, but they must agree once that is
# normalized away.
assert_same_page() {
	local shallow="$1" deep="$2" name="$3"

	if ! cmp --silent \
		<(normalize_link_depth "$shallow" "$name") \
		<(normalize_link_depth "$deep" "$name"); then
		echo "'$shallow' and '$deep' should be two copies of the page '$name', but they differ by more than the depth of their relative links" >&2
		return 1
	fi
}

# The *.html files in `src` that are distinct pages, in a stable order. The
# crawl mirrors a page reachable at `foo` as both `foo.html` and
# `foo/index.html`; only the latter is kept.
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

# Run `convert OLD DST REL` over every page in `src`. The converter picks OLD's
# destination within DST and creates whatever subdirectories it needs.
run_pass() {
	local src="$1" dst="$2" convert="$3"

	mkdir -p "$dst"

	# Collected up front so that a failed assertion in `list_pages` aborts the
	# run: `set -e` does not fire inside the subshell of a command
	# substitution, so the failure is propagated by hand.
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

# Scratch space for the converters, which each pass a page through it.
work_file="$(mktemp)"
readonly work_file
nav_file="$(mktemp)"
readonly nav_file
trap 'rm -f "$work_file" "$nav_file"' EXIT

run_pass "$src_dir" "$dst_dir/minimal-html" to_minimal_html
run_pass "$dst_dir/minimal-html" "$dst_dir/markdown" to_markdown
run_pass "$dst_dir/minimal-html" "$dst_dir/share/man/man$MAN_SECTION" to_man

if nav_source="$(nav_source_path "$src_dir")"; then
	nav_relative_path="${nav_source#"$src_dir"/}"
	if nav_page "$nav_source" "$nav_file"; then
		nav_to_minimal_html "$nav_file" "$dst_dir/minimal-html" "$nav_relative_path"
		nav_to_markdown "$nav_file" "$dst_dir/markdown" "$nav_relative_path"
		rm -f "$dst_dir/share/man/man$MAN_SECTION/$(page_name "$nav_relative_path").$MAN_SECTION"
		nav_to_man "$nav_file" "$dst_dir/share/man/man$MAN_SECTION" "$nav_relative_path"
	fi
fi
