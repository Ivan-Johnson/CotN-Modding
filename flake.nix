{
        description = "Crypt of the NecroDancer Synchrony modding: API docs and mods";

        inputs = {
                nixpkgs.url = "nixpkgs/nixos-26.05";

                dev-tools = {
                        url = "git+https://github.com/Ivan-Johnson/DevTools.git?ref=refs/heads/mainline";
                        inputs.nixpkgs.follows = "nixpkgs";
                };

                cotn-docs-official = {
                        url = "git+ssh://git@github.com/Ivan-Johnson/CotN-docs.git?ref=mainline";
                        flake = false;
                };

                cotn-docs-game-data = {
                        url = "git+ssh://git@github.com/Ivan-Johnson/CotN-docs.git?ref=game-data";
                        flake = false;
                };
        };

        outputs =
                {
                        self,
                        nixpkgs,
                        dev-tools,
                        cotn-docs-official,
                        cotn-docs-game-data,
                }:
                let
                        pkgs = import nixpkgs { system = "x86_64-linux"; };

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
                                root = ./DocDownloader;
                                fileset = pkgs.lib.fileset.unions [
                                        (pkgs.lib.fileset.fileFilter (file: file.hasExt "bash") ./DocDownloader)
                                        ./DocDownloader/game-data-README.md
                                ];
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
                                                bash ./test-push.bash
                                                touch "$out"
                                        '';

                        docs = import ./DocDownloader/docs-tree.nix {
                                inherit pkgs conversionTools;
                                official = cotn-docs-official;
                                gameData = cotn-docs-game-data;
                        };

                        # The same conversion, checked over a whole build rather than a
                        # handwritten crawl of two or three pages.
                        corpus = pkgs.runCommand "cotn-docs-corpus" { nativeBuildInputs = conversionTools; } ''
                                export LC_ALL=C.UTF-8
                                export MANPATH=${docs}/official/man
                                bash ${./DocDownloader/check-docs.bash} ${docs}
                                touch "$out"
                        '';

                        helloWorldModZip = pkgs.runCommand "hello-world-mod-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
                                mkdir -p "$out"
                                cd ${./Mods/HelloWorld}
                                zip -qr "$out/HelloWorld.zip" .
                        '';

                        # Not shipped to players; a generic test-running framework that
                        # HelloWorld (and any other mod under test) optionally requires at
                        # load-time to register and run its behavioral tests. See
                        # `Mods/HelloWorldTests`.
                        helloWorldModTestsZip =
                                pkgs.runCommand "hello-world-mod-tests-zip" { nativeBuildInputs = [ pkgs.zip ]; }
                                        ''
                                                mkdir -p "$out"
                                                cd ${./Mods/HelloWorldTests}
                                                zip -qr "$out/HelloWorldTests.zip" .
                                        '';

                        # Static analysis of every mod's Lua, catching syntax errors and
                        # undefined globals (e.g. a typo'd event name) without needing the
                        # game itself. `Mods/.luacheckrc` declares the globals Synchrony
                        # injects into mods, such as `event`.
                        modsLuaLint =
                                pkgs.runCommand "cotn-mods-luacheck" { nativeBuildInputs = [ pkgs.luaPackages.luacheck ]; }
                                        ''
                                                luacheck --config ${./Mods/.luacheckrc} ${./Mods}
                                                touch "$out"
                                        '';

                        # The conventions `install-mods` relies on, e.g. that each mod's
                        # directory is named after its namespace.
                        modsLayout =
                                pkgs.runCommand "cotn-mods-layout"
                                        {
                                                nativeBuildInputs = [
                                                        pkgs.jq
                                                        pkgs.gnugrep
                                                ];
                                        }
                                        ''
                                                bash ${./Mods/check-layout.bash} ${./Mods}
                                                touch "$out"
                                        '';

                        # Installs mods from the source tree (not the store, which only
                        # sees git-tracked files) into the game as one bundle mod. See
                        # `Mods/install-mods.bash`.
                        installMods = pkgs.writeShellApplication {
                                name = "install-mods";
                                runtimeInputs = [
                                        pkgs.coreutils
                                        pkgs.findutils
                                        pkgs.gnused
                                        pkgs.jq
                                        pkgs.rsync
                                ];
                                text = builtins.readFile ./Mods/install-mods.bash;
                        };

                        # Only correct while CotN runs natively on this machine, under this
                        # user, via this specific Proton prefix (id 247080).
                        cotnLogPath = "/home/i/.local/share/Steam/steamapps/common/Crypt of the NecroDancer/NecroDancer64/NecroDancer.log";

                        # Drives the game's live-reload and asserts on the resulting log
                        # output. Impure (needs a running, native Steam/Proton CotN
                        # instance and a live mods directory), so it lives in `apps`
                        # rather than `checks`: exposed as `nix run .#itj-impure-tests`.
                        impureTests = pkgs.writeShellApplication {
                                name = "run-tests";
                                runtimeInputs = [ pkgs.coreutils ];
                                text = ''
                                        baseline=$(wc -l <"$COTN_LOG")

                                        # Installing appends a timestamp comment to api.lua, rather than
                                        # to the entry script. api.lua is the module every mod under test
                                        # requires at load-time to register its tests, so changing it
                                        # (forcing a reload) cascades a reload of every mod that
                                        # successfully required it - including HelloWorld - re-running
                                        # their registerTest() calls. This also ensures the suite always
                                        # reruns even if there are no new changes.
                                        ITJ_BUNDLE_RELOAD_TRIGGER="HelloWorldTests/api.lua" ${installMods}/bin/install-mods HelloWorld HelloWorldTests

                                        # Wait for the tests mod's completion sentinel, rather than a
                                        # hardcoded sleep or a quiet-period guess.
                                        timeoutSeconds=60
                                        start=$(date +%s)
                                        timedOut=0
                                        while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -qF "[HelloWorldTests] Test suite completed"; do
                                                sleep 0.1
                                                if ((($(date +%s) - start) >= timeoutSeconds)); then
                                                        echo "itj-impure-tests: timed out waiting for test suite completion" >&2
                                                        timedOut=1
                                                        break
                                                fi
                                        done

                                        newOutput="$(tail -n "+$((baseline + 1))" "$COTN_LOG")"
                                        echo "$newOutput"

                                        if ((timedOut)); then
                                        	echo "Test suite timed out"
                                                exit 1
                                        fi

                                        if grep -qE '\[HelloWorldTests\] Test suite completed: 0 failure\(s\)' <<<"$newOutput"; then
                                                echo All tests pass
                                        else
                                                echo "itj-impure-tests: test suite reported failures" >&2
                                                exit 1
                                        fi
                                '';
                        };

                        # Installs ScrapeGameData, waits for its "end" sentinel, and saves
                        # the new log lines into a fresh per-run directory. Impure, like
                        # `impureTests`.
                        scrapeGameData = pkgs.writeShellApplication {
                                name = "scrape-game-data";
                                runtimeInputs = [
                                        pkgs.coreutils
                                        pkgs.gawk
                                        pkgs.gnugrep
                                        pkgs.yq-go
                                ];
                                text = ''
                                        outDir="$ITJ_FLAKE_ROOT/Tmp/scrape-game-data/$(date +%Y-%m-%d_%H-%M-%S)"
                                        mkdir -p "$outDir"

                                        baseline=$(wc -l <"$COTN_LOG")

                                        ITJ_BUNDLE_RELOAD_TRIGGER="ScrapeGameData/ScrapeGameData.lua" ${installMods}/bin/install-mods ScrapeGameData

                                        timeoutSeconds=60
                                        start=$(date +%s)
                                        while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -qF "[ScrapeGameData] end"; do
                                                sleep 0.1
                                                if ((($(date +%s) - start) >= timeoutSeconds)); then
                                                        echo "scrape-game-data: timed out waiting for the end sentinel" >&2
                                                        exit 1
                                                fi
                                        done

                                        tail -n "+$((baseline + 1))" "$COTN_LOG" >"$outDir/NecroDancer.log"

                                        # Reassemble each dataset from its DATA chunk lines.
                                        grep -oE '\[ScrapeGameData\] DATA [^ ]+ [0-9]+/[0-9]+ [A-Za-z0-9+/=]*' "$outDir/NecroDancer.log" >"$outDir/chunks.txt" || true
                                        status=0
                                        while read -r name; do
                                                total=$(awk -v n="$name" '$3 == n {split($4, p, "/"); print p[2]; exit}' "$outDir/chunks.txt")
                                                count=$(awk -v n="$name" '$3 == n' "$outDir/chunks.txt" | wc -l)
                                                if ((count != total)); then
                                                        echo "scrape-game-data: $name has $count of $total chunks" >&2
                                                        status=1
                                                        continue
                                                fi
                                                awk -v n="$name" '$3 == n {split($4, p, "/"); print p[1], $5}' "$outDir/chunks.txt" | sort -n | cut -d' ' -f2 | tr -d '\n' | base64 -d >"$outDir/$name"
                                        done < <(awk '{print $3}' "$outDir/chunks.txt" | sort -u)
                                        rm "$outDir/chunks.txt"

                                        if grep -F "[ScrapeGameData] ERROR" "$outDir/NecroDancer.log"; then
                                                status=1
                                        fi

                                        # The game's XML, in a queryable form.
                                        yq -p xml -o json "$outDir/necrodancer.xml" >"$outDir/necrodancer-xml.json"

                                        echo "$outDir"
                                        exit "$status"
                                '';
                        };
                in
                {
                        devShells.x86_64-linux.default = pkgs.mkShell {
                                inputsFrom = [
                                        dev-tools.devShells.x86_64-linux.default
                                        dev-tools.devShells.x86_64-linux.github-cli
                                ];
                                buildInputs = conversionTools ++ [
                                        impureTests
                                        installMods

                                        # For packaging mods
                                        pkgs.zip
                                        pkgs.unzip
                                ];
                                # `docs` is deliberately not an input of this shell. Depending on
                                # it would mean the shell could not be entered whenever the
                                # conversion is broken, which is exactly when it is needed. It is
                                # built on demand instead.
                                shellHook = ''
                                        # This path is platform specific. e.g. if you're running the native steam runtime vs proton
                                        # todo: commonize?
                                        export COTN_LOCAL_MODS_DIR="$HOME/.local/share/Steam/steamapps/compatdata/247080/pfx/drive_c/users/steamuser/AppData/Local/NecroDancer/mods/"

                                        export ITJ_GIT_PREPUSH_ENABLE_NIX_CHECKS=
                                        export COTN_LOG="${cotnLogPath}"
                                        export EXTRA_RO_BINDS="''${EXTRA_RO_BINDS:+''$EXTRA_RO_BINDS:}$COTN_LOG"
                                        export EXTRA_RW_BINDS="''${EXTRA_RW_BINDS:+''$EXTRA_RW_BINDS:}$COTN_LOCAL_MODS_DIR"

                                        # Rebuild the documentation, then read a page from it.
                                        man-crypt() {
                                                local out="$(nix build --no-link --print-out-paths "$ITJ_FLAKE_ROOT#docs")" || return
                                                MANPATH="$out/official/man" man "$@"
                                        }
                                        export -f man-crypt
                                '';
                        };

                        packages.x86_64-linux = {
                                default = pkgs.linkFarm "cotn-modding" {
                                        docs = docs;
                                        hello-world-mod = helloWorldModZip;
                                        hello-world-mod-tests = helloWorldModTestsZip;
                                };
                                docs = docs;
                                hello-world-mod = helloWorldModZip;
                                hello-world-mod-tests = helloWorldModTestsZip;
                        };

                        checks.x86_64-linux = {
                                tests = tests;
                                corpus = corpus;
                                hello-world-mod = helloWorldModZip;
                                hello-world-mod-tests = helloWorldModTestsZip;
                                mods-lua-lint = modsLuaLint;
                                mods-layout = modsLayout;
                        };

                        apps.x86_64-linux = {
                                install-mods = {
                                        type = "app";
                                        program = "${installMods}/bin/install-mods";
                                        meta.description = "Install the named mods into the game as one bundle mod: nix run .#install-mods -- Foo Bar";
                                };

                                scrape-game-data = {
                                        type = "app";
                                        program = "${scrapeGameData}/bin/scrape-game-data";
                                        meta.description = "Run the ScrapeGameData mod in the live game and save its log output to Tmp/scrape-game-data/<date-slug>/";
                                };

                                itj-impure-tests = {
                                        type = "app";
                                        program = "${impureTests}/bin/run-tests";
                                        meta.description = "Rsync mods into the game's local mods directory and run its automated test suite";
                                };
                        };
                };
}
