{
	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

		nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
		nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

		agenix = {
			url = "github:ryantm/agenix";
			inputs.nixpkgs.follows = "nixpkgs";
			inputs.darwin.follows = "nix-darwin";
		};
	};

	outputs = inputs@{ self, nix-darwin, nixpkgs, agenix }: let
		hostname = "mba";
		system = "aarch64-darwin";
		configuration = { pkgs, ... }: {
			nix.settings.experimental-features = "nix-command flakes";
			networking.hostName = hostname;

			system.primaryUser = "veeti";
			users.users.veeti = {
				name = "veeti";
				home = "/Users/veeti";
			};

			environment.systemPackages = [
				pkgs.vim
				pkgs.git
				pkgs.fzf
				pkgs.neovim
				agenix.packages.${system}.agenix
			];

			programs.zsh.enable = true;
			environment.shellAliases = {
				nixswitch = "sudo darwin-rebuild switch --flake .#mba";
				ls = "eza -la";
				f = "cd \"$(find ~/code ~/things -type d -maxdepth 7 -print0 | fzf --read0)\"";
				gs = "git status --short";
				gl = "git log --oneline --decorate --color";

				e = "nvim";
				k = "kubectl";
			};

			security.pam.services.sudo_local = {
				enable = true;
				touchIdAuth = true;
			};

			system.defaults = {
				NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud = false;
				
				NSGlobalDomain.AppleICUForce24HourTime = true;
				NSGlobalDomain.AppleTemperatureUnit = "Celsius";
				NSGlobalDomain.AppleMeasurementUnits = "Centimeters";
				NSGlobalDomain.AppleMetricUnits = 1;
				menuExtraClock.Show24Hour = true;
				menuExtraClock.ShowSeconds = true;

				controlcenter.BatteryShowPercentage = true;
				controlcenter.Bluetooth = true;
				dock = {
					orientation = "right";
					autohide = true;
					showhidden = true;
					show-recents = false;
					mru-spaces = false;
					tilesize = 34;
					persistent-apps = [];
				};

				CustomSystemPreferences."com.apple.dock" = {
					wvous-tl-corner = 0;
					wvous-tr-corner = 0;
					wvous-bl-corner = 0;
					wvous-br-corner = 0;
				};

				LaunchServices.LSQuarantine = false;
				CustomSystemPreferences."com.apple.screensaver" = {
					askForPassword = 1;
					askForPasswordDelay = 0;
				};
				loginwindow = {
					DisableConsoleAccess = true;
					GuestEnabled = false;
				};

				CustomSystemPreferences."com.apple.AdLib" = {
					allowApplePersonalizedAdvertising = false;
					allowIdentifierForAdvertising = false;
					forceLimitAdTracking = true;
					personalizedAdsMigrated = false;
				};
			};
			system.startup.chime = false;

			system.defaults.trackpad = {
				Clicking = false;
				Dragging = false;
			};
			system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
			system.defaults.NSGlobalDomain.KeyRepeat = 1;
			system.keyboard.enableKeyMapping = true;
			system.keyboard.remapCapsLockToControl = true;

			system.configurationRevision = self.rev or self.dirtyRev or null;
			system.stateVersion = 6;
			nixpkgs.hostPlatform = system;
		};
	in
	{
		darwinConfigurations."${hostname}" = nix-darwin.lib.darwinSystem {
			modules = [ configuration ];
		};
	};
}
