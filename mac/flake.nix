{
	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

		nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
		nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

		agenix = {
			url = "github:ryantm/agenix";
			inputs.nixpkgs.follows = "nixpkgs";
			inputs.darwin.follows = "nix-darwin";
		};

		home-manager = {
			url = "github:nix-community/home-manager/release-25.11";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs = inputs@{ self, nix-darwin, nixpkgs, agenix, home-manager }: let
		hostname = "e";
		username = "veeti";
		homeDir = "/Users/${username}";
		system = "aarch64-darwin";
		configuration = { pkgs, home, ... }: {
			nix.settings.experimental-features = "nix-command flakes";


			networking.hostName = hostname;

			environment.systemPackages = with pkgs; [
				agenix.packages.${system}.agenix
				vim
				git
				zstd
				pv
				eza
				gnupg
				fzf
				home-manager
				ripgrep
				mpv
				opencode
			];
			environment.variables = {
				EDITOR = "nvim";
				VISUAL = "nvim";
			};

			environment.shellAliases = {
				nixswitch = "sudo darwin-rebuild switch --flake .#${hostname}";
				ls = "eza -la";
				f = "cd \"$(find ~/code ~/things -type d -maxdepth 7 -print0 | fzf --read0)\"";
				gs = "git status --short";
				gl = "git log --pretty=format:\"%C(yellow)%h%C(reset) %C(dim)%ad%C(reset) %C(green)%an%C(reset) %s\" --date=human";
				gc = "git commit -S";
				gca = "git commit -S --amend";
				k = "kubectl";
				e = "vim";
			};
			system.primaryUser = username;
			users.users."${username}" = {
				name = username;
				home = homeDir;
			};

			home-manager.useGlobalPkgs = true;
			home-manager.useUserPackages = true;
			home-manager.users."${username}".home = {
				username = username;
				homeDirectory = homeDir;
				stateVersion = "25.05";
			};
			home-manager.sharedModules = [
				({ config, lib, pkgs, ... }: {
					programs.home-manager.enable = true;
					programs.git.enable = true;
					programs.git.settings = {
						user.email = "veeti@veetik.com";
						user.name = "Veeti K";
						user.signingkey = "111E474490913E21";
						commit.gpgsign = true;
						branch.sort = "-committerdate";
						push.autoSetupRemote = true;
					};
					programs.neovim = {
						enable = true;
						defaultEditor = true;
						vimAlias = true;
					};

					xdg.configFile."nvim/init.lua".source = config.lib.file.mkOutOfStoreSymlink ./nvim.conf;
					xdg.configFile."ghostty/config".source = config.lib.file.mkOutOfStoreSymlink ./ghostty.conf;
					xdg.configFile."ghostty/themes/vague".source = config.lib.file.mkOutOfStoreSymlink ./ghostty-vague.conf;
				})
			];
			

			homebrew.enable = true;
			homebrew.casks = [ "keepassxc" "firefox" "ghostty" "helium-browser" "cursor" "syncthing" ];
			homebrew.brews = [ "lazygit" ];
			environment.systemPath = [ "/opt/homebrew/bin" ];

			programs.zsh.enable = true;
			programs.zsh.interactiveShellInit = ''
                          enc() {
                            local file="$1"
                            if [[ -z "$${file}" ]]; then
                                echo "usage: enc <file or dir>"
                                return 1
                            fi
                        
                            local passphrase1 passphrase2
                            echo -n "enter passphrase: "
                            read -s passphrase1
                            echo
                            echo -n "confirm passphrase: "
                            read -s passphrase2
                            echo
                            if [[ "$passphrase1" != "$passphrase2" ]]; then
                                echo "passphrases do not match. aborting."
                                return 1
                            fi
                        
                            tar -cf - "$file" | zstd -T0 | pv -c | gpg --no-symkey-cache --batch --yes --passphrase "$passphrase1" --symmetric --cipher-algo AES256 --compress-level 0 -o "$file.tar.zst.gpg"
                            echo "done"
                        }
                        
                        dec() {
                            local file="$1"
                            if [[ -z "$${file}" ]]; then
                                echo "usage: dec <file.tar.zst.gpg>"
                                return 1
                            fi
                        
                            local tar_name=$(basename "$${file}" .tar.zst.gpg)
                            if [[ -e "$${tar_name}" ]]; then
                                echo "error: '$${tar_name}' already exists. aborting."
                                return 1
                            fi
                        
                            local passphrase
                            echo -n "enter passphrase: "
                            read -s passphrase
                            echo
                        
                            gpg --no-symkey-cache --batch --passphrase "$passphrase" --decrypt "$file" | zstd -d | pv -c | tar -xf -
                            echo "done"
                        }
                        '';


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

				controlcenter.BatteryShowPercentage = false;
				controlcenter.Bluetooth = true;
				dock = {
					orientation = "right";
					autohide = true;
					showhidden = true;
					show-recents = false;
					mru-spaces = false;
					tilesize = 34;
					persistent-apps = [];

					wvous-tl-corner = 1;
					wvous-tr-corner = 1;
					wvous-bl-corner = 1;
					wvous-br-corner = 1;
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
			modules = [
				home-manager.darwinModules.home-manager
				configuration
			];
		};
	};
}
