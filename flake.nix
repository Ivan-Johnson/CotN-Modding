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
                        system = "x86_64-linux";
                        pkgs = import nixpkgs { inherit system; };

                        mods = import ./Mods/flake-module.nix { inherit pkgs; };

                        docDownloader = import ./DocDownloader/flake-module.nix {
                                inherit pkgs;
                                official = cotn-docs-official;
                        };

                        # An array of all the different `flake-module.nix`s
                        modules = [
                                docDownloader
                                (import ./AuthoredDocs/flake-module.nix {
                                        inherit pkgs;
                                        official = cotn-docs-official;
                                        gameData = cotn-docs-game-data;
                                        inherit (docDownloader) converted;
                                })
                                mods
                                (import ./GameData/flake-module.nix {
                                        inherit pkgs;
                                        inherit (mods) liveGame;
                                })
                        ];

                        disjointUnion = pkgs.lib.foldl' pkgs.lib.attrsets.unionOfDisjoint { };

                        # Flatten the modules
                        #
                        # e.g. `modules[*].packages` -> `merged.packages`
                        merged = {
                                packages = disjointUnion (map (m: m.packages or { }) modules);
                                checks = disjointUnion (map (m: m.checks or { }) modules);
                                apps = disjointUnion (map (m: m.apps or { }) modules);

                                # Unlike the other merged.*, which are attribute
                                # sets, `devShellList` is a list.
                                devShellList = map (m: m.devShell) modules;
                        };
                in
                {
                        devShells.${system}.default = pkgs.mkShell {
                                inputsFrom = [
                                        dev-tools.devShells.${system}.default
                                        dev-tools.devShells.${system}.github-cli
                                ]
                                ++ merged.devShellList;
                                shellHook = ''
                                        export ITJ_GIT_PREPUSH_ENABLE_NIX_CHECKS=
                                '';
                        };

                        packages.${system} = disjointUnion [
                                # The default is to build a linkfarm of all modules
                                { default = pkgs.linkFarm "cotn-modding" merged.packages; }

                                # Alternatively you can build just one module; e.g. `nix build .#docs`
                                merged.packages
                        ];

                        checks.${system} = merged.checks;

                        apps.${system} = merged.apps;
                };
}
