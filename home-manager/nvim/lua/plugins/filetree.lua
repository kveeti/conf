return {
	"nvim-neo-tree/neo-tree.nvim",
	version = "*",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
		"MunifTanjim/nui.nvim",
	},
	config = function ()
		require('neo-tree').setup({})

		vim.api.nvim_set_keymap('n', '<leader>se', ':Neotree source=filesystem reveal=true position=right<CR>', { noremap = true, silent = true })
	end,
}
