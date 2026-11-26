# The Mods context's flake outputs: the mod zips, the offline checks (lint,
# layout, and each test-*.lua / test-*.bash), the live-game-run,
# itj-impure-tests and itj-impure-scope apps, and the dev shell, whose
# shellHook locates the game's log and mods directory. `liveGame` is the part
# GameData reuses to run a mod in the live game.
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
        # `Mods/TestFramework`.
        testFrameworkZip = mkModZip "TestFramework" "test-framework-zip";

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
        # `install-mods` relies on. See `Mods/LiveGame/bundle-layout.lua`.
        bundleLayout = pkgs.writeShellApplication {
                name = "bundle-layout";
                runtimeInputs = [
                        pkgs.coreutils
                        pkgs.findutils
                        bundleLuajit
                ];
                text = ''
                        exec luajit ${./LiveGame/bundle-layout.lua} "$@"
                '';
        };

        # The conventions `install-mods` relies on, e.g. that each mod's
        # directory is named after its namespace.
        modsLayout = pkgs.runCommand "cotn-mods-layout" { nativeBuildInputs = [ bundleLayout ]; } ''
                bundle-layout check ${./.}
                touch "$out"
        '';

        # Each claim test file backs the authored page it is named after, so a
        # change to that page runs it
        # (Docs/Adr/0008-claim-tests-run-only-when-their-page-changes.md).
        claimTestsLayout = pkgs.runCommand "cotn-claim-tests-layout" { } ''
                status=0
                for path in ${./ClaimTests}/*.lua; do
                        name=''${path##*/}
                        if [ ! -e "${../AuthoredDocs/Src}/''${name%.lua}.md" ]; then
                                echo "Mods/ClaimTests/$name backs no page: AuthoredDocs/Src/''${name%.lua}.md does not exist" >&2
                                status=1
                        fi
                done
                if ((status != 0)); then
                        exit 1
                fi
                touch "$out"
        '';

        # Tests the layout rules and the rewrite on fixtures, in-process and
        # through the real `bundle-layout` wrapper; see
        # `Mods/LiveGame/test-bundle-layout.lua`.
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
                                cd ${./LiveGame}
                                luajit test-bundle-layout.lua
                                touch "$out"
                        '';

        # Runs the bytecode parser behind `ScrapeGameData` under plain
        # LuaJIT; see `Mods/LiveGame/test-bytecode-api.lua`.
        bytecodeApiTest =
                pkgs.runCommand "cotn-bytecode-api-test" { nativeBuildInputs = [ pkgs.luajit ]; }
                        ''
                                cd ${./.}
                                luajit LiveGame/test-bytecode-api.lua
                                touch "$out"
                        '';

        # Installs mods from the source tree (not the store, which only
        # sees git-tracked files) into the game as one bundle mod. Internal to
        # `liveGameRun`. See `Mods/LiveGame/install-mods.bash`.
        installMods = pkgs.writeShellApplication {
                name = "install-mods";
                runtimeInputs = [
                        pkgs.coreutils
                        bundleLayout
                        pkgs.git
                        pkgs.jq
                        pkgs.rsync
                ];
                text = builtins.readFile ./LiveGame/install-mods.bash;
        };

        # Only correct while CotN runs natively on this machine, under this
        # user, via this specific Proton prefix (id 247080).
        cotnLogPath = "/home/i/.local/share/Steam/steamapps/common/Crypt of the NecroDancer/NecroDancer64/NecroDancer.log";

        # The one module that drives the live game: takes the game-instance
        # lock, installs, forces a reload, and can wait for a log line. Impure,
        # so it lives in `apps`. See `Mods/LiveGame/live-game-run.bash` and
        # Docs/Adr/0009-one-module-owns-the-live-game-instance.md.
        liveGameRun = pkgs.writeShellApplication {
                name = "live-game-run";
                runtimeInputs = [
                        pkgs.coreutils
                        pkgs.gnugrep
                        pkgs.util-linux
                        installMods
                ];
                text = builtins.readFile ./LiveGame/live-game-run.bash;
        };

        # Tests the lock, the wait and the install options against a fake
        # game log; see `Mods/LiveGame/test-live-game-run.bash`.
        liveGameRunTest =
                pkgs.runCommand "cotn-live-game-run-test"
                        {
                                nativeBuildInputs = [
                                        liveGameRun
                                        pkgs.coreutils
                                        pkgs.gnugrep
                                        pkgs.util-linux
                                ];
                        }
                        ''
                                bash ${./LiveGame/test-live-game-run.bash}
                                touch "$out"
                        '';

        # The single unit-test entrypoint: runs each pass through
        # `live-game-run` and judges the results. Impure
        # (needs a running, native Steam/Proton CotN instance and a live mods
        # directory), so it lives in `apps` rather than `checks`: exposed as
        # `nix run .#itj-impure-tests`. See
        # `Mods/LiveGame/itj-impure-tests.bash`.
        impureTests = pkgs.writeShellApplication {
                name = "itj-impure-tests";
                runtimeInputs = [
                        pkgs.coreutils
                        pkgs.git
                        pkgs.gnugrep
                        liveGameRun
                ];
                text = builtins.readFile ./LiveGame/itj-impure-tests.bash;
        };

        # Tests the entrypoint's verdicts against a fake game log, through the
        # real `live-game-run`; see `Mods/LiveGame/test-itj-impure-tests.bash`.
        impureTestsTest =
                pkgs.runCommand "cotn-impure-tests-test"
                        {
                                nativeBuildInputs = [
                                        impureTests
                                        pkgs.coreutils
                                        pkgs.gnugrep
                                        pkgs.util-linux
                                ];
                        }
                        ''
                                bash ${./LiveGame/test-itj-impure-tests.bash}
                                touch "$out"
                        '';

        # Tells `build-release` whether a change can affect the live suite;
        # see `Mods/LiveGame/itj-impure-scope.bash`.
        impureScope = pkgs.writeShellApplication {
                name = "itj-impure-scope";
                runtimeInputs = [ pkgs.git ];
                text = builtins.readFile ./LiveGame/itj-impure-scope.bash;
        };

        # Feeds the classifier fixture path lists and checks its prefix lists
        # against the repo's tracked files; see
        # `Mods/LiveGame/test-itj-impure-scope.bash`.
        impureScopeTest =
                pkgs.runCommand "cotn-impure-scope-test"
                        {
                                nativeBuildInputs = [
                                        impureScope
                                        pkgs.coreutils
                                ];
                        }
                        ''
                                bash ${./LiveGame/test-itj-impure-scope.bash} ${../.}
                                touch "$out"
                        '';
