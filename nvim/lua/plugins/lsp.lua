return {
    {
        -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
        -- used for completion, annotations and signatures of Neovim apis
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
            library = {
                -- Load luvit types when the `vim.uv` word is found
                { path = 'luvit-meta/library', words = { 'vim%.uv' } },
            },
        },
    },
    { 'Bilal2453/luvit-meta', lazy = true },

    {
        'neovim/nvim-lspconfig',
        dependencies = {
            'williamboman/mason.nvim',
            'williamboman/mason-lspconfig.nvim',
            {
                'j-hui/fidget.nvim',
                opts = {}
            },
        },

        config = function()
            vim.api.nvim_create_autocmd('LspAttach', {
                group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
                callback = function(event)
                    local bufnr = event.buf

                    local builtin = require("telescope.builtin")
                    vim.keymap.set("n", "gd", builtin.lsp_definitions, { buffer = bufnr, desc = "[G]o to [d]efinition" })
                    vim.keymap.set("n", "gr", builtin.lsp_references, { buffer = bufnr, desc = "[G]o to [r]eferences" })
                    vim.keymap.set("n", "gi", builtin.lsp_implementations,
                        { buffer = bufnr, desc = "[G]o to [i]mplementations" })

                    vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr, desc = "Hover" })
                    vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, { buffer = bufnr, desc = "Signature Help" })

                    vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, { buffer = bufnr, desc = "[R]ename" })
                    vim.keymap.set("n", "<leader>c", vim.lsp.buf.code_action, { buffer = bufnr, desc = "[C]ode action" })

                    -- highlight references to symbol under cursor
                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
                        local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight-on-rest', { clear = false })
                        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.document_highlight,
                        })

                        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.clear_references,
                        })

                        vim.api.nvim_create_autocmd('LspDetach', {
                            group = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
                            callback = function(event2)
                                vim.lsp.buf.clear_references()
                                vim.api.nvim_clear_autocmds { group = 'lsp-highlight-on-rest', buffer = event2.buf }
                            end,
                        })
                    end
                end
            })


            require('mason').setup()
            require('mason-lspconfig').setup()

            local servers = {
                tsserver              = {},
                cssls                 = {},
                emmet_language_server = {},
                eslint                = {},
                astro                 = {},
                unocss                = {},
                tailwindcss           = {},
                -- biome                 = {},

                -- rust_analyzer         = {},
                -- gopls                 = {},

                lua_ls                = {
                    Lua = {
                        workspace = { checkThirdParty = false },
                        telemetry = { enable = false },
                        diagnostics = { disable = { 'missing-fields' } },
                    },
                },
            }

            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

            require('mason-lspconfig').setup({
                ensure_installed = vim.tbl_keys(servers),
                handlers = {
                    function(server_name)
                        local server = servers[server_name] or {}

                        require('lspconfig')[server_name].setup {
                            cmd = server.cmd,
                            settings = server.settings,
                            filetypes = server.filetypes,
                            capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {}),
                        }
                    end,
                }
            })
        end
    }
}
