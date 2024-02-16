return {
	"github/copilot.vim",
	event = "TextChangedI",
	config = function()
		vim.g.copilot_assume_mapped = true;
	end
}
