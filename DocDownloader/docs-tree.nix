{
        pkgs,
        conversionTools,
        official,
        gameData,
}:
let
        # The markdown and man page renderings of the raw docs, before they
        # are indexed. `html-to-docs.bash` lays them out as `markdown/`,
        # `minimal-html/` and `share/man/`; the docs tree re-homes them below.
        converted = pkgs.runCommand "cotn-docs-converted" { nativeBuildInputs = conversionTools; } ''
                export LC_ALL=C.UTF-8
                bash ${./html-to-docs.bash} ${official} "$out"
        '';
in
# The docs tree:
#
#   raw/        the raw docs, exactly as mirrored
#   official/   the official docs: minimal-html/, markdown/ and man/
#   authored/   the authored docs, empty until some exist
#   game-data/  the game data
#
# `man/` is indexed with `mandb`, whose index records each page's mtime. Nix
# normalizes mtimes only once a builder has exited, so indexing is its own
# stage that reads the pages back out of `converted`; that keeps the index
# reproducible. `man` and `man -k` search that index, and nothing can build one
# later, because by then the tree lives in the read only store.
pkgs.runCommand "cotn-docs-tree" { nativeBuildInputs = [ pkgs.man-db ]; } ''
        mkdir -p "$out/official" "$out/authored"
        cp -r ${official} "$out/raw"
        cp -r ${gameData} "$out/game-data"
        cp -a ${converted}/minimal-html "$out/official/minimal-html"
        cp -a ${converted}/markdown "$out/official/markdown"
        cp -a ${converted}/share/man "$out/official/man"
        chmod -R u+w "$out"

        # MANDB_MAP is what tells `mandb` where a manpath's index belongs;
        # without it there is nowhere to put one, and it quietly builds
        # nothing.
        echo "MANDATORY_MANPATH $out/official/man" >man.conf
        echo "MANDB_MAP $out/official/man $out/official/man" >>man.conf
        mandb --config-file man.conf --create

        # Keep the index, but not the empty directory `mandb` makes to cache
        # formatted pages in; the store has no use for it.
        rm -rf "$out/official/man/cat"*
''
