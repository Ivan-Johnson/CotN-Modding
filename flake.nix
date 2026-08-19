{
	description = "Dev Env for PracticeTracker2";

	inputs = {
		nixpkgs.url = "nixpkgs/nixos-26.05";
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

			shell = pkgs.mkShell {
				buildInputs = [
					pkgs.gnumake
					pkgs.htmlq
					pkgs.pandoc
					pkgs.vscode
				];
			};
		in
		{
			devShells.x86_64-linux.default = shell;

			# TODO - update my pre-push hook so that it doesn't require this to exist
			packages.x86_64-linux.default = shell;
		};
}
