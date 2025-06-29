-- keybinds
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

vim.keymap.set('n', 'Å', vim.diagnostic.goto_prev)
vim.keymap.set('n', 'å', vim.diagnostic.goto_next)
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float)

vim.keymap.set("n", "<leader>w", [[:w<CR>]], { noremap = true, silent = true })

vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

vim.keymap.set(
	"n",
	"<leader>i", ":let @/='\\<'.expand('<cword>').'\\>'<CR>:set hlsearch<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set("n", "xx", ":nohlsearch<CR>", { noremap = true, silent = true })

vim.keymap.set("i", "<C-c>", "<ESC>")

vim.keymap.set("n", "<leader><leader>", "<c-^>", { noremap = true, silent = true })
-- keybinds

-- options
vim.opt.mouse = 'a'
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"
vim.opt.hlsearch = false
vim.opt.termguicolors = true
vim.wo.number = true
vim.opt.relativenumber = true
vim.wo.signcolumn = 'no'
vim.opt.wrap = false
vim.opt.laststatus = 0
vim.opt.scrolloff = 8

vim.opt.completeopt = 'menuone,noselect'

vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = false

vim.opt.updatetime = 50
vim.opt.timeoutlen = 300
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.omni_sql_no_default_maps = 1
vim.g.zig_fmt_autosave = 0

vim.opt.list = true
vim.opt.listchars = {
	tab = '⇥ ',
	trail = '·',
	space = '·',
}
-- options

-- plugins
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system {
		'git',
		'clone',
		'--filter=blob:none',
		'https://github.com/folke/lazy.nvim.git',
		'--branch=stable',
		lazypath,
	}
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
	{
		"vague2k/vague.nvim",
		config = function()
			require("vague").setup({})
			vim.cmd("colorscheme vague")
			vim.cmd(":hi statusline guibg=NONE")
		end
	},
	{ 'windwp/nvim-autopairs' },
	{ 'windwp/nvim-ts-autotag' },
	{ 'tpope/vim-sleuth' },
	{
		"stevearc/conform.nvim",
		config = function()
			local conform = require("conform")
			conform.setup({
				formatters_by_ft = {
					lua = { "stylua" },
					javascript = { "prettier" },
					typescript = { "prettier" },
					javascriptreact = { "prettier" },
					typescriptreact = { "prettier" },
					json = { "prettier" },
					jsonc = { "prettier" },
					html = { "prettier" },
					css = { "prettier" },
				},
				format_after_save = function(bufnr)
					if vim.g.disable_autoformat then return end
					return { async = true, timeout_ms = 1000, lsp_format = "fallback" }
				end,
			})

			vim.api.nvim_create_user_command("FormatDisable", function(args)
				vim.g.disable_autoformat = true
			end, { desc = "Disable autoformat-on-save" })
			vim.api.nvim_create_user_command("FormatEnable", function()
				vim.g.disable_autoformat = false
			end, { desc = "Re-enable autoformat-on-save" })
		end
	},
	{
		'nvim-telescope/telescope.nvim',
		branch = '0.1.x',
		dependencies = { 'nvim-lua/plenary.nvim' },
		config = function()
			require('telescope').setup {
				defaults = {
					mappings = {
						i = {
							['<C-u>'] = false,
							['<C-d>'] = false,
						},
					},
					path_display = {
						"filename_first",
					}
				},
			}

			local builtin = require('telescope.builtin')

			vim.keymap.set('n', '<leader>b', builtin.current_buffer_fuzzy_find)
			vim.keymap.set('n', '<leader>f', builtin.find_files)
			vim.keymap.set('n', '<leader>g', builtin.live_grep)
		end
	},
	{
		'neovim/nvim-lspconfig',
		dependencies = {
			{ 'mason-org/mason.nvim', opts = {} },
			'mason-org/mason-lspconfig.nvim',
			{ 'j-hui/fidget.nvim',    opts = {} },
			'saghen/blink.cmp',
		},
		config = function()
			vim.api.nvim_create_autocmd('LspAttach', {
				callback = function(event)
					local builtin = require('telescope.builtin')
					local rest = { buffer = event.buf }

					vim.keymap.set("n", '<leader>r', vim.lsp.buf.rename, rest)
					vim.keymap.set({ "n", "x" }, '<leader>a', vim.lsp.buf.code_action, rest)
					vim.keymap.set("n", '<leader>a', vim.lsp.buf.code_action, rest)
					vim.keymap.set("n", 'gr', builtin.lsp_references, rest)
					vim.keymap.set("n", 'gi', builtin.lsp_implementations, rest)
					vim.keymap.set("n", 'gd', builtin.lsp_definitions, rest)
				end,
			})

			local servers = {
				ts_ls = {},
				rust_analyzer = {},
				lua_ls = {},
			}
			local ensure_installed = vim.tbl_keys(servers or {})

			local capabilities = require('blink.cmp').get_lsp_capabilities()

			require('mason-lspconfig').setup({
				ensure_installed = ensure_installed,
				automatic_installation = false,
				handlers = {
					function(server_name)
						local server = servers[server_name] or {}
						server.capabilities = vim.tbl_deep_extend('force', {}, capabilities,
							server.capabilities or {})
						require('lspconfig')[server_name].setup(server)
					end,
				},
			})
		end
	},
	{
		'saghen/blink.cmp',
		dependencies = {
			{
				'L3MON4D3/LuaSnip',
				version = '2.*',
				build = (function()
					if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
						return
					end
					return 'make install_jsregexp'
				end)(),
				opts = {},
			},
			'folke/lazydev.nvim',
		},
		opts = {
			keymap = {
				preset = 'enter',
			},
			appearance = {
				nerd_font_variant = 'mono',
			},
			completion = {
				documentation = { auto_show = false, auto_show_delay_ms = 500 },
			},
			sources = {
				default = { 'lsp', 'path', 'snippets', 'lazydev' },
				providers = {
					lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
				},
			},
			snippets = { preset = 'luasnip' },
			fuzzy = { implementation = 'lua' },
			signature = { enabled = true },
		},
	},
	{
		'nvim-treesitter/nvim-treesitter',
		build = ':TSUpdate',
		main = 'nvim-treesitter.configs',
		opts = {
			ensure_installed = {
				'go',
				'lua',
				'rust',
				'tsx',
				'javascript',
				'typescript',
				'bash',
			},
			auto_install = true,
			highlight = { enable = true },
			indent = { enable = true },
		}
	},
	{
		'stevearc/oil.nvim',
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local oil = require("oil")

			oil.setup({
				delete_to_trash = true,
				watch_for_changes = true,
				skip_confirm_for_simple_edits = true,
				view_options = { show_hidden = true },
				lsp_file_methods = {
					timeout_ms = 1200,
					autosave_changes = true,
				},
				keymaps = {
					["<C-h>"] = false,
					["<C-j>"] = false,
					["<C-k>"] = false,
					["<C-l>"] = false,
				}
			})

			vim.keymap.set("n", "<leader>x", oil.open)
		end
	}
})
-- plugins
