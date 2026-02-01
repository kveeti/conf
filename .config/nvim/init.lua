local vim = vim
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
vim.keymap.set("n", "<leader>x", [[:Ex<CR>]], { noremap = true, silent = true })
vim.keymap.set('n', '<leader>m', ':e $MYVIMRC<CR>', { silent = true })

vim.keymap.set('n', '<leader>rr', ':source $MYVIMRC<CR>')
vim.keymap.set({ "n", "v", "x" }, "<leader>t", vim.lsp.buf.format, { desc = "Format current buffer" })

vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-d>", "<C-d>zz")

vim.keymap.set("n", "{", "{zz")
vim.keymap.set("n", "}", "}zz")
vim.keymap.set("n", "N", "Nzz")
vim.keymap.set("n", "n", "nzz")
vim.keymap.set("n", "G", "Gzz")
vim.keymap.set("n", "gg", "ggzz")
vim.keymap.set("n", "<C-i>", "<C-i>zz")
vim.keymap.set("n", "<C-o>", "<C-o>zz")
vim.keymap.set("n", "%", "%zz")
vim.keymap.set("n", "*", "*zz")
vim.keymap.set("n", "#", "#zz")

vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down" })
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up" })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

vim.keymap.set("x", "<leader>p", '"_dP')
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')
vim.keymap.set('v', '<leader>y', '"+y', { noremap = true, silent = true })

vim.keymap.set(
	"n",
	"<leader>i", ":let @/='\\<'.expand('<cword>').'\\>'<CR>:set hlsearch<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set("n", "xx", ":nohlsearch<CR>", { noremap = true, silent = true })

vim.keymap.set("i", "<C-c>", "<ESC>")
-- keybinds

-- options
vim.opt.mouse = "a"
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"
vim.opt.hlsearch = false
vim.opt.termguicolors = true
vim.wo.number = true
vim.opt.relativenumber = true
vim.wo.signcolumn = "no"
vim.opt.wrap = false
vim.opt.laststatus = 0
vim.opt.scrolloff = 8

--vim.opt.completeopt = { "menuone", "noinsert", "noselect", "fuzzy", "popup" }

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

vim.g.omni_sql_no_default_maps = 1
vim.g.zig_fmt_autosave = 0

vim.opt.backspace = "indent,eol,start"
vim.opt.autochdir = false
vim.opt.iskeyword:append("-")

vim.opt.redrawtime = 10000
vim.opt.maxmempattern = 20000

vim.opt.list = true
vim.opt.listchars = {
	tab = '⇥ ',
	trail = '·',
	space = '·',
}

vim.diagnostic.config({ virtual_text = true, virtual_lines = false })

-- Show current filename as terminal title
vim.opt.title = true
vim.opt.titlestring = '%f'
-- options

-- THEME --
-- THEME --
-- THEME --

vim.cmd("hi clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end

vim.g.colors_name = "minimal"

vim.api.nvim_set_hl(0, "Comment", { fg = "#6a9955", italic = true })
vim.api.nvim_set_hl(0, "String", { fg = "#ce9178" })
vim.api.nvim_set_hl(0, "Character", { link = "String" })

-- Clear everything else to default foreground
local groups_to_clear = {
	"Constant", "Number", "Boolean", "Float",
	"Identifier", "Function",
	"Statement", "Conditional", "Repeat", "Label", "Operator", "Keyword", "Exception",
	"PreProc", "Include", "Define", "Macro", "PreCondit",
	"Type", "StorageClass", "Structure", "Typedef",
	"Special", "SpecialChar", "Tag", "Delimiter", "SpecialComment", "Debug",
}

for _, group in ipairs(groups_to_clear) do
	vim.api.nvim_set_hl(0, group, {})
end

vim.api.nvim_set_hl(0, "CursorLine", { bg = "#2a2a2a" })
vim.api.nvim_set_hl(0, "MiniPickMatchCurrent", { link = "CursorLine" })

vim.api.nvim_set_hl(0, "DiagnosticUnderlineInfo", { fg = "#55aaff", bg = "none" })
vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = "#55aaff", bg = "none" })
vim.api.nvim_set_hl(0, "DiagnosticHint", { fg = "#55aaff", bg = "none" })
vim.api.nvim_set_hl(0, "DiagnosticUnderlineHint", { fg = "#55aaff", bg = "none" })
vim.api.nvim_set_hl(0, "DiagnosticUnnecessary", { fg = "#777777", bg = "none" })

local warn_bg = "none"
local warn_fg = "#d4c96a"
local warn_diag_fg = "#d4c96a"
vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = warn_diag_fg, bg = "none" })
vim.api.nvim_set_hl(0, "DiagnosticUnderlineWarn", { bg = warn_bg, fg = warn_fg, underline = false })

