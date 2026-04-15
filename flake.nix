{
	description = "Multi-user shared Steam library for Linux using bubblewrap overlay";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
	};

	outputs = { self, nixpkgs, ... }:
		let
			supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
			forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
		in
		{
			packages = forAllSystems (system:
				let
					pkgs = nixpkgs.legacyPackages.${system};

					activate = pkgs.writeShellApplication {
						name = "steam-shared-activate";
						runtimeInputs = with pkgs; [ acl coreutils findutils ];
						text = ''
							exec "${self}/scripts/activate.sh" "$@"
						'';
					};

					uninstall = pkgs.writeShellApplication {
						name = "steam-shared-uninstall";
						runtimeInputs = with pkgs; [ coreutils ];
						text = ''
							exec "${self}/scripts/uninstall.sh" "$@"
						'';
					};

					add-user = pkgs.writeShellApplication {
						name = "steam-shared-add-user";
						runtimeInputs = with pkgs; [ coreutils ];
						text = ''
							exec "${self}/scripts/add-user.sh" "$@"
						'';
					};
				in
				{
					inherit activate uninstall add-user;
					default = activate;
				}
			);
		};
}
