{
	description = "Offline version of the CotN modding docs";

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

		dev_tools = {
			url = "git+https://github.com/Ivan-Johnson/DevTools.git?ref=refs/heads/mainline";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs =
		{
			self,
			nixpkgs,
			fenix,
			cotn-docs,
			dev_tools,
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
				buildInputs = conversionTools ++ [ dev_tools.packages.${pkgs.stdenv.hostPlatform.system}.default ];
				# `docs` is deliberately not an input of this shell. Depending on
				# it would mean the shell could not be entered whenever the
				# conversion is broken, which is exactly when it is needed. It is
				# built on demand instead.
				shellHook = ''
					# Rebuild the documentation, then read a page from it.
					man-crypt() {
						local out="$(nix build --no-link --print-out-paths "$ITJ_FLAKE_ROOT")" || return
						MANPATH="$out/share/man" man "$@"
					}
					export -f man-crypt
				'';
			};

			# The scripts, isolated from the generated state around them so that
			# a rebuilt `result` or a fresh crawl does not invalidate the tests.
			scripts = pkgs.lib.fileset.toSource {
				root = ./.;
				fileset = pkgs.lib.fileset.unions [
					./check-docs.bash
					./crawl-and-push.bash
					./html-to-docs.bash
					./test-html-to-docs.bash
				];
			};

			# The conversion's own tests, which build throwaway crawls of their
			# own and so need nothing from the network or the mirror.
			tests = pkgs.runCommand "cotn-docs-tests" { nativeBuildInputs = conversionTools; } ''
				export LC_ALL=C.UTF-8
				cd ${scripts}
				bash -n *.bash
				bash ./test-html-to-docs.bash
				touch "$out"
			'';

			# The markdown and man page renderings of the HTML mirrored in the
			# CotN-docs repo.
			docs =
				pkgs.runCommand "cotn-docs-rendered" { nativeBuildInputs = conversionTools ++ [ pkgs.man-db ]; }
					''
						export LC_ALL=C.UTF-8
						bash ${./html-to-docs.bash} ${cotn-docs} "$out"

						# `man -k` and `whatis` search an index rather than the pages
						# themselves, and nothing can build one later, because by then
						# the pages live in the read only store. MANDB_MAP is what
						# tells `mandb` where a manpath's index belongs; without it
						# there is nowhere to put one, and it quietly builds nothing.
						echo "MANDATORY_MANPATH $out/share/man" >man.conf
						echo "MANDB_MAP $out/share/man $out/share/man" >>man.conf
						mandb --config-file man.conf --create

						# Keep the index, but not the empty directory `mandb` makes to
						# cache formatted pages in; the store has no use for it.
						rm -rf "$out/share/man/cat"*
					'';

			# The same conversion, checked over a whole build rather than a
			# handwritten crawl of two or three pages.
			corpus = pkgs.runCommand "cotn-docs-corpus" { nativeBuildInputs = conversionTools; } ''
				export LC_ALL=C.UTF-8
				bash ${./check-docs.bash} ${docs}
				touch "$out"
			'';
		in
		{
			devShells.x86_64-linux.default = shell;

			packages.x86_64-linux.default = docs;

			checks.x86_64-linux.tests = tests;

			checks.x86_64-linux.corpus = corpus;
		};
}
