{
        description = "IDK. Something to do with CotN mods & vibe coding.";

        inputs = {
                nixpkgs.url = "nixpkgs/nixos-26.05";

                itj_dev_tools = {
                        url = "git+https://github.com/Ivan-Johnson/DevTools.git?ref=refs/heads/mainline";
                        inputs.nixpkgs.follows = "nixpkgs";
                };
        };

        outputs =
                {
                        self,
                        nixpkgs,
                        itj_dev_tools,
                }:
                let
                        pkgs = import nixpkgs { system = "x86_64-linux"; };
                in
                {
                        devShells.x86_64-linux.default = pkgs.mkShell {
                                buildInputs = with pkgs; [ itj_dev_tools.packages.${pkgs.stdenv.hostPlatform.system}.default ];
                        };
                };
}
