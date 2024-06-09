{
	inputs,
	outputs,
	lib,
	config,
	pkgs,
	...
}: {
	nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
		"discord"
	];

	home = {
		username = "veeti";
		homeDirectory = "/home/veeti";

		packages = with pkgs; [
			alacritty
			keepassxc
			wireguard-tools
			discord
			btop
			gnumake
			xclip
		];
	};

	programs = {
		home-manager.enable = true;

		firefox = {
			enable = true;
			profiles = {
				default = {
					id = 0;
					name = "default";
					isDefault = true;
					settings = {
						"browser.search.defaultenginename" = "DuckDuckGo";
						"browser.search.order.1" = "DuckDuckGo";
						"browser.download.useDownloadsDir" = false;
					};
					search = {
						force = true;
						default = "DuckDuckGo";
						order = [ "DuckDuckGo" ];
					};
				};
			};
		};

		tmux = {
			enable = true;
			extraConfig = ''
				set-option -g prefix C-e

				set -g default-terminal "screen-256color"
				set -as terminal-features ",xterm-256color:RGB"

				set -g base-index 1
				setw -g pane-base-index 1
				set-option -g renumber-windows on

				set -g status-style bg=terminal,fg=terminal

				set -g status-position bottom

				set -g window-status-current-style fg=terminal,bold

				set -g status-right "%a %d. %b  %H:%M"

				set-window-option -g mode-keys vi
				bind-key -T copy-mode-vi v send -X begin-selection
				bind-key -T copy-mode-vi V send -X select-line
				bind-key -T copy-mode-vi y send -X copy-pipe-and-cancel 'xclip -in -selection clipboard'

				setw -g mouse on
			'';
		};

		neovim = {
			enable = true;
			extraPackages = [
				pkgs.go
				pkgs.nodejs_22
				pkgs.gcc
				pkgs.vimPlugins.nvim-treesitter.withAllGrammars
			];
		};

		zsh = {
			enable = true;

			autosuggestion.enable = true;
			syntaxHighlighting.enable = true;
			enableCompletion = true;

			oh-my-zsh = {
				enable = true;
				plugins = [
					"git"
					"z"
					"history"
					"node"
					"npm"
					"rust"
				];
				theme = "robbyrussell";
			};
		};
	};

	home.file."./.config/nvim" = {
		source = config.lib.file.mkOutOfStoreSymlink "/home/veeti/code/conf/nvim";
		recursive = true;
	};

	systemd.user.startServices = "sd-switch";

	home.stateVersion = "24.05";
}
