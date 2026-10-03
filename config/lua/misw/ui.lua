-- Look: colorscheme, icons, snacks (UI + utilities), bufferline, lualine, noice.
-- Transparency is applied by plugin/after/transparency.lua.
local util = require("misw.util")
local icons = util.icons
local M = {}

-- runs during init.lua: things that must exist before the first redraw
function M.setup()
  vim.cmd.colorscheme("ethereal")

  require("mini.icons").setup({
    file = {
      [".keep"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
      ["devcontainer.json"] = { glyph = "", hl = "MiniIconsAzure" },
    },
    filetype = {
      dotenv = { glyph = "", hl = "MiniIconsYellow" },
    },
  })
  package.preload["nvim-web-devicons"] = function()
    require("mini.icons").mock_nvim_web_devicons()
    return package.loaded["nvim-web-devicons"]
  end

  local function term_nav(dir)
    return function(self)
      return self:is_floating() and "<c-" .. dir .. ">"
        or vim.schedule(function()
          vim.cmd.wincmd(dir)
        end)
    end
  end

  -- noice takes over vim.notify; keep snacks from grabbing it first
  local notify = vim.notify
  require("snacks").setup({
    bigfile = { enabled = true },
    quickfile = { enabled = true },
    indent = { enabled = true },
    input = { enabled = true },
    notifier = { enabled = true },
    scope = { enabled = true },
    scroll = { enabled = false }, -- misw: no animated scrolling
    statuscolumn = { enabled = false }, -- set via 'statuscolumn' in options.lua
    words = { enabled = true },
    terminal = {
      win = {
        keys = {
          nav_h = { "<C-h>", term_nav("h"), desc = "Go to Left Window", expr = true, mode = "t" },
          nav_j = { "<C-j>", term_nav("j"), desc = "Go to Lower Window", expr = true, mode = "t" },
          nav_k = { "<C-k>", term_nav("k"), desc = "Go to Upper Window", expr = true, mode = "t" },
          nav_l = { "<C-l>", term_nav("l"), desc = "Go to Right Window", expr = true, mode = "t" },
          hide_slash = { "<C-/>", "hide", desc = "Hide Terminal", mode = { "t", "n" } },
          hide_underscore = { "<c-_>", "hide", desc = "which_key_ignore", mode = { "t", "n" } },
        },
      },
    },
    picker = require("misw.editor").picker_opts(),
  })
  vim.notify = notify

  -- lualine is set up after startup; until then hide the default statusline
  vim.g.lualine_laststatus = vim.o.laststatus
  if vim.fn.argc(-1) > 0 then
    vim.o.statusline = " "
  else
    vim.o.laststatus = 0
  end
end

local function bufferline()
  require("bufferline").setup({
    options = {
      close_command = function(n)
        Snacks.bufdelete(n)
      end,
      right_mouse_command = function(n)
        Snacks.bufdelete(n)
      end,
      diagnostics = "nvim_lsp",
      always_show_bufferline = false,
      diagnostics_indicator = function(_, _, diag)
        local ret = (diag.error and icons.diagnostics.Error .. diag.error .. " " or "")
          .. (diag.warning and icons.diagnostics.Warn .. diag.warning or "")
        return vim.trim(ret)
      end,
      offsets = {
        { filetype = "neo-tree", text = "Neo-tree", highlight = "Directory", text_align = "left" },
        { filetype = "snacks_layout_box" },
      },
      get_element_icon = function(opts)
        return icons.ft[opts.filetype]
      end,
    },
  })
  -- fix bufferline when restoring a session
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
    callback = function()
      vim.schedule(function()
        pcall(nvim_bufferline)
      end)
    end,
  })
  local map = vim.keymap.set
  map("n", "<leader>bp", "<Cmd>BufferLineTogglePin<CR>", { desc = "Toggle Pin" })
  map("n", "<leader>bP", "<Cmd>BufferLineGroupClose ungrouped<CR>", { desc = "Delete Non-Pinned Buffers" })
  map("n", "<leader>br", "<Cmd>BufferLineCloseRight<CR>", { desc = "Delete Buffers to the Right" })
  map("n", "<leader>bl", "<Cmd>BufferLineCloseLeft<CR>", { desc = "Delete Buffers to the Left" })
  map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
  map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
  map("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
  map("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
  map("n", "[B", "<cmd>BufferLineMovePrev<cr>", { desc = "Move buffer prev" })
  map("n", "]B", "<cmd>BufferLineMoveNext<cr>", { desc = "Move buffer next" })
end

local function lualine()
  local lualine_require = require("lualine_require")
  lualine_require.require = require
  vim.o.laststatus = vim.g.lualine_laststatus

  local opts = {
    options = {
      theme = "auto",
      globalstatus = vim.o.laststatus == 3,
    },
    sections = {
      lualine_a = { "mode" },
      lualine_b = { "branch" },
      lualine_c = {
        util.lualine.root_dir(),
        {
          "diagnostics",
          symbols = {
            error = icons.diagnostics.Error,
            warn = icons.diagnostics.Warn,
            info = icons.diagnostics.Info,
            hint = icons.diagnostics.Hint,
          },
        },
        { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
        { util.lualine.pretty_path() },
      },
      lualine_x = {
        {
          function()
            return require("noice").api.status.command.get()
          end,
          cond = function()
            return package.loaded["noice"] and require("noice").api.status.command.has()
          end,
          color = function()
            return { fg = Snacks.util.color("Statement") }
          end,
        },
        {
          function()
            return require("noice").api.status.mode.get()
          end,
          cond = function()
            return package.loaded["noice"] and require("noice").api.status.mode.has()
          end,
          color = function()
            return { fg = Snacks.util.color("Constant") }
          end,
        },
        {
          function()
            return "  " .. require("dap").status()
          end,
          cond = function()
            return package.loaded["dap"] and require("dap").status() ~= ""
          end,
          color = function()
            return { fg = Snacks.util.color("Debug") }
          end,
        },
        {
          "diff",
          symbols = {
            added = icons.git.added,
            modified = icons.git.modified,
            removed = icons.git.removed,
          },
          source = function()
            local gitsigns = vim.b.gitsigns_status_dict
            if gitsigns then
              return { added = gitsigns.added, modified = gitsigns.changed, removed = gitsigns.removed }
            end
          end,
        },
      },
      lualine_y = {
        { "progress", separator = " ", padding = { left = 1, right = 0 } },
        { "location", padding = { left = 0, right = 1 } },
      },
      lualine_z = {
        function()
          return " " .. os.date("%R")
        end,
      },
    },
    extensions = { "neo-tree" },
  }

  -- current LSP symbol path in the statusline
  local symbols = require("trouble").statusline({
    mode = "symbols",
    groups = {},
    title = false,
    filter = { range = true },
    format = "{kind_icon}{symbol.name:Normal}",
    hl_group = "lualine_c_normal",
  })
  table.insert(opts.sections.lualine_c, {
    symbols and symbols.get,
    cond = function()
      return vim.b.trouble_lualine ~= false and symbols.has()
    end,
  })

  require("lualine").setup(opts)
end

local function noice()
  require("noice").setup({
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
      },
    },
    routes = {
      {
        filter = {
          event = "msg_show",
          any = {
            { find = "%d+L, %d+B" },
            { find = "; after #%d+" },
            { find = "; before #%d+" },
          },
        },
        view = "mini",
      },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
    },
  })
  local map = vim.keymap.set
  map("c", "<S-Enter>", function()
    require("noice").redirect(vim.fn.getcmdline())
  end, { desc = "Redirect Cmdline" })
  map("n", "<leader>snl", function()
    require("noice").cmd("last")
  end, { desc = "Noice Last Message" })
  map("n", "<leader>snh", function()
    require("noice").cmd("history")
  end, { desc = "Noice History" })
  map("n", "<leader>sna", function()
    require("noice").cmd("all")
  end, { desc = "Noice All" })
  map("n", "<leader>snd", function()
    require("noice").cmd("dismiss")
  end, { desc = "Dismiss All" })
  map("n", "<leader>snt", function()
    require("noice").cmd("pick")
  end, { desc = "Noice Picker" })
  map({ "i", "n", "s" }, "<c-f>", function()
    if not require("noice.lsp").scroll(4) then
      return "<c-f>"
    end
  end, { silent = true, expr = true, desc = "Scroll Forward" })
  map({ "i", "n", "s" }, "<c-b>", function()
    if not require("noice.lsp").scroll(-4) then
      return "<c-b>"
    end
  end, { silent = true, expr = true, desc = "Scroll Backward" })
end

-- runs after the UI is up (LazyVim's VeryLazy)
function M.later()
  noice()
  bufferline()
  lualine()
  vim.keymap.set("n", "<leader>n", function()
    Snacks.picker.notifications()
  end, { desc = "Notification History" })
  vim.keymap.set("n", "<leader>un", function()
    Snacks.notifier.hide()
  end, { desc = "Dismiss All Notifications" })
end

return M
