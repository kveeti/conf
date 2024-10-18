return {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
        'nvim-lua/plenary.nvim',
        {
            'nvim-telescope/telescope-fzf-native.nvim',
            build = 'make',
            cond = function()
                return vim.fn.executable 'make' == 1
            end,
        },
    },
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

        pcall(require('telescope').load_extension, 'fzf')
        local builtin = require('telescope.builtin')

        vim.keymap.set('n', '<leader>b', builtin.current_buffer_fuzzy_find, { desc = 'Find in current [b]uffer' })
        vim.keymap.set('n', '<leader>f', builtin.find_files, { desc = '[F]ind files' })
        vim.keymap.set('n', '<leader>g', builtin.live_grep, { desc = 'Live [g]rep' })

        -- find files in nvim config dir
        vim.keymap.set('n', '<leader>m', function() builtin.find_files({ cwd = vim.fn.stdpath 'config' }) end)
    end
}
