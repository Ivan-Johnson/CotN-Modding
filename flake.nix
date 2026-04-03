{
	description = "Dev Env for PracticeTracker2";

	inputs = {
		nixpkgs.url = "nixpkgs/nixos-25.11-small";
		fenix = {
			url = "github:nix-community/fenix";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs =
		{
			self,
			nixpkgs,
			fenix,
		}:
		let
			pkgs = import nixpkgs {
				system = "x86_64-linux";
				config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "vscode" ];
			};
		in
		{
			devShells.x86_64-linux.default = pkgs.mkShell {
				buildInputs = [
					pkgs.vscode
				];
			};
		};
}
