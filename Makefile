SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

all: output/3-html-to-markdown.tar.gz

.PHONY: all clean

# We intentionally do not define a `clean` target. Downloading the HTML files is 
# time-consuming, so we want to avoid accidentally deleting them.
#
# clean:
#	rm -rf output/

output/1-original-html.tar.gz:
	set -x
	tmp="$$(mktemp -d)"
	trap 'rm -rf "$$tmp"' EXIT
	echo "$$tmp"

	# Production:
	wget --mirror --convert-links --adjust-extension --page-requisites -P "$$tmp" https://vortexbuffer.com/synchrony/docs/ --wait=3

	# Development:
	# wget -P "$$tmp" --wait=3 https://vortexbuffer.com/synchrony/docs/

	tar -zcf "$@.tmp" -C "$$tmp" .
	mv "$@.tmp" "$@"

output/2-minimal-html.tar.gz: output/1-original-html.tar.gz
	tmp="$$(mktemp -d)"
	trap 'rm -rf "$$tmp"' EXIT
	src="$$tmp/src"
	dst="$$tmp/dst"
	mkdir -p "$$src" "$$dst"

	tar -zxf "$<" -C "$$src"

	find "$$src" -name '*.html' | while read -r old_path; do
		relative_path="$${old_path#$$src/}"
		new_path="$$dst/$$relative_path"
		mkdir -p "$$(dirname "$$new_path")"
		htmlq article --ignore-whitespace --pretty --filename "$$old_path" --output "$$new_path"
	done

	tar -zcf "$@.tmp" -C "$$dst" .
	mv "$@.tmp" "$@"

output/3-html-to-markdown.tar.gz: output/2-minimal-html.tar.gz
	tmp="$$(mktemp -d)"
	trap 'rm -rf "$$tmp"' EXIT
	src="$$tmp/src"
	dst="$$tmp/dst"
	mkdir -p "$$src" "$$dst"

	tar -zxf "$<" -C "$$src"

	find "$$src" -name '*.html' | while read -r old_path; do
		relative_path="$${old_path#$$src/}"
		new_path="$$dst/$$relative_path"
		mkdir -p "$$(dirname "$$new_path")"
		new_path="$${new_path/.html}.md"
		if [ "$$(basename "$$new_path")" = "index.md" ]; then
			new_path="$${new_path/\/index.md}.md"
		fi
		pandoc --from=html --to=commonmark-alerts-ascii_identifiers-attributes-autolink_bare_uris-bracketed_spans-definition_lists-east_asian_line_breaks-emoji-fancy_lists-fenced_divs-footnotes-gfm_auto_identifiers-hard_line_breaks-implicit_figures-implicit_header_references-pipe_tables-raw_attribute-raw_html-rebase_relative_paths-smart-sourcepos-strikeout-subscript-superscript-task_lists-tex_math_dollars-tex_math_gfm-wikilinks_title_after_pipe-wikilinks_title_before_pipe-yaml_metadata_block "$$old_path" --output "$$new_path"
	done

	tar -zcf "$@.tmp" -C "$$dst" .
	mv "$@.tmp" "$@"
