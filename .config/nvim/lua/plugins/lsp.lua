return {
    'neovim/nvim-lspconfig',
    dependencies = {
        { "williamboman/mason.nvim", version = "^1.0.0" },
        { "williamboman/mason-lspconfig.nvim", version = "^1.0.0" },
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
            vim.keymap.set("n", "gd", "gdzz")
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
            cssls                 = {},
            emmet_language_server = {},
            ts_ls                 = {},
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

        -- rust_analyzer -- catch harmless error
        for _, method in ipairs({ 'textDocument/diagnostic', 'workspace/diagnostic' }) do
            local default_diagnostic_handler = vim.lsp.handlers[method]
            vim.lsp.handlers[method] = function(err, result, context, config)
                if err ~= nil and err.code == -32802 then
                    return
                end
                return default_diagnostic_handler(err, result, context, config)
            end
        end
    end
}
