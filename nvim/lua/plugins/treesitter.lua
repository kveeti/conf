return {
	'nvim-treesitter/nvim-treesitter',
	dependencies = {
		'nvim-treesitter/nvim-treesitter-textobjects',
	},
	build = ':TSUpdate',
	config = function()
		vim.defer_fn(function()
			require('nvim-treesitter.configs').setup {
				ensure_installed = {
					'tsx',
					'javascript',
					'typescript',
					'go',
					'rust',
					'bash',
					'lua',
				},

				auto_install = false,

				highlight = { enable = true },
				indent = { enable = true },
				incremental_selection = {
					enable = true,
					keymaps = {
						init_selection = '<c-space>',
						node_incremental = '<c-space>',
						scope_incremental = '<c-s>',
						node_decremental = '<M-space>',
					},
				},
			}
		end, 0)
	end
}
