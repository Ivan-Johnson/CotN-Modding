{ pkgs }:
let
        mkModZip =
                name: drvName:
                pkgs.runCommand drvName { nativeBuildInputs = [ pkgs.zip ]; } ''
                        mkdir -p "$out"
                        cd ${./.}/${name}
                        zip -qr "$out/${name}.zip" .
                '';

        helloWorldModZip = mkModZip "HelloWorld" "hello-world-mod-zip";

        # Not shipped to players; a generic test-running framework that
        # HelloWorld (and any other mod under test) optionally requires at
        # load-time to register and run its behavioral tests. See
        # `Mods/HelloWorldTests`.
        helloWorldModTestsZip = mkModZip "HelloWorldTests" "hello-world-mod-tests-zip";

        # Static analysis of every mod's Lua, catching syntax errors and
        # undefined globals (e.g. a typo'd event name) without needing the
        # game itself. `Mods/.luacheckrc` declares the globals Synchrony
        # injects into mods, such as `event`.
        modsLuaLint =
                pkgs.runCommand "cotn-mods-luacheck" { nativeBuildInputs = [ pkgs.luaPackages.luacheck ]; }
                        ''
                                luacheck --config ${./.luacheckrc} ${./.}
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
                                bash ${./check-layout.bash} ${./.}
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
                text = builtins.readFile ./install-mods.bash;
        };

        # Only correct while CotN runs natively on this machine, under this
        # user, via this specific Proton prefix (id 247080).
        cotnLogPath = "/home/i/.local/share/Steam/steamapps/common/Crypt of the NecroDancer/NecroDancer64/NecroDancer.log";

        # Shell function shared by the live-game apps. `wait_for_log BASELINE
        # SENTINEL` polls the `NecroDancer.log` lines after line BASELINE for
        # SENTINEL, and returns 1 if it doesn't appear within 60s, so callers
        # decide how to react.
        waitForLog = ''
                wait_for_log() {
                        local baseline=$1 sentinel=$2 timeoutSeconds=60 start
                        start=$(date +%s)
                        while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -qF "$sentinel"; do
                                sleep 0.1
                                if ((($(date +%s) - start) >= timeoutSeconds)); then
                                        return 1
                                fi
                        done
                }
        '';

        # Drives the game's live-reload and asserts on the resulting log
        # output. Impure (needs a running, native Steam/Proton CotN
        # instance and a live mods directory), so it lives in `apps`
        # rather than `checks`: exposed as `nix run .#itj-impure-tests`.
        impureTests = pkgs.writeShellApplication {
                name = "run-tests";
                runtimeInputs = [
                        pkgs.coreutils
                        pkgs.gnugrep
                ];
                text = ''
                        ${waitForLog}

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
                        timedOut=0
                        if ! wait_for_log "$baseline" "[HelloWorldTests] Test suite completed"; then
                                echo "itj-impure-tests: timed out waiting for test suite completion" >&2
                                timedOut=1
                        fi

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
                        ${waitForLog}

                        outDir="$ITJ_FLAKE_ROOT/Tmp/scrape-game-data/$(date +%Y-%m-%d_%H-%M-%S)"
                        mkdir -p "$outDir"

                        baseline=$(wc -l <"$COTN_LOG")

                        ITJ_BUNDLE_RELOAD_TRIGGER="ScrapeGameData/ScrapeGameData.lua" ${installMods}/bin/install-mods ScrapeGameData

                        if ! wait_for_log "$baseline" "[ScrapeGameData] end"; then
                                echo "scrape-game-data: timed out waiting for the end sentinel" >&2
                                exit 1
                        fi

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
        packages = {
                hello-world-mod = helloWorldModZip;
                hello-world-mod-tests = helloWorldModTestsZip;
        };

        checks = {
                mods-lua-lint = modsLuaLint;
                mods-layout = modsLayout;
        };

        apps = {
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

        devShell = pkgs.mkShell {
                buildInputs = [
                        impureTests
                        installMods

                        # For packaging mods
                        pkgs.zip
                        pkgs.unzip
                ];
                shellHook = ''
                        # This path is platform specific. e.g. if you're running the native steam runtime vs proton
                        # todo: commonize?
                        export COTN_LOCAL_MODS_DIR="$HOME/.local/share/Steam/steamapps/compatdata/247080/pfx/drive_c/users/steamuser/AppData/Local/NecroDancer/mods/"

                        export COTN_LOG="${cotnLogPath}"
                        export EXTRA_RO_BINDS="''${EXTRA_RO_BINDS:+''$EXTRA_RO_BINDS:}$COTN_LOG"
                        export EXTRA_RW_BINDS="''${EXTRA_RW_BINDS:+''$EXTRA_RW_BINDS:}$COTN_LOCAL_MODS_DIR"
                '';
        };
}
