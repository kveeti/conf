-- return {
-- 	'stevearc/oil.nvim',
-- 	dependencies = { "nvim-tree/nvim-web-devicons" },
-- 	config = function()
-- 		local oil = require("oil")
--
-- 		oil.setup({
-- 			delete_to_trash = true,
-- 			lsp_file_methods = {
-- 				timeout_ms = 1000,
-- 				autosave_changes = true,
-- 			},
-- 			watch_for_changes = true,
-- 			skip_confirm_for_simple_edits = true,
-- 			view_options = {
-- 				show_hidden = true
-- 			},
-- 			keymaps = {
-- 				["<C-h>"] = false,
-- 				["<C-j>"] = false,
-- 				["<C-k>"] = false,
-- 				["<C-l>"] = false,
-- 			}
-- 		})
--
-- 		vim.keymap.set("n", "<leader>x", oil.open)
-- 	end
-- }

-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
	'nvim-neo-tree/neo-tree.nvim',
	version = '*',
	dependencies = {
		'nvim-lua/plenary.nvim',
		'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
		'MunifTanjim/nui.nvim',
	},
	cmd = 'Neotree',
	keys = {
		{ '<leader>e', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
	},
	opts = {

		filesystem = {
			window = {
				position = "right",
				mappings = {
					['<leader>e'] = 'close_window',
				},
			},
		},
	},
}