in
{
        # What other modules need to drive the live game; not merged into the
        # flake's outputs.
        liveGame = { inherit liveGameRun; };

        packages = {
                hello-world-mod = helloWorldModZip;
                test-framework = testFrameworkZip;
        };

        checks = {
                mods-lua-lint = modsLuaLint;
                mods-layout = modsLayout;
                claim-tests-layout = claimTestsLayout;
                bytecode-api = bytecodeApiTest;
                bundle-layout = bundleLayoutTest;
                live-game-run = liveGameRunTest;
                impure-tests = impureTestsTest;
                impure-scope = impureScopeTest;
        };

        apps = {
                live-game-run = {
                        type = "app";
                        program = "${liveGameRun}/bin/live-game-run";
                        meta.description = "Lock the game, install the named mods as one bundle mod and reload: nix run .#live-game-run -- [--until LINE] Foo Bar";
                };

                itj-impure-tests = {
                        type = "app";
                        program = "${impureTests}/bin/itj-impure-tests";
                        meta.description = "Rsync mods into the game's local mods directory and run its automated test suite";
                };

                itj-impure-scope = {
                        type = "app";
                        program = "${impureScope}/bin/itj-impure-scope";
                        meta.description = "Print none, all, or the test files that the changed paths on stdin can affect";
                };
        };

        devShell = pkgs.mkShell {
                buildInputs = [
                        impureTests
                        liveGameRun

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
                        export COTN_COMPATDATA="$HOME/.local/share/Steam/steamapps/compatdata/247080"
                        export COTN_LOCAL_MODS_DIR="$COTN_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/NecroDancer/mods/"

                        export COTN_LOG="${cotnLogPath}"
                        # The whole Proton prefix is read-only (e.g. for replays); the
                        # mods dir is bound read-write on top of it.
                        export EXTRA_RO_BINDS="''${EXTRA_RO_BINDS:+''$EXTRA_RO_BINDS:}$COTN_LOG:$COTN_COMPATDATA"
                        export EXTRA_RW_BINDS="''${EXTRA_RW_BINDS:+''$EXTRA_RW_BINDS:}$COTN_LOCAL_MODS_DIR"
                '';
        };
}