local error_bg = "#502020"
local error_fg = "none"
local error_diag_fg = "#f08080"
vim.api.nvim_set_hl(0, "Error", { fg = error_diag_fg, bg = "none" })
vim.api.nvim_set_hl(0, "ErrorMsg", { fg = error_diag_fg, bg = "none" })
vim.api.nvim_set_hl(0, "DiagnosticError", { fg = error_diag_fg, bg = "none", underline = false })
vim.api.nvim_set_hl(0, "DiagnosticUnderlineError", { bg = error_bg, fg = error_fg, underline = false })

vim.opt.winborder = "single"
vim.cmd(":hi statusline guibg=NONE")

-- no bg
vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
vim.api.nvim_set_hl(0, "FloatBorder", { bg = "none" })
vim.api.nvim_set_hl(0, "Pmenu", { bg = "none" })
vim.api.nvim_set_hl(0, "NonText", { bg = "none" })

-- dim vim list / whitespace chars
-- MUST be below theme stuff
vim.api.nvim_set_hl(0, "Whitespace", { fg = "#666666", bg = "none" })

-- THEME --
-- THEME --
-- THEME --

-- plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system {
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	}
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	{ "windwp/nvim-autopairs" },
	{ "windwp/nvim-ts-autotag" },
	{ "tpope/vim-sleuth" },
	{
		"tpope/vim-fugitive",
		cmd = { "Git", "G", "Gdiffsplit", "Gread", "Gwrite", "Ggrep", "GMove", "GDelete", "GBrowse" },
		keys = {
			{ "<leader>gs", "<cmd>Git<cr>",        desc = "Git status" },
			{ "<leader>gb", "<cmd>Git blame<cr>",  desc = "Git blame" },
			{ "<leader>gd", "<cmd>Gdiffsplit<cr>", desc = "Git diff" },
			{ "<leader>gl", "<cmd>Git log<cr>",    desc = "Git log" },
		},
	},
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
	-- {
	-- 	"nvim-mini/mini.pick",
	-- 	version = "*",
	-- 	config = function()
	-- 		MiniPick = require("mini.pick")
	-- 		vim.keymap.set("n", "<leader>f", MiniPick.builtin.files, { noremap = true, silent = true })
	-- 	end
	-- },
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			"mason-org/mason-lspconfig.nvim",
			{ "j-hui/fidget.nvim",    opts = {} },
			"saghen/blink.cmp",
		},
		config = function()
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(event)
					local builtin = require("telescope.builtin")
					local rest = { buffer = event.buf }

					vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, rest)
					vim.keymap.set({ "n", "x" }, "<leader>a", vim.lsp.buf.code_action, rest)
					vim.keymap.set("n", "<leader>a", vim.lsp.buf.code_action, rest)
					vim.keymap.set("n", "gr", builtin.lsp_references, rest)
					vim.keymap.set("n", "gi", builtin.lsp_implementations, rest)
					vim.keymap.set("n", "gd", builtin.lsp_definitions, rest)
				end,
			})

			local servers = {
				ts_ls = {},
				rust_analyzer = {},
				lua_ls = {},
			}
			local ensure_installed = vim.tbl_keys(servers or {})

			local capabilities = require("blink.cmp").get_lsp_capabilities()

			require("mason-lspconfig").setup({
				ensure_installed = ensure_installed,
				automatic_installation = false,
				handlers = {
					function(server_name)
						local server = servers[server_name] or {}
						server.capabilities = vim.tbl_deep_extend("force", {}, capabilities,
							server.capabilities or {})
						require("lspconfig")[server_name].setup(server)
					end,
				},
			})
		end
	},
	{
		"saghen/blink.cmp",
		dependencies = {
			"folke/lazydev.nvim",
		},
		opts = {
			keymap = {
				preset = "enter",
			},
			cmdline = { enabled = false },
			signature = { enabled = false },
			completion = {
				ghost_text = { enabled = false },
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 100
				},
				menu = {
					auto_show = true,
					draw = {
						columns = {
							{ "label", "label_description", gap = 1 },
						},
					}
				}
			},
			sources = {
				default = { "lsp", "path", "snippets", "buffer" },
			},
			fuzzy = { implementation = "lua" },
		},
	},
	-- {
	-- 	"nvim-treesitter/nvim-treesitter",
	-- 	build = ":TSUpdate",
	-- 	main = "nvim-treesitter.configs",
	-- 	opts = {
	-- 		ensure_installed = {
	-- 			"go",
	-- 			"lua",
	-- 			"rust",
	-- 			"tsx",
	-- 			"javascript",
	-- 			"typescript",
	-- 			"bash",
	-- 		},
	-- 		auto_install = true,
	-- 		highlight = { enable = true },
	-- 		indent = { enable = true },
	-- 	}
	-- },
}, {
	ui = {
		border = "single",
	},
})
-- plugins

local augroup = vim.api.nvim_create_augroup("UserConfig", {})

vim.api.nvim_create_autocmd("VimResized", {
	group = augroup,
	callback = function()
		vim.cmd("tabdo wincmd =")
	end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
	group = augroup,
	callback = function()
		vim.highlight.on_yank({ timeout = 150 })
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	group = augroup,
	callback = function()
		local dir = vim.fn.expand("<afile>:p:h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end
	end,
})
