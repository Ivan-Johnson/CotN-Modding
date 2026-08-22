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

			# Everything `html-to-docs.bash` needs to run.
			conversionTools = [
				pkgs.bash
				pkgs.coreutils
				pkgs.findutils
				pkgs.htmlq
				pkgs.pandoc
			];

			shell = pkgs.mkShell {
				buildInputs = conversionTools ++ [
					pkgs.git
					pkgs.gnumake
					pkgs.less
					pkgs.man-db
					pkgs.nix
					pkgs.nixfmt
					pkgs.which
				];
				# `docs` is deliberately not an input of this shell. Depending on
				# it would mean the shell could not be entered whenever the
				# conversion is broken, which is exactly when it is needed. It is
				# built on demand instead.
				shellHook = ''
					# Rebuild the documentation, then read a page from it.
					man-crypt() {
						local out="$(nix build --no-link --print-out-paths "$ITJ_FLAKE_ROOT#man")" || return
						MANPATH="$out/share/man" man "$@"
					}
					export -f man-crypt
				'';
			};

			# The markdown and man page renderings of the HTML mirrored in the
			# CotN-docs repo.
			docs = pkgs.runCommand "cotn-docs-rendered" { nativeBuildInputs = conversionTools; } ''
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
