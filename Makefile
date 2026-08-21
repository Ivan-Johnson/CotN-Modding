SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

ACCEPT_REGEX_DEBUG := ^.*/docs/(index.html|modules/|modules/necro.client.ClientEvents/|components/|components/necro.game.data.component.character.AutoCastComponents/)$$
ACCEPT_REGEX_PRODUCTION := .*

BRANCH_DEBUG := debug
BRANCH_PRODUCTION := mainline

ifeq ($(BUILD_MODE),debug)
ACCEPT_REGEX := $(ACCEPT_REGEX_DEBUG)
BRANCH := $(BRANCH_DEBUG)
else ifeq ($(BUILD_MODE),production)
ACCEPT_REGEX := $(ACCEPT_REGEX_PRODUCTION)
BRANCH := $(BRANCH_PRODUCTION)
else ifeq ($(strip $(BUILD_MODE)),)
# Use debug by default
ACCEPT_REGEX := $(ACCEPT_REGEX_DEBUG)
BRANCH := $(BRANCH_DEBUG)
else
$(error Invalid BUILD_MODE='$(BUILD_MODE)' (use BUILD_MODE=debug or BUILD_MODE=production))
endif

all: output/3-html-to-markdown.tar.gz

.PHONY: all clean

clean:
	rm -f output/2-minimal-html.tar.gz output/3-html-to-markdown.tar.gz

# This takes about an hour to run
output/1-original-html.tar.gz:
	# Gotta make the directory first, otherwise the logs won't be saved
	mkdir -p output
	log="$@.log"

	exec > >(tee -a "$$log") 2>&1
	set -x
	tmp="$@.work"
	mkdir -p "$$tmp"
	echo "$$tmp"
	# TODO: Figure out what to do with `--wait`.
	wget --recursive --level=inf --wait=3 --continue "--directory-prefix=$$tmp" https://vortexbuffer.com/synchrony/docs/index.html "--accept-regex=$(ACCEPT_REGEX)"

	tar -zcf "$@.tmp" -C "$$tmp" .
	mv "$@.tmp" "$@"
	chmod -w "$@"
	rm -rf "$$tmp"

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

deploy: output/1-original-html.tar.gz
	tmp="$$(mktemp -d)"
	echo "$$tmp"

	# Do git stuff (and other metadata) before cd
	git rev-parse HEAD > "$$tmp/git_HEAD.txt"
	git diff HEAD > "$$tmp/git_diff.txt"
	git status > "$$tmp/git_status.txt"
	echo "$$(date)" > "$$tmp/timestamp.txt"

	# trap 'rm -rf "$$tmp"' EXIT
	tar -zxf "$<" -C "$$tmp"
	cd "$$tmp"
	git init
	git remote add origin git@github.com:Ivan-Johnson/CotN-docs.git
	git fetch origin "$(BRANCH)"
	git switch --create "$(BRANCH)"
	git reset --soft "origin/$(BRANCH)"

	git add .
	git commit -m "Update $$(cat timestamp.txt)"
	git push origin "$(BRANCH)"
