{
        pkgs,
        official,
        gameData,
}:
let
        # Everything `html-to-docs.bash` needs to run.
        conversionTools = [
                pkgs.bash
                pkgs.coreutils
                pkgs.findutils
                pkgs.htmlq
                pkgs.jq
                pkgs.pandoc
                pkgs.man-db
        ];

        # The scripts, isolated from the generated state around them so that
        # a rebuilt `result` or a fresh crawl does not invalidate the tests.
        scripts = pkgs.lib.fileset.toSource {
                root = ./.;
                fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "bash") ./.;
        };

        # The conversion's own tests, which build throwaway crawls of their
        # own and so need nothing from the network or the mirror.
        tests =
                pkgs.runCommand "cotn-docs-tests" { nativeBuildInputs = conversionTools ++ [ pkgs.git ]; }
                        ''
                                export LC_ALL=C.UTF-8
                                cd ${scripts}
                                bash -n *.bash
                                bash ./test-html-to-docs.bash
                                touch "$out"
                        '';

        docs = import ./docs-tree.nix {
                inherit
                        pkgs
                        conversionTools
                        official
                        gameData
                        ;
        };

        # The same conversion, checked over a whole build rather than a
        # handwritten crawl of two or three pages.
        corpus = pkgs.runCommand "cotn-docs-corpus" { nativeBuildInputs = conversionTools; } ''
                export LC_ALL=C.UTF-8
                export MANPATH=${docs}/official/man
                bash ${./check-docs.bash} ${docs}
                touch "$out"
        '';
in
{
        packages = { inherit docs; };

        checks = { inherit tests corpus; };

        # `docs` is deliberately not an input of this shell. Depending on
        # it would mean the shell could not be entered whenever the
        # conversion is broken, which is exactly when it is needed. It is
        # built on demand instead.
        devShell = pkgs.mkShell {
                buildInputs = conversionTools;
                shellHook = ''
                        # Rebuild the documentation, then read a page from it.
                        man-crypt() {
                                local out="$(nix build --no-link --print-out-paths "$ITJ_FLAKE_ROOT#docs")" || return
                                MANPATH="$out/official/man" man "$@"
                        }
                        export -f man-crypt
                '';
        };
}
