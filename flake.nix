{
        description = "Crypt of the NecroDancer Synchrony modding: API docs and mods";

        inputs = {
                nixpkgs.url = "nixpkgs/nixos-26.05";

                dev-tools = {
                        url = "git+https://github.com/Ivan-Johnson/DevTools.git?ref=refs/heads/mainline";
                        inputs.nixpkgs.follows = "nixpkgs";
                };

                cotn-docs = {
                        url = "git+ssh://git@github.com/Ivan-Johnson/CotN-docs.git?ref=mainline";
                        flake = false;
                };
        };

        outputs =
                {
                        self,
                        nixpkgs,
                        dev-tools,
                        cotn-docs,
                }:
                let
                        pkgs = import nixpkgs { system = "x86_64-linux"; };

                        # Everything `html-to-docs.bash` needs to run.
                        conversionTools = [
                                pkgs.bash
                                pkgs.coreutils
                                pkgs.findutils
                                pkgs.htmlq
                                pkgs.pandoc
                                pkgs.man-db
                        ];

                        # The scripts, isolated from the generated state around them so that
                        # a rebuilt `result` or a fresh crawl does not invalidate the tests.
                        scripts = pkgs.lib.fileset.toSource {
                                root = ./DocDownloader;
                                fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "bash") ./DocDownloader;
                        };

                        # The conversion's own tests, which build throwaway crawls of their
                        # own and so need nothing from the network or the mirror.
                        tests = pkgs.runCommand "cotn-docs-tests" { nativeBuildInputs = conversionTools; } ''
                                export LC_ALL=C.UTF-8
                                cd ${scripts}
                                bash -n *.bash
                                bash ./test-html-to-docs.bash
                                touch "$out"
                        '';

                        # The markdown and man page renderings of the HTML mirrored in the
                        # CotN-docs repo, before they are indexed.
                        pages = pkgs.runCommand "cotn-docs-pages" { nativeBuildInputs = conversionTools; } ''
                                export LC_ALL=C.UTF-8
                                bash ${./DocDownloader/html-to-docs.bash} ${cotn-docs} "$out"

                                cp -r ${cotn-docs} "$out/html-original"
                        '';

                        # The same renderings, with a `mandb` index over them. `man -k` and
                        # `whatis` search that index rather than the pages themselves, and
                        # nothing can build one later, because by then the pages live in the
                        # read only store.
                        #
                        # Indexing is a stage of its own because `mandb` records each page's
                        # mtime, and Nix normalizes mtimes only once a builder has exited.
                        # Reading the pages back out of `pages`, where Nix has already
                        # normalized them, is what keeps the index reproducible.
                        docs = pkgs.runCommand "cotn-docs-rendered" { nativeBuildInputs = [ pkgs.man-db ]; } ''
                                cp -a ${pages} "$out"
                                chmod -R u+w "$out"

                                # MANDB_MAP is what tells `mandb` where a manpath's index
                                # belongs; without it there is nowhere to put one, and it
                                # quietly builds nothing.
                                echo "MANDATORY_MANPATH $out/share/man" >man.conf
                                echo "MANDB_MAP $out/share/man $out/share/man" >>man.conf
                                mandb --config-file man.conf --create

                                # Keep the index, but not the empty directory `mandb` makes to
                                # cache formatted pages in; the store has no use for it.
                                rm -rf "$out/share/man/cat"*

                                # It appears as though `MANPATH` is constructed automatically
                                # from `PATH`: if we don't create this empty `bin` directory,
                                # then `man` won't be able to find our `share/man` directory.
                                mkdir -p "$out/bin"
                        '';

                        # The same conversion, checked over a whole build rather than a
                        # handwritten crawl of two or three pages.
                        corpus = pkgs.runCommand "cotn-docs-corpus" { nativeBuildInputs = conversionTools ++ [ docs ]; } ''
                                export LC_ALL=C.UTF-8
                                bash ${./DocDownloader/check-docs.bash} ${docs}
                                touch "$out"
                        '';

                        helloWorldModZip = pkgs.runCommand "hello-world-mod-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
                                mkdir -p "$out"
                                cd ${./Mods/HelloWorldMod}
                                zip -qr "$out/HelloWorldMod.zip" .
                        '';

                        # Not shipped to players; drives a deterministic run of HelloWorldMod
                        # and asserts on its behavior. See `Mods/HelloWorldModTests`.
                        helloWorldModTestsZip =
                                pkgs.runCommand "hello-world-mod-tests-zip" { nativeBuildInputs = [ pkgs.zip ]; }
                                        ''
                                                mkdir -p "$out"
                                                cd ${./Mods/HelloWorldModTests}
                                                zip -qr "$out/HelloWorldModTests.zip" .
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

                        # Only correct while CotN runs natively on this machine, under this
                        # user, via this specific Proton prefix (id 247080).
                        cotnLogPath = "/home/i/.local/share/Steam/steamapps/common/Crypt of the NecroDancer/NecroDancer64/NecroDancer.log";

                        # Drives the game's hot-reload and asserts on the resulting log
                        # output. Impure (needs a running, native Steam/Proton CotN
                        # instance and a live mods directory), so it lives in `apps`
                        # rather than `checks`: exposed as `nix run .#itj-impure-tests`.
                        impureTests = pkgs.writeShellApplication {
                                name = "itj-impure-tests";
                                runtimeInputs = [ pkgs.coreutils ];
                                text = ''
                                        ${pkgs.rsync}/bin/rsync -rlt --delete --delay-updates "$ITJ_FLAKE_ROOT/Mods/HelloWorldMod" "$COTN_LOCAL_MODS_DIR"

                                        # ModLoader reloads only on content changes, not mtime, so the
                                        # tests mod's entry script is rewritten with a unique trailing
                                        # comment every run to force its test suite to re-fire.
                                        entryScript="HelloWorldTests.lua"
                                        ${pkgs.rsync}/bin/rsync -rlt --delete --delay-updates --exclude "/$entryScript" \
                                                "$ITJ_FLAKE_ROOT/Mods/HelloWorldModTests/" "$COTN_LOCAL_MODS_DIR/HelloWorldModTests/"
                                        {
                                                cat "$ITJ_FLAKE_ROOT/Mods/HelloWorldModTests/$entryScript"
                                                echo "-- itj-impure-tests trigger $(date +%s%N)"
                                        } >"$COTN_LOCAL_MODS_DIR/HelloWorldModTests/$entryScript"

                                        # Wait for the tests mod's completion sentinel, rather than a
                                        # hardcoded sleep or a quiet-period guess.
                                        timeoutSeconds=60
                                        baseline=$(wc -l <"$COTN_LOG")
                                        start=$(date +%s)
                                        while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -qF "[HelloWorldTests] Test suite completed"; do
                                                sleep 0.1
                                                if ((($(date +%s) - start) >= timeoutSeconds)); then
                                                        echo "itj-impure-tests: timed out waiting for test suite completion" >&2
                                                        break
                                                fi
                                        done

                                        tail -n "+$((baseline + 1))" "$COTN_LOG"
                                '';
                        };
                in
                {
                        devShells.x86_64-linux.default = pkgs.mkShell {
                                buildInputs = conversionTools ++ [
                                        dev-tools.packages.${pkgs.stdenv.hostPlatform.system}.default

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
                                                MANPATH="$out/share/man" man "$@"
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
                                pages = pages;
                                hello-world-mod = helloWorldModZip;
                                hello-world-mod-tests = helloWorldModTestsZip;
                        };

                        checks.x86_64-linux = {
                                tests = tests;
                                corpus = corpus;
                                hello-world-mod = helloWorldModZip;
                                hello-world-mod-tests = helloWorldModTestsZip;
                                mods-lua-lint = modsLuaLint;
                        };

                        apps.x86_64-linux.itj-impure-tests = {
                                type = "app";
                                program = "${impureTests}/bin/itj-impure-tests";
                                meta.description = "Rsync mods into the game's local mods directory and run its automated test suite";
                        };
                };
}
