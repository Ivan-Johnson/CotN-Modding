{ pkgs, liveGame }:
let
        # The scripts, plus the mirror push they share with DocDownloader,
        # isolated from the generated state around them.
        scripts = pkgs.lib.fileset.toSource {
                root = ./..;
                fileset = pkgs.lib.fileset.unions [
                        (pkgs.lib.fileset.fileFilter (file: file.hasExt "bash") ./.)
                        ./game-data-README.md
                        ../DocDownloader/push-to-mirror.bash
                ];
        };

        pipelineTools = [
                pkgs.coreutils
                pkgs.findutils
                pkgs.gawk
                pkgs.git
                pkgs.gnugrep
                pkgs.jq
        ];

        tests = pkgs.runCommand "cotn-game-data-tests" { nativeBuildInputs = pipelineTools; } ''
                export LC_ALL=C.UTF-8
                cd ${scripts}/GameData
                bash -n *.bash
                bash ./test-reassemble.bash
                bash ./test-push.bash
                touch "$out"
        '';

        # Installs ScrapeGameData, waits for its "end" sentinel, saves the new
        # log lines into a fresh per-run directory and reassembles the
        # datasets there. Impure, like `itj-impure-tests`.
        scrapeGameData = pkgs.writeShellApplication {
                name = "scrape-game-data";
                runtimeInputs = pipelineTools;
                text = ''
                        ${liveGame.waitForLog}

                        outDir="$(git rev-parse --show-toplevel)/Tmp/scrape-game-data/$(date +%Y-%m-%d_%H-%M-%S)"
                        mkdir -p "$outDir"

                        baseline=$(wc -l <"$COTN_LOG")

                        ITJ_BUNDLE_RELOAD_TRIGGER="ScrapeGameData/ScrapeGameData.lua" ${liveGame.installMods}/bin/install-mods ScrapeGameData

                        if ! wait_for_log "$baseline" "[ScrapeGameData] end"; then
                                echo "scrape-game-data: timed out waiting for the end sentinel" >&2
                                exit 1
                        fi

                        tail -n "+$((baseline + 1))" "$COTN_LOG" >"$outDir/NecroDancer.log"

                        status=0
                        bash ${scripts}/GameData/reassemble-scrape.bash "$outDir" || status=$?

                        echo "$outDir"
                        exit "$status"
                '';
        };

        # A real Git push to the mirror's `game-data` branch.
        pushGameData = pkgs.writeShellApplication {
                name = "push-game-data";
                runtimeInputs = pipelineTools;
                text = ''
                        REPO_ROOT="$(git rev-parse --show-toplevel)" exec bash ${scripts}/GameData/push-game-data.bash "$@"
                '';
        };
in
{
        checks = {
                game-data-tests = tests;
        };

        apps = {
                scrape-game-data = {
                        type = "app";
                        program = "${scrapeGameData}/bin/scrape-game-data";
                        meta.description = "Run the ScrapeGameData mod in the live game and save its datasets to Tmp/scrape-game-data/<date-slug>/";
                };

                push-game-data = {
                        type = "app";
                        program = "${pushGameData}/bin/push-game-data";
                        meta.description = "Push a scrape (the newest by default) to the mirror's game-data branch: nix run .#push-game-data -- [SCRAPE_DIR]";
                };
        };

        devShell = pkgs.mkShell { buildInputs = pipelineTools; };
}
