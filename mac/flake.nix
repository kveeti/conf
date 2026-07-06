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

    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, agenix, home-manager, nixvim }:
    let
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
          mosh
        ];

        environment.shellAliases = {
          nixswitch = "sudo darwin-rebuild switch --flake .#${hostname}";
          ls = "eza -la";
          f = "cd \"$(find ~/code ~/things -type d -maxdepth 7 -print0 | fzf --read0)\"";
          gs = "git status --short";
          gl = "git log --pretty=format:\"%C(yellow)%h%C(reset) %C(dim)%ad%C(reset) %C(green)%an%C(reset) %s\" --date=human";
          gc = "git commit -S";
          gca = "git commit -S --amend";
          k = "kubectl";
          e = "nvim";
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
          nixvim.homeManagerModules.nixvim

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

            xdg.configFile."ghostty/config".source = config.lib.file.mkOutOfStoreSymlink ./ghostty.conf;
            xdg.configFile."ghostty/themes/vague".source = config.lib.file.mkOutOfStoreSymlink ./ghostty-vague.conf;
            xdg.configFile."tmux/tmux.conf".source = config.lib.file.mkOutOfStoreSymlink ./tmux.conf;

            programs.nixvim = {
              enable = true;

              extraPlugins = [
                (pkgs.vimUtils.buildVimPlugin {
                  name = "dark-notify";
                  src = pkgs.fetchFromGitHub {
                    owner = "cormacrelf";
                    repo = "dark-notify";
                    rev = "v0.1.3";
                    hash = "sha256-TZuuXeolzx3kby2qO9e/FTf+1g39gKk9NzXQxmjN/UA="; 
                  };
                })
              ];

              globals = {
                mapleader = " ";
                maplocalleader = " ";
                omni_sql_no_default_maps = 1;
                zig_fmt_autosave = 0;
                loaded_netrw = 1;
                loaded_netrwPlugin = 1;
              };

              opts = {
                list = true;
                listchars = {
                  tab = "⇥ ";
                  trail = "·";
                  space = "·";
                };
                title = true;
                titlestring = "%f";
                mouse = "a";
                guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20";
                hlsearch = false;
                termguicolors = true;
                number = true;
                relativenumber = true;
                signcolumn = "no";
                wrap = false;
                laststatus = 0;
                scrolloff = 8;
                ignorecase = true;
                smartcase = true;
                tabstop = 4;
                softtabstop = 4;
                shiftwidth = 4;
                expandtab = false;
                backspace = "indent,eol,start";
                autochdir = false;
                completeopt = "menuone,noselect,fuzzy,nosort";
              };

              extraConfigLua = ''
                vim.opt.iskeyword:append("-")
                require('dark_notify').run({
                  onchange = function(mode)
                    if mode == "light" then
                      -- Set to your preferred light style
                      require('onedark').setup({ style = 'light' })
                    else
                      -- Set to your preferred dark style (e.g., 'dark', 'darker', 'cool', 'deep')
                      require('onedark').setup({ style = 'dark' }) 
                    end
                    -- Force Onedark to reload with the new settings
                    require('onedark').load()
                  end
                })
              '';

              colorschemes.onedark = {
                enable = true;
                settings.style = "dark";
              };

              autoGroups = {
                UserConfig = { };
              };

              autoCmd = [
                {
                  event = "VimResized";
                  group = "UserConfig";
                  command = "tabdo wincmd =";
                }
                {
                  event = "TextYankPost";
                  group = "UserConfig";
                  callback = {
                    __raw = "function() vim.highlight.on_yank({ timeout = 150 }) end";
                  };
                }
              ];

              userCommands = {
                FormatDisable = {
                  command = "let g:disable_autoformat = v:true";
                  desc = "Disable autoformat-on-save";
                };
                FormatEnable = {
                  command = "let g:disable_autoformat = v:false";
                  desc = "Re-enable autoformat-on-save";
                };
              };

              keymaps = [
                { mode = [ "n" "v" ]; key = "<Space>"; action = "<Nop>"; options = { silent = true; }; }
                { mode = "n"; key = "<leader>w"; action = "<cmd>w<CR>"; options = { silent = true; noremap = true; }; }
                
                { mode = "n"; key = "<leader>x"; action = "<cmd>Oil<CR>"; options = { silent = true; noremap = true; }; }

                { mode = "n"; key = "k"; action = "v:count == 0 ? 'gk' : 'k'"; options = { expr = true; silent = true; }; }
                { mode = "n"; key = "j"; action = "v:count == 0 ? 'gj' : 'j'"; options = { expr = true; silent = true; }; }
                { mode = "i"; key = "<C-c>"; action = "<Nop>"; }

                { mode = "n"; key = "<C-h>"; action = "<C-w>h"; }
                { mode = "n"; key = "<C-j>"; action = "<C-w>j"; }
                { mode = "n"; key = "<C-k>"; action = "<C-w>k"; }
                { mode = "n"; key = "<C-l>"; action = "<C-w>l"; }

                { mode = "n"; key = "<C-u>"; action = "<C-u>zz"; }
                { mode = "n"; key = "<C-d>"; action = "<C-d>zz"; }
                { mode = "n"; key = "{"; action = "{zz"; }
                { mode = "n"; key = "}"; action = "}zz"; }
                { mode = "n"; key = "N"; action = "Nzz"; }
                { mode = "n"; key = "n"; action = "nzz"; }
                { mode = "n"; key = "G"; action = "Gzz"; }
                { mode = "n"; key = "gg"; action = "ggzz"; }
                { mode = "n"; key = "<C-i>"; action = "<C-i>zz"; }
                { mode = "n"; key = "<C-o>"; action = "<C-o>zz"; }
                { mode = "n"; key = "%"; action = "%zz"; }
                { mode = "n"; key = "*"; action = "*zz"; }
                { mode = "n"; key = "#"; action = "#zz"; }

                { mode = "n"; key = "<A-j>"; action = "<cmd>m .+1<CR>=="; options = { desc = "Move line down"; }; }
                { mode = "n"; key = "<A-k>"; action = "<cmd>m .-2<CR>=="; options = { desc = "Move line up"; }; }
                { mode = "v"; key = "<A-j>"; action = ":m '>+1<CR>gv=gv"; options = { desc = "Move selection down"; }; }
                { mode = "v"; key = "<A-k>"; action = ":m '<-2<CR>gv=gv"; options = { desc = "Move selection up"; }; }

                { mode = "x"; key = "<leader>p"; action = ''"_dP''; }
                { mode = [ "n" "v" ]; key = "<leader>d"; action = ''"_d''; }
                { mode = "v"; key = "<leader>y"; action = ''"+y''; options = { silent = true; noremap = true; }; }

                { mode = "n"; key = "<leader>i"; action = ":let @/='\\<'.expand('<cword>').'\\>'<CR>:set hlsearch<CR>"; options = { silent = true; noremap = true; }; }
                { mode = "n"; key = "xx"; action = "<cmd>nohlsearch<CR>"; options = { silent = true; noremap = true; }; }

                { mode = "n"; key = "<leader>ås"; action = "<cmd>Git<CR>"; options = { desc = "Git status"; }; }
                { mode = "n"; key = "<leader>åb"; action = "<cmd>Git blame<CR>"; options = { desc = "Git blame"; }; }
                { mode = "n"; key = "<leader>åd"; action = "<cmd>Gdiffsplit<CR>"; options = { desc = "Git diff"; }; }
                { mode = "n"; key = "<leader>ål"; action = "<cmd>Git log<CR>"; options = { desc = "Git log"; }; }
              ];

              plugins = {
                nvim-autopairs.enable = true;
                ts-autotag.enable = true;
                sleuth.enable = true;
                fugitive.enable = true;

                telescope = {
                  enable = true;
                  settings = {
                    defaults = {
                      mappings = {
                        i = {
                          "<C-u>" = false;
                          "<C-d>" = false;
                        };
                      };
                      path_display = [ "filename_first" ];
                    };
                  };
                  keymaps = {
                    "<leader>b" = "current_buffer_fuzzy_find";
                    "<leader>f" = "find_files";
                    "<leader>g" = "live_grep";
                  };
                };

                treesitter = {
                  enable = true;
                  settings = {
                    highlight = { enable = true; };
                    indent = { enable = true; };
                    ensure_installed = [ "go" "lua" "rust" "tsx" "javascript" "typescript" "bash" "zig" ];
                    auto_install = true;
                  };
                };

                oil = {
                  enable = true;
                  settings = {
                    delete_to_trash = true;
                    watch_for_changes = true;
                    skip_confirm_for_simple_edits = true;
                    view_options = { show_hidden = true; };
                    lsp_file_methods = {
                      timeout_ms = 1200;
                      autosave_changes = true;
                    };
                    keymaps = {
                      "<C-h>" = false;
                      "<C-j>" = false;
                      "<C-k>" = false;
                      "<C-l>" = false;
                    };
                  };
                };

                conform-nvim = {
                  enable = true;
                  settings = {
                    formatters_by_ft = {
                      go = [ "goimports" "gofumpt" ];
                      lua = [ "stylua" ];
                      javascript = [ "prettier" ];
                      typescript = [ "prettier" ];
                      javascriptreact = [ "prettier" ];
                      typescriptreact = [ "prettier" ];
                      json = [ "prettier" ];
                      jsonc = [ "prettier" ];
                      html = [ "prettier" ];
                      css = [ "prettier" ];
                    };
                    format_after_save = {
                      __raw = ''
                        function(bufnr)
                          if vim.g.disable_autoformat then return end
                          return { async = true, timeout_ms = 1000, lsp_format = "fallback" }
                        end
                      '';
                    };
                  };
                };

                blink-cmp = {
                  enable = true;
                  settings = {
                    keymap = {
                      preset = "enter";
                    };
                    cmdline = { enabled = false; };
                    signature = { enabled = false; };
                    completion = {
                      ghost_text = { enabled = false; };
                      documentation = {
                        auto_show = true;
                        auto_show_delay_ms = 100;
                      };
                      menu = {
                        auto_show = true;
                        draw = {
                          columns = {
                            __raw = ''{ { "label", "label_description", gap = 1 } }'';
                          };
                        };
                      };
                    };
                    sources = {
                      default = [ "lsp" "path" "snippets" "buffer" ];
                    };
                    fuzzy = { implementation = "lua"; };
                  };
                };

                lsp = {
                  enable = true;
                  keymaps = {
                    diagnostic = {
                      "Å" = { action = "goto_prev"; desc = "Previous Diagnostic"; };
                      "å" = { action = "goto_next"; desc = "Next Diagnostic"; };
                      "<leader>e" = { action = "open_float"; desc = "Open Diagnostics"; };
                    };
                    lspBuf = {
                      "gd" = { action = "definition"; desc = "[G]oto [D]efinition"; };
                      "gr" = { action = "references"; desc = "[G]oto [R]eferences"; };
                      "gi" = { action = "implementation"; desc = "[G]oto [I]mplementation"; };
                      "gD" = { action = "declaration"; desc = "[G]oto [D]eclaration"; };
                      "<leader>r" = { action = "rename"; desc = "[R]e[n]ame"; };
                      "<leader>a" = { action = "code_action"; desc = "[C]ode [A]ction"; };
                      "K" = { action = "hover"; desc = "Hover Documentation"; };
                    };
                  };
                  servers = {
                    gopls = {
                      enable = true;
                      settings.gopls = {
                        gofumpt = true;
                        usePlaceholders = true;
                        analyses = {
                          unusedparams = true;
                          nilness = true;
                          unusedwrite = true;
                        };
                        staticcheck = true;
                        hints = {
                          assignVariableTypes = true;
                          compositeLiteralFields = true;
                          constantValues = true;
                          functionTypeParameters = true;
                          parameterNames = true;
                          rangeVariableTypes = true;
                        };
                      };
                    };
                    rust_analyzer = {
                      enable = true;
                      installCargo = true;
                      installRustc = true;
                      settings = {
                        files.watcher = "server";
                        cargo.targetDir = true;
                        check.command = "clippy";
                        inlayHints = {
                          bindingModeHints.enable = true;
                          closureCaptureHints.enable = true;
                          closureReturnTypeHints.enable = "always";
                          maxLength = 100;
                        };
                        rustc.source = "discover";
                      };
                      extraOptions = {
                        root_markers = [ "Config.toml" ".git" ];
                      };
                    };
                    ts_ls = {
                      enable = true;
                      
                      onAttach.function = ''
                        client.server_capabilities.documentFormattingProvider = false
                        client.server_capabilities.documentRangeFormattingProvider = false
                      '';
                    };
                    cssls.enable = true;
                    emmet_ls = {
                      enable = true;
                      filetypes = [ "html" "css" "scss" "sass" "less" "javascriptreact" "typescriptreact" ];
                    };
                  };
                };
              };
            };
          })
        ];

        programs.zsh.enable = true;
        programs.zsh.interactiveShellInit = ''
          enc() {
            local file="$1"
            if [[ -z "$file" ]]; then
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
            if [[ -z "$file" ]]; then
              echo "usage: dec <file.tar.zst.gpg>"
              return 1
            fi

            local tar_name=$(basename "$file" .tar.zst.gpg)
            if [[ -e "$tar_name" ]]; then
              echo "error: '$tar_name' already exists. aborting."
              return 1
            fi

            local passphrase
            echo -n "enter passphrase: "
            read -s passphrase
            echo

            gpg --no-symkey-cache --batch --passphrase "$passphrase" --decrypt "$file" | zstd -d | pv -c | tar -xf -
            echo "done"
          }

          function t() {
            if [[ $# -eq 1 ]]; then
              selected="$1"
            else
              selected=$(find ~/code -maxdepth 7 \( -name "node_modules" -o -name ".git" -o -name "dist" -o -name "build" -o -name "target" \) -prune -o -type d -print0 | fzf --read0)
            fi

            if [[ -z $selected ]]; then
              exit 0
            fi

            selected_name=$(basename "$selected" | tr . _)
            tmux_running=$(pgrep tmux)

            if [[ -z $TMUX ]] && [[ -z "$tmux_running" ]]; then
              tmux new-session -s "$selected_name" -c "$selected"
              exit 0
            fi

            if ! tmux has-session -t="$selected_name" 2> /dev/null; then
              tmux new-session -ds "$selected_name" -c "$selected"
            fi

            if [[ -z $TMUX ]]; then
              tmux attach -t "$selected_name"
            else
              tmux switch-client -t "$selected_name"
            fi
          }
        '';

        homebrew.enable = true;
        homebrew.taps = [ "cormacrelf/tap" ];
        homebrew.casks = [ "keepassxc" "alacritty" "ghostty" "firefox" "syncthing-app" "codex" ];
        homebrew.brews = [ "lazygit" "colima" "tmux" "dark-notify" ];
        environment.systemPath = [ "/opt/homebrew/bin" ];

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
          controlcenter.Sound = true;
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

          finder.AppleShowAllFiles = true;
          finder.NewWindowTarget = "Home";
          finder.ShowPathbar = true;
          finder.ShowStatusBar = true;

          screencapture.target = "clipboard";

          screensaver.askForPasswordDelay = 0;
          screensaver.askForPassword = true;
        };

        system.startup.chime = false;
        system.defaults.trackpad = {
          Clicking = true;
          Dragging = false;
          ActuationStrength = 0;
          FirstClickThreshold = 0;
          ForceSuppressed = true;
          TrackpadRightClick = true;
          TrackpadThreeFingerDrag = true;
          TrackpadThreeFingerTapGesture = 0;
        };
        system.defaults.NSGlobalDomain.NSScrollAnimationEnabled = true;
        system.defaults.NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
        system.defaults.NSGlobalDomain."com.apple.trackpad.scaling" = 3.0;
        system.defaults.".GlobalPreferences"."com.apple.mouse.scaling" = -1.0;
        system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;
        system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
        system.defaults.NSGlobalDomain.KeyRepeat = 1;
        system.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
        system.keyboard = {
          enableKeyMapping = true;
          remapCapsLockToControl = true;
          nonUS.remapTilde = true;
        };

        system.defaults.NSGlobalDomain."com.apple.sound.beep.feedback" = 1;

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
