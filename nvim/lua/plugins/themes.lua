return {
	-- {
	-- 	'catppuccin/nvim',
	-- 	name = "catppuccin",
	-- 	priority = 1000,
	-- 	config = function()
	-- 		require('catppuccin').setup({
	-- 			flavour = 'frappe'
	-- 		})
	-- 	end,
	-- },
	-- {
	-- 	"rose-pine/neovim",
	-- 	priority = 1000,
	-- 	name = "rose-pine"
	-- },
	{
		"nyoom-engineering/oxocarbon.nvim",
		priority = 1000,
		name = "oxocarbon",
		config = function()
			vim.opt.background = "dark"
			vim.cmd("colorscheme oxocarbon")
		end
	}
}
