-- Completion: blink.cmp (LSP, path, snippets via friendly-snippets, buffer;
-- lazydev for lua), set up on the first InsertEnter/CmdlineEnter. Uses the
-- pure-Lua fuzzy matcher: the Rust one needs nightly Rust (not on RHEL).
local util = require("misw.util")
local M = {}

-- expand snippets in the top-level session (native sessions don't nest)
local function expand(snippet)
  local session = vim.snippet.active() and vim.snippet._session or nil
  local ok, err = pcall(vim.snippet.expand, snippet)
  if not ok then
    vim.notify("Failed to parse snippet.\n" .. err, vim.log.levels.WARN, { title = "vim.snippet" })
  end
  if session then
    vim.snippet._session = session
  end
end

local function snippet_forward()
  if vim.snippet.active({ direction = 1 }) then
    vim.schedule(function()
      vim.snippet.jump(1)
    end)
    return true
  end
end

local function setup()
  require("blink.cmp").setup({
    fuzzy = { implementation = "lua" },
    snippets = { preset = "default", expand = expand },
    appearance = {
      use_nvim_cmp_as_default = false,
      nerd_font_variant = "mono",
      kind_icons = util.icons.kinds,
    },
    completion = {
      accept = { auto_brackets = { enabled = true } },
      menu = { draw = { treesitter = { "lsp" } } },
      documentation = { auto_show = true, auto_show_delay_ms = 200 },
      ghost_text = { enabled = true },
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      per_filetype = {
        lua = { inherit_defaults = true, "lazydev" },
      },
      providers = {
        lazydev = {
          name = "LazyDev",
          module = "lazydev.integrations.blink",
          score_offset = 100, -- above lsp
        },
      },
    },
    cmdline = {
      enabled = true,
      keymap = {
        preset = "cmdline",
        ["<Right>"] = false,
        ["<Left>"] = false,
        -- menu open: walk/accept items; otherwise history / run the command
        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
      },
      completion = {
        list = { selection = { preselect = false } },
        menu = {
          auto_show = function()
            return vim.fn.getcmdtype() == ":"
          end,
        },
        ghost_text = { enabled = true },
      },
    },
    keymap = {
      preset = "enter",
      ["<C-y>"] = { "select_and_accept" },
      ["<Tab>"] = { snippet_forward, "fallback" },
    },
  })
end

function M.setup()
  vim.api.nvim_create_autocmd({ "InsertEnter", "CmdlineEnter" }, {
    group = vim.api.nvim_create_augroup("misw_blink", { clear = true }),
    once = true,
    callback = setup,
  })
end

return M
