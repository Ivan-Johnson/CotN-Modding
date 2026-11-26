# The AuthoredDocs context's flake outputs: the docs tree (`docs-tree.nix`) as
# the `docs` package, `check-docs.bash` over it as the `corpus` check, and the
# dev shell's `man-crypt`.
{
        pkgs,
        official,
        gameData,
        converted,
}:
let
        docs = import ./docs-tree.nix {
                inherit
                        pkgs
                        official
                        gameData
                        converted
                        ;
        };

        # What `check-docs.bash` needs beyond the standard environment.
        checkTools = [
                pkgs.htmlq
                pkgs.man-db
        ];

        # The conversion, checked over a whole build rather than a handwritten
        # crawl of two or three pages.
        corpus = pkgs.runCommand "cotn-docs-corpus" { nativeBuildInputs = checkTools; } ''
                export LC_ALL=C.UTF-8
                export MANPATH=${docs}/official/man
                bash ${./check-docs.bash} ${docs}
                touch "$out"
        '';
in
{
        packages = { inherit docs; };

        checks = { inherit corpus; };

        # `docs` is deliberately not an input of this shell. Depending on
        # it would mean the shell could not be entered whenever the
        # conversion is broken, which is exactly when it is needed. It is
        # built on demand instead.
        devShell = pkgs.mkShell {
                buildInputs = checkTools;
                shellHook = ''
                        # Rebuild the documentation, then read a page from it.
                        man-crypt() {
                                local out="$(nix build --no-link --print-out-paths "$(git rev-parse --show-toplevel)#docs")" || return
                                MANPATH="$out/official/man" man "$@"
                        }
                        export -f man-crypt
                '';
        };
}
