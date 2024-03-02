local telescope = require('telescope')

return {
  main = function() 
    telescope.setup({
      defaults = {
        layout_strategy = "flex",
            layout_config = {
                horizontal = {
                    prompt_position = "top",
                    preview_width = 0.55,
                },
                vertical = { mirror = false },
                width = 0.87,
                height = 0.8,
                preview_cutoff = 120,
            },
      }
    })

    local map = vim.keymap.set
    local tsbuiltin = require('telescope.builtin')

    -- builtin
    map('n', '<leader>ff', tsbuiltin.find_files)
    map('n', '<leader>fs', tsbuiltin.builtin)
    map('n', '<leader>fg', tsbuiltin.live_grep)


    -- lsp
    map('n', 'gd', tsbuiltin.lsp_definitions)
    map('n', 'gr', tsbuiltin.lsp_references)
    map('n', 'gi', tsbuiltin.lsp_implementations)
  end
}
