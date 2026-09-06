{
        description = "IDK. Something to do with CotN mods & vibe coding.";

        inputs = {
                nixpkgs.url = "nixpkgs/nixos-26.05";

                itj_dev_tools = {
                        url = "git+https://github.com/Ivan-Johnson/DevTools.git?ref=refs/heads/mainline";
                        inputs.nixpkgs.follows = "nixpkgs";
                };
                itj_cotn_docs = {
                        url = "git+https://github.com/Ivan-Johnson/CotN-doc-downloader.git?ref=refs/heads/mainline";
                        inputs.nixpkgs.follows = "nixpkgs";
                };
        };

        outputs =
                {
                        self,
                        nixpkgs,
                        itj_dev_tools,
                        itj_cotn_docs,
                }:
                let
                        pkgs = import nixpkgs { system = "x86_64-linux"; };
                        helloWorldModZip = pkgs.runCommand "hello-world-mod-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
                                mkdir -p "$out"
                                cd ${./HelloWorldMod}
                                zip -qr "$out/HelloWorldMod.zip" .
                        '';

                        shell = pkgs.mkShell {
                                buildInputs = with pkgs; [
                                        itj_dev_tools.packages.${pkgs.stdenv.hostPlatform.system}.default

                                        itj_cotn_docs.packages.${pkgs.stdenv.hostPlatform.system}.default

                                        # For packaging mods
                                        pkgs.zip
                                        pkgs.unzip
                                ];
                                shellHook = ''
                                        export ITJ_GIT_PREPUSH_ENABLE_NIX_CHECKS=
                                        alias 'build-install=nix build && nix run .#install-hello-world-mod'
                                '';
                        };
                in
                {
                        devShells.x86_64-linux.default = shell;

                        packages.x86_64-linux.default = helloWorldModZip;

                        apps.x86_64-linux.install-hello-world-mod = {
                                type = "app";
                                program = "${pkgs.writeShellScriptBin "install-hello-world-mod" ''
                                        set -eu

                                        target_dir="$HOME/.local/share/NecroDancer/downloadedMods"

                                        mkdir -p "$target_dir"
                                        cp -f ${helloWorldModZip}/HelloWorldMod.zip "$target_dir/HelloWorldMod.zip"
                                ''}/bin/install-hello-world-mod";
                        };
                };
}
