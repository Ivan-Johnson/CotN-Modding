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
					docs
				];
				shellHook = ''
					export MANPATH="${docs}/share/man''${MANPATH:+:$MANPATH}"
				'';
			};

			# The markdown and man page renderings of the HTML mirrored in the
			# CotN-docs repo.
			docs =
				pkgs.runCommand "cotn-docs-rendered"
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
						bash ${./html-to-docs.bash} ${cotn-docs} "$out"
					'';
		in
		{
			devShells.x86_64-linux.default = shell;

			# A single derivation renders every format; the aliases are just
			# conveniences for `nix build .#markdown` / `nix build .#man`.
			packages.x86_64-linux.default = docs;
			packages.x86_64-linux.markdown = docs;
			packages.x86_64-linux.man = docs;
		};
}
