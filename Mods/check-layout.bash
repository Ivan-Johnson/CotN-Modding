#!/usr/bin/env bash
# Checks the conventions install-mods relies on, for every mod under a Mods/
# directory:
#   * the directory name equals mod.json's "namespace" and "name"
#   * a Lua string that starts with a mod's name, like "HelloWorldTests.api",
#     appears only as the argument of a require, which install-mods can rewrite
#
# Usage: check-layout.bash MODS_DIR
set -euo pipefail

modsDir="$1"
status=0

mods=()
for manifest in "$modsDir"/*/mod.json; do
	mods+=("$(basename "$(dirname "$manifest")")")
done

for mod in "${mods[@]}"; do
	for field in namespace name; do
		value="$(jq -r ".$field" "$modsDir/$mod/mod.json")"
		if [[ $value != "$mod" ]]; then
			echo "$mod/mod.json: \"$field\" is \"$value\", expected \"$mod\" to match its directory" >&2
			status=1
		fi
	done
done

alternatives="$(IFS='|'; echo "${mods[*]}")"
for mod in "${mods[@]}"; do
	# -v requires lines to lack the rewritable form; both greps are per line.
	stray="$(
		grep -rnE --include='*.lua' "\"($alternatives)\\." "$modsDir/$mod" |
			grep -vE "require[ (,]+\"($alternatives)\\." || true
	)"
	if [[ -n $stray ]]; then
		echo "$stray" >&2
		echo "$mod: the strings above name a mod's modules outside a require, so install-mods would not rewrite them" >&2
		status=1
	fi
done

exit "$status"
