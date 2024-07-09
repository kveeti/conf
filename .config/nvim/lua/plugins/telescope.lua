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

        vim.keymap.set('n', '<leader>b', builtin.current_buffer_fuzzy_find)
        vim.keymap.set('n', '<leader>f', builtin.find_files)
        vim.keymap.set('n', '<leader>g', builtin.live_grep)
        vim.keymap.set('n', '<leader>m', function() builtin.find_files({ cwd = vim.fn.stdpath 'config' }) end)
    end
}
