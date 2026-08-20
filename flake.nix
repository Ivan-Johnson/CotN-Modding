{
	description = "IDK. Something to do with CotN mods & vibe coding.";

	inputs = {
		nixpkgs.url = "nixpkgs/nixos-26.05";
	};

	outputs =
		{ self, nixpkgs }:
		let
			pkgs = import nixpkgs { system = "x86_64-linux"; };

			shell = pkgs.mkShell {
				buildInputs = with pkgs; [
					pkgs.coreutils
					pkgs.which
					pkgs.bash
					pkgs.git
					pkgs.nix
					pkgs.nixfmt

					# For packaging mods
					pkgs.zip
					pkgs.unzip
				];
				shellHook = "";
			};
		in
		{
			devShells.x86_64-linux.default = shell;

			# TODO - actually build something useful here
			packages.x86_64-linux.default = shell;
		};
}
