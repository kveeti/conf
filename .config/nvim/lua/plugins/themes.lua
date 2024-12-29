return {
	-- {
	-- 	"datsfilipe/vesper.nvim",
	-- 	priority = 1000,
	-- 	config = function()
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme vesper")
	-- 	end
	-- }
	{
		'catppuccin/nvim',
		name = "catppuccin",
		priority = 1000,
		config = function()
			require('catppuccin').setup({
				flavour = 'frappe'
			})

			vim.o.background = "dark"
			vim.cmd("colorscheme catppuccin")
		end,
	},
	-- {
	-- 	'Lokaltog/monotone.nvim',
	-- 	dependencies = {
	-- 		'rktjmp/lush.nvim',
	-- 	},
	-- 	priority = 1000,
	-- 	config = function()
	-- 		vim.g.monotone_h = 0
	-- 		vim.g.monotone_s = 0
	-- 		vim.g.monotone_l = 50
	-- 		vim.g.monotone_contrast = 90
	-- 		vim.g.monotone_true_monotone = true
	-- 		vim.o.background = 'dark'
	-- 		vim.cmd('colorscheme monotone')
	-- 	end,
	-- },
	-- {
	-- 	"savq/melange-nvim",
	-- 	config = function()
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme melange")
	-- 	end,
	-- },
	-- {
	-- 	"rose-pine/neovim",
	-- 	priority = 1000,
	-- 	name = "rose-pine",
	-- 	config = function()
	-- 		require("rose-pine").setup()
	--
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme rose-pine")
	-- 	end
	-- },
	-- {
	-- 	"nyoom-engineering/oxocarbon.nvim",
	-- 	priority = 1000,
	-- 	name = "oxocarbon",
	-- 	config = function()
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme oxocarbon")
	-- 	end
	-- },
	-- {
	-- 	"slugbyte/lackluster.nvim",
	-- 	lazy = false,
	-- 	priority = 1000,
	-- 	init = function()
	-- 		vim.o.background = "dark"
	-- 		-- vim.cmd.colorscheme("lackluster")
	-- 		-- vim.cmd.colorscheme("lackluster-hack")
	-- 		vim.cmd.colorscheme("lackluster-mint")
	-- 	end,
	-- },
	-- {
	-- 	"ellisonleao/gruvbox.nvim",
	-- 	priority = 1000,
	-- 	config = function()
	-- 		require("gruvbox").setup({})
	--
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme gruvbox")
	-- 	end
	-- },
	-- {
	-- 	"bluz71/vim-moonfly-colors",
	-- 	name = "moonfly",
	-- 	lazy = false,
	-- 	priority = 1000,
	-- 	config = function()
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme moonfly")
	-- 	end
	-- },
	-- {
	-- 	"olimorris/onedarkpro.nvim",
	-- 	priority = 1000,
	-- 	config = function()
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme onedark")
	-- 	end
	-- }
}