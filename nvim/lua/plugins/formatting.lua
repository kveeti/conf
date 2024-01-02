return {
	"stevearc/conform.nvim",
	config = function()
		local conform = require("conform")
		conform.setup({
			lua = { "stylua" },
			formatters_by_ft = {
				typescriptreact = { { "prettier", "prettierd" } },
				typescript = { { "prettier", "prettierd" } },
				javascriptreact = { { "prettier", "prettierd" } },
				javascript = { { "prettier", "prettierd" } },
			},

			format_on_save = {
				timeout_ms = 500,
				lsp_fallback = true
			}
		})
	end
}
