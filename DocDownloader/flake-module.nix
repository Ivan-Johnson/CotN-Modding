{ pkgs, official }:
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

        # The markdown and man page renderings of the raw docs, before they
        # are indexed. `html-to-docs.bash` lays them out as `markdown/`,
        # `minimal-html/` and `share/man/`.
        converted = pkgs.runCommand "cotn-docs-converted" { nativeBuildInputs = conversionTools; } ''
                export LC_ALL=C.UTF-8
                bash ${./html-to-docs.bash} ${official} "$out"
        '';
in
{
        # What the AuthoredDocs module builds the docs tree from; not merged
        # into the flake's outputs.
        inherit converted;

        checks = { inherit tests; };

        devShell = pkgs.mkShell { buildInputs = conversionTools; };
}
