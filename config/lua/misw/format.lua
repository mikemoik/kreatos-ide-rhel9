-- Formatting: conform.nvim, format on save (toggle <leader>uf / <leader>uF).
-- shfmt (sh), fish_indent (fish), clang-format (c/cpp, from RHEL9);
-- everything else falls back to the LSP formatter (ruff for Python,
-- neocmakelsp for CMake). No Lua formatter is bundled.
local util = require("misw.util")
local M = {}

function M.setup()
  require("conform").setup({
    default_format_opts = {
      timeout_ms = 3000,
      async = false,
      quiet = false,
      lsp_format = "fallback",
    },
    formatters_by_ft = {
      fish = { "fish_indent" },
      sh = { "shfmt" },
      c = { "clang-format" },
      cpp = { "clang-format" },
    },
    formatters = {
      injected = { options = { ignore_errors = true } },
    },
  })

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("misw_format", { clear = true }),
    callback = function(ev)
      util.format.run({ buf = ev.buf })
    end,
  })

  vim.keymap.set({ "n", "x" }, "<leader>cF", function()
    require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
  end, { desc = "Format Injected Langs" })
end

return M
