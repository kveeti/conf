local copilot = require('copilot')
local lspconfig = require('lspconfig')
local rust_tools = require('rust-tools')
local treesitter = require('nvim-treesitter.configs')
local treesitter_context = require('treesitter-context')
local fidget = require('fidget')

local function on_attach(client, buffer)
    local map = function(keys, func)
        vim.keymap.set('n', keys, func, { buffer = buffer })
    end
    
    map('<leader>r', vim.lsp.buf.rename)
    map('<leader>c', vim.lsp.buf.code_action)
    map('<leader>K', vim.lsp.buf.hover)
    map('<C-k>', vim.lsp.buf.signature_help)
end

return {
    main = function()
        fidget.setup() 

        -- rust spesific setup
        rust_tools.setup({
            on_attach = on_attach,
            server = {
                settings = {
                    ['rust-analyzer'] = {
                        cargo = {
                            buildScripts = {
                                enable = true,
                            },
                        },
                        diagnostics = {
                            enable = false,
                        },
                    },
                },
            },
        })

        local servers = {
            lua_ls                = {
                Lua = {
                    workspace = { checkThirdParty = false },
                    telemetry = { enable = false },
                    diagnostics = { disable = { 'missing-fields' } },
                },
            },
            gopls                 = {},
            html                  = { filetypes = { 'html', 'twig', 'hbs' } },
            cssls                 = {},
            emmet_language_server = {},
            eslint                = {},
            tsserver              = {},
            jsonls                = {},
            tailwindcss           = {},
            gopls                 = {},
        }

        for server, server_config in pairs(servers) do
            local config = { on_attach = on_attach }

            if server_config then
                config['settings'] = server_config
                config['filetypes'] = server_config['filetypes']
            end

            lspconfig[server].setup(config)
        end
    end
}
