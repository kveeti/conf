return {
	{
		"lalitmee/cobalt2.nvim",
		name = "cobalt2",
		lazy = false,
		priority = 1000,
		dependencies = { "tjdevries/colorbuddy.nvim", tag = "v1.0.0" },
		init = function()
			require("colorbuddy").colorscheme("cobalt2")

			vim.o.background = "dark"
			vim.cmd("colorscheme cobalt2")
		end,
	},
}
