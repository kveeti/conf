{ pkgs, ... }:
{
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

                if vim.fn.has('mac') == 0 then
                  vim.g.clipboard = {
                    name = 'OSC 52',
                    copy = {
                      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
                      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
                    },
                    paste = {
                      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
                      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
                    },
                  }
                end

                -- dark-notify follows the macOS system appearance; it has no effect
                -- (and the helper binary is absent) on the headless Linux dev guest.
                if vim.fn.has('mac') == 1 then
                  require('dark_notify').run({
                    onchange = function(mode)
                      if mode == "light" then
                        require('onedark').setup({ style = 'light' })
                      else
                        require('onedark').setup({ style = 'dark' })
                      end
                      require('onedark').load()
                    end
                  })
                end
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
                web-devicons.enable = true;

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
}
