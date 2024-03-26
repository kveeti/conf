return {
    "github/copilot.vim",
    event = "TextChangedI",
    config = function()
        vim.keymap.set('i', '<C-J>', 'copilot#Accept("<CR>")', {
            expr = true,
            replace_keycodes = false
        })
    end
}
