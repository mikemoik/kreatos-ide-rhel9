-- kreatos-ide-rhel9: misw's kreatos nvim config, built offline from source.
-- Plugins are vendored (see manifest/plugins.tsv) and installed by build.sh as
-- opt packages under site/; parsers and queries live in site/ too. Nothing
-- here downloads: no vim.pack, no claudecode, no JSON schemas.

-- layout installed by build.sh: <share>/config (this file) and <share>/site
local config = vim.fs.dirname(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
vim.g.kide_site = vim.fs.joinpath(vim.fs.dirname(config), "site")
vim.opt.rtp:prepend(config)
vim.opt.rtp:prepend(vim.g.kide_site)
vim.opt.packpath:prepend(vim.g.kide_site)

require("misw.options")

for _, name in ipairs({
  -- look
  "ethereal.nvim",
  "mini.icons",
  "snacks.nvim",
  "bufferline.nvim",
  "lualine.nvim",
  "nui.nvim",
  "noice.nvim",
  -- editing
  "which-key.nvim",
  "flash.nvim",
  "mini.ai",
  "mini.pairs",
  "trouble.nvim",
  "todo-comments.nvim",
  "grug-far.nvim",
  "persistence.nvim",
  "plenary.nvim",
  "neo-tree.nvim",
  -- code
  "nvim-treesitter",
  "nvim-treesitter-textobjects",
  "nvim-lspconfig",
  "lazydev.nvim",
  "blink.cmp",
  "friendly-snippets",
  "conform.nvim",
  "gitsigns.nvim",
  -- debug
  "nvim-dap",
  "nvim-nio",
  "nvim-dap-ui",
  "nvim-dap-python",
  "nvim-dap-virtual-text",
  -- c/c++
  "clangd_extensions.nvim",
  "cmake-tools.nvim",
  "neogen",
  "neotest",
  "neotest-gtest",
}) do
  vim.cmd.packadd(name)
end

local util = require("misw.util")

-- before the first redraw
require("misw.ui").setup()
require("misw.keymaps")
require("misw.autocmds")
require("misw.editor").setup()
require("misw.treesitter").setup()
require("misw.cpp").setup() -- before misw.lsp: it configures clangd
require("misw.lsp").setup()
require("misw.completion").setup()
require("misw.format").setup()
require("misw.git").setup()

-- after the UI is up
util.later(function()
  vim.opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"
  require("misw.ui").later()
  require("misw.editor").later()
  require("misw.dap").setup()
end)
