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

        bundleLuajit = pkgs.luajit.withPackages (p: [ p.cjson ]);

        # Validates and rewrites the bundle layout; the one home of the rules
        # `install-mods` relies on. See `Mods/bundle-layout.lua`.
        bundleLayout = pkgs.writeShellApplication {
                name = "bundle-layout";
                runtimeInputs = [
                        pkgs.coreutils
                        pkgs.findutils
                        bundleLuajit
                ];
                text = ''
                        exec luajit ${./bundle-layout.lua} "$@"
                '';
        };

        # The conventions `install-mods` relies on, e.g. that each mod's
        # directory is named after its namespace.
        modsLayout = pkgs.runCommand "cotn-mods-layout" { nativeBuildInputs = [ bundleLayout ]; } ''
                bundle-layout check ${./.}
                touch "$out"
        '';

        # Tests the layout rules and the rewrite on fixtures, in-process and
        # through the real `bundle-layout` wrapper; see
        # `Mods/test-bundle-layout.lua`.
        bundleLayoutTest =
                pkgs.runCommand "cotn-bundle-layout-test"
                        {
                                nativeBuildInputs = [
                                        bundleLayout
                                        bundleLuajit
                                        pkgs.coreutils
                                ];
                        }
                        ''
                                cd ${./.}
                                luajit test-bundle-layout.lua
                                touch "$out"
                        '';

        # Runs the bytecode parser behind `ScrapeGameData` under plain
        # LuaJIT; see `Mods/test-bytecode-api.lua`.
        bytecodeApiTest =
                pkgs.runCommand "cotn-bytecode-api-test" { nativeBuildInputs = [ pkgs.luajit ]; }
                        ''
                                cd ${./.}
                                luajit test-bytecode-api.lua
                                touch "$out"
                        '';

        # Installs mods from the source tree (not the store, which only
        # sees git-tracked files) into the game as one bundle mod. See
        # `Mods/install-mods.bash`.
        installMods = pkgs.writeShellApplication {
                name = "install-mods";
                runtimeInputs = [
                        pkgs.coreutils
                        bundleLayout
                        pkgs.jq
                        pkgs.rsync
                ];
                text = builtins.readFile ./install-mods.bash;
        };

        # Only correct while CotN runs natively on this machine, under this
        # user, via this specific Proton prefix (id 247080).
        cotnLogPath = "/home/i/.local/share/Steam/steamapps/common/Crypt of the NecroDancer/NecroDancer64/NecroDancer.log";

        # Shell function shared by the live-game apps. `wait_for_log BASELINE
        # SENTINEL [TIMEOUT_SECONDS [STALL_SECONDS]]` polls the `NecroDancer.log`
        # lines after line BASELINE for SENTINEL. It returns 1 if SENTINEL
        # doesn't appear within TIMEOUT_SECONDS (default 60), and 2 if the log
        # gains no bytes for STALL_SECONDS (default 0, which turns the check
        # off), so callers decide how to react and can tell a slow game from a
        # silent one.
        waitForLog = ''
                wait_for_log() {
                        local baseline=$1 sentinel=$2 timeoutSeconds=''${3:-60} stallSeconds=''${4:-0}
                        local start now lastSize size lastChange
                        start=$(date +%s)
                        lastChange=$start
                        lastSize=$(stat -c %s "$COTN_LOG")
                        while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -qF "$sentinel"; do
                                sleep 0.1
                                now=$(date +%s)
                                size=$(stat -c %s "$COTN_LOG")
                                if ((size != lastSize)); then
                                        lastSize=$size
                                        lastChange=$now
                                fi
                                if ((stallSeconds > 0 && now - lastChange >= stallSeconds)); then
                                        return 2
                                fi
                                if ((now - start >= timeoutSeconds)); then
                                        return 1
                                fi
                        done
                }
        '';

        # The single unit-test entrypoint: takes the game-instance lock,
        # installs the mods, runs the tests and prints the results. Impure
        # (needs a running, native Steam/Proton CotN instance and a live mods
        # directory), so it lives in `apps` rather than `checks`: exposed as
        # `nix run .#itj-impure-tests`. See `Mods/itj-impure-tests.bash`.
        impureTests = pkgs.writeShellApplication {
                name = "run-tests";
                runtimeInputs = [
                        pkgs.coreutils
                        pkgs.gnugrep
                        pkgs.util-linux
                        installMods
                ];
                text = ''
                        ${waitForLog}
                        ${builtins.readFile ./itj-impure-tests.bash}
                '';
        };

        # Tests the entrypoint's lock without a live game; see
        # `Mods/test-itj-impure-tests-lock.bash`.
        impureTestsLockTest =
                pkgs.runCommand "cotn-impure-tests-lock-test"
                        {
                                nativeBuildInputs = [
                                        impureTests
                                        pkgs.coreutils
                                        pkgs.gnugrep
                                        pkgs.util-linux
                                ];
                        }
                        ''
                                bash ${./test-itj-impure-tests-lock.bash}
                                touch "$out"
                        '';
in
{
        # What other modules need to drive the live game; not merged into the
        # flake's outputs.
        liveGame = { inherit installMods waitForLog; };

        packages = {
                hello-world-mod = helloWorldModZip;
                hello-world-mod-tests = helloWorldModTestsZip;
        };

        checks = {
                mods-lua-lint = modsLuaLint;
                mods-layout = modsLayout;
                bytecode-api = bytecodeApiTest;
                bundle-layout = bundleLayoutTest;
                impure-tests-lock = impureTestsLockTest;
        };

        apps = {
                install-mods = {
                        type = "app";
                        program = "${installMods}/bin/install-mods";
                        meta.description = "Install the named mods into the game as one bundle mod: nix run .#install-mods -- Foo Bar";
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

                        # For checking mod Lua before a live reload
                        pkgs.luaPackages.luacheck
                        pkgs.luajit
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
