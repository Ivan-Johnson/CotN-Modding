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
			pkgs = import nixpkgs { system = "x86_64-linux"; };
			helloWorldMan = pkgs.runCommand "hello-world-manpage" { } ''
				mkdir -p "$out/share/man/man1"
				cp ${./man/hello-world.1} "$out/share/man/man1/hello-world.1"
			'';

			shell = pkgs.mkShell {
				buildInputs = [
					pkgs.bash
					pkgs.coreutils
					pkgs.git
					pkgs.gnumake
					pkgs.htmlq
					pkgs.less
					pkgs.man-db
					pkgs.nix
					pkgs.nixfmt
					pkgs.pandoc
					pkgs.which
					helloWorldMan
				];
				shellHook = ''
					export MANPATH="${helloWorldMan}/share/man''${MANPATH:+:$MANPATH}"
				'';
			};
		in
		{
			devShells.x86_64-linux.default = shell;

			# TODO - can we do something useful here instead?
			packages.x86_64-linux.default = shell;
		};
}
