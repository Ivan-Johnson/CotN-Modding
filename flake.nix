{
	description = "Dev Env for PracticeTracker2";

	inputs = {
		nixpkgs.url = "nixpkgs/nixos-26.05";
		fenix = {
			url = "github:nix-community/fenix";
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
			fenix,
			cotn-docs,
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

			# The markdown rendering of the HTML mirrored in the CotN-docs repo.
			markdown =
				pkgs.runCommand "cotn-docs-markdown"
					{
						nativeBuildInputs = [
							pkgs.bash
							pkgs.coreutils
							pkgs.findutils
							pkgs.htmlq
							pkgs.pandoc
						];
					}
					''
						export LC_ALL=C.UTF-8
						bash ${./html-to-markdown.bash} ${cotn-docs} "$out"
					'';
		in
		{
			devShells.x86_64-linux.default = shell;

			packages.x86_64-linux.default = markdown;
			packages.x86_64-linux.markdown = markdown;
		};
}
