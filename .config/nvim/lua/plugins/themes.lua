return {
	-- {
	-- 	'catppuccin/nvim',
	-- 	name = "catppuccin",
	-- 	priority = 1000,
	-- 	config = function()
	-- 		require('catppuccin').setup({
	-- 			flavour = 'frappe'
	-- 		})
	--
	-- 		vim.o.background = "dark"
	-- 		vim.cmd("colorscheme catppuccin")
	-- 	end,
	-- },
	-- {
	-- 	"rose-pine/neovim",
	-- 	priority = 1000,
	-- 	name = "rose-pine"
	-- 	config = function()
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
	-- 		vim.cmd.colorscheme("lackluster")
	-- 		-- vim.cmd.colorscheme("lackluster-hack")
	-- 		-- vim.cmd.colorscheme("lackluster-mint")
	-- 	end,
	-- },
	{
		"ellisonleao/gruvbox.nvim",
		priority = 1000,
		config = function()
			require("gruvbox").setup({})

			vim.o.background = "dark"
			vim.cmd("colorscheme gruvbox")
		end
	}
}
