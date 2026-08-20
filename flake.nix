{
	description = "IDK. Something to do with CotN mods & vibe coding.";

	inputs = {
		nixpkgs.url = "nixpkgs/nixos-26.05";
	};

	outputs =
		{ self, nixpkgs }:
		let
			pkgs = import nixpkgs { system = "x86_64-linux"; };
			helloWorldModZip = pkgs.runCommand "hello-world-mod-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
				mkdir -p "$out"
				cd ${./HelloWorldMod}
				zip -qr "$out/HelloWorldMod.zip" .
			'';

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
				shellHook = "
					alias 'build-install="nix build && nix run .#install-hello-world-mod"'
				";
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
