{ config, pkgs, pkgs-unstable, lib, keys, ... }:

{
  config.nix.settings.experimental-features = "nix-command flakes pipe-operators";

  config.boot.loader.systemd-boot.enable = true;
  config.boot.loader.efi.canTouchEfiVariables = true;

  config.boot.kernelParams = [ "ip=dhcp" ];
  config.boot.initrd = {
    availableKernelModules = [ "e1000e" "igb" ];
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = keys.admins;
        hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        shell = "/bin/cryptsetup-askpass";
      };
    };
  };

  config.networking.hostName = "dev";
  config.time.timeZone = "UTC";
  config.i18n.defaultLocale = "en_US.UTF-8";
  config.i18n.extraLocaleSettings = {
    LC_ADDRESS = "fi_FI.UTF-8";
    LC_IDENTIFICATION = "fi_FI.UTF-8";
    LC_MEASUREMENT = "fi_FI.UTF-8";
    LC_MONETARY = "fi_FI.UTF-8";
    LC_NAME = "fi_FI.UTF-8";
    LC_NUMERIC = "fi_FI.UTF-8";
    LC_PAPER = "fi_FI.UTF-8";
    LC_TELEPHONE = "fi_FI.UTF-8";
    LC_TIME = "fi_FI.UTF-8";
  };
  config.console.keyMap = "fi";
  config.services.xserver.xkb = {
    layout = "fi";
    variant = "";
  };

  config.users.users = {
    root = {
      openssh.authorizedKeys.keys = keys.admins;
      hashedPasswordFile = config.age.secrets.password.path;
    };

    veeti = {
      useDefaultShell = true;
      createHome = true;
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = keys.admins;
      hashedPasswordFile = config.age.secrets.password.path;
    };
  };

  config.security.sudo.wheelNeedsPassword = false;

  config.services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      ChallengeResponseAuthentication = false;
      X11Forwarding = false;
    };
    hostKeys = [{
      type = "ed25519";
      path = "/etc/ssh/ssh_host_ed25519_key";
    }];
  };

  config.boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
  };
  config.networking.firewall.enable = true;
  config.networking.firewall.allowedTCPPorts = [22 80 443 3000 8000];
  config.environment.systemPackages = with pkgs; [
    vim
    git
    btop
    gnupg
    eza
    fzf
    ripgrep
    opencode
    tmux
  ];

  config.programs.mosh = {
    enable = true;
    openFirewall = true;
  };

  config.programs.nixvim = {
    enable = true;

    # ==========================================
    # Options & Globals
    # ==========================================
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

    # Safely append to iskeyword
    extraConfigLua = ''
      vim.opt.iskeyword:append("-")
    '';

    # ==========================================
    # Colorscheme
    # ==========================================
    colorschemes.onedark = {
      enable = true;
      settings.style = "darker";
    };

    # ==========================================
    # Autocmds
    # ==========================================
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

    # ==========================================
    # User Commands
    # ==========================================
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

    # ==========================================
    # Keymaps
    # ==========================================
    keymaps = [
      { mode = [ "n" "v" ]; key = "<Space>"; action = "<Nop>"; options = { silent = true; }; }
      { mode = "n"; key = "<leader>w"; action = "<cmd>w<CR>"; options = { silent = true; noremap = true; }; }
      
      # Overridden by oil.nvim down below, but kept mapping for clarity
      { mode = "n"; key = "<leader>x"; action = "<cmd>Oil<CR>"; options = { silent = true; noremap = true; }; }

      { mode = "n"; key = "k"; action = "v:count == 0 ? 'gk' : 'k'"; options = { expr = true; silent = true; }; }
      { mode = "n"; key = "j"; action = "v:count == 0 ? 'gj' : 'j'"; options = { expr = true; silent = true; }; }
      { mode = "i"; key = "<C-c>"; action = "<Nop>"; }

      # Window Navigation
      { mode = "n"; key = "<C-h>"; action = "<C-w>h"; }
      { mode = "n"; key = "<C-j>"; action = "<C-w>j"; }
      { mode = "n"; key = "<C-k>"; action = "<C-w>k"; }
      { mode = "n"; key = "<C-l>"; action = "<C-w>l"; }

      # Centered Navigation
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

      # Line Moving
      { mode = "n"; key = "<A-j>"; action = "<cmd>m .+1<CR>=="; options = { desc = "Move line down"; }; }
      { mode = "n"; key = "<A-k>"; action = "<cmd>m .-2<CR>=="; options = { desc = "Move line up"; }; }
      { mode = "v"; key = "<A-j>"; action = ":m '>+1<CR>gv=gv"; options = { desc = "Move selection down"; }; }
      { mode = "v"; key = "<A-k>"; action = ":m '<-2<CR>gv=gv"; options = { desc = "Move selection up"; }; }

      # Clipboard & Deletion Operations
      { mode = "x"; key = "<leader>p"; action = ''"_dP''; }
      { mode = [ "n" "v" ]; key = "<leader>d"; action = ''"_d''; }
      { mode = "v"; key = "<leader>y"; action = ''"+y''; options = { silent = true; noremap = true; }; }

      # Highlight / Search
      { mode = "n"; key = "<leader>i"; action = ":let @/='\\<'.expand('<cword>').'\\>'<CR>:set hlsearch<CR>"; options = { silent = true; noremap = true; }; }
      { mode = "n"; key = "xx"; action = "<cmd>nohlsearch<CR>"; options = { silent = true; noremap = true; }; }

      # Fugitive Keymaps
      { mode = "n"; key = "<leader>ås"; action = "<cmd>Git<CR>"; options = { desc = "Git status"; }; }
      { mode = "n"; key = "<leader>åb"; action = "<cmd>Git blame<CR>"; options = { desc = "Git blame"; }; }
      { mode = "n"; key = "<leader>åd"; action = "<cmd>Gdiffsplit<CR>"; options = { desc = "Git diff"; }; }
      { mode = "n"; key = "<leader>ål"; action = "<cmd>Git log<CR>"; options = { desc = "Git log"; }; }
    ];

    # ==========================================
    # Plugins
    # ==========================================
    plugins = {
      nvim-autopairs.enable = true;
      ts-autotag.enable = true;
      sleuth.enable = true;
      fugitive.enable = true;

      # Telescope
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

      # Treesitter
      treesitter = {
        enable = true;
        settings = {
          highlight = { enable = true; };
          indent = { enable = true; };
          ensure_installed = [ "go" "lua" "rust" "tsx" "javascript" "typescript" "bash" "zig" ];
          auto_install = true;
        };
      };

      # Oil
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

      # Conform (Formatting)
      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
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

      # Blink CMP
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
                # Use __raw to safely pass Lua's mixed table structure
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

      # LSP Configuration
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
            # Allows you to specify root markers dynamically
            extraOptions = {
              root_markers = [ "Config.toml" ".git" ];
            };
          };
          ts_ls = {
            enable = true;
            
            # Optional: Disable the LSP's built-in formatting so it doesn't 
            # conflict with Prettier (which you configured in conform.nvim)
            onAttach.function = ''
              client.server_capabilities.documentFormattingProvider = false
              client.server_capabilities.documentRangeFormattingProvider = false
            '';
          };
        };
      };
    };
  };

  config.virtualisation.containers.enable = true;
  config.virtualisation = {
    docker.enable = lib.mkForce false;
    oci-containers.backend = "podman";
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = false;
    };
  };

  config.system.stateVersion = "25.11";
}

