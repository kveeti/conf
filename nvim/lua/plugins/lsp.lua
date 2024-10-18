return {
    'neovim/nvim-lspconfig',
    dependencies = {
        'williamboman/mason.nvim',
        'williamboman/mason-lspconfig.nvim',
        {
            'j-hui/fidget.nvim',
            opts = {}
        },
        'folke/neodev.nvim',
    },
    config = function()
        local on_attach = function(_, bufnr)
            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "gd", builtin.lsp_definitions, { buffer = bufnr })
            vim.keymap.set("n", "gr", builtin.lsp_references, { buffer = bufnr })
            vim.keymap.set("n", "gi", builtin.lsp_implementations, { buffer = bufnr })

            vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
            vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, { buffer = bufnr })

            vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, { buffer = bufnr })
            vim.keymap.set("n", "<leader>c", vim.lsp.buf.code_action, { buffer = bufnr })
        end

        require('mason').setup()
        require('mason-lspconfig').setup()

        local servers = {
            emmet_language_server = {},
            tailwindcss           = {},
            cssls                 = {},
            gopls                 = {},
            tsserver              = {},
            rust_analyzer         = {},
            lua_ls                = {
                Lua = {
                    workspace = { checkThirdParty = false },
                    telemetry = { enable = false },
                    diagnostics = { disable = { 'missing-fields' } },
                },
            },
        }

        require('neodev').setup()

        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

        local mason_lspconfig = require 'mason-lspconfig'

        mason_lspconfig.setup {
            ensure_installed = vim.tbl_keys(servers),
        }

        mason_lspconfig.setup_handlers {
            function(server_name)
                require('lspconfig')[server_name].setup {
                    capabilities = capabilities,
                    on_attach = on_attach,
                    settings = servers[server_name],
                    filetypes = (servers[server_name] or {}).filetypes,
                }
            end,
        }
    end
}
