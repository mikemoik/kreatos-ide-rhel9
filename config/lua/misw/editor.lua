-- Editing and navigation: snacks pickers, which-key, flash, mini.ai/pairs,
-- trouble, todo-comments, grug-far, persistence, neo-tree, scratch buffers.
local util = require("misw.util")
local M = {}

local function map(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, rhs, opts)
end

-- picker with the "Root Dir" convention: cwd = project root unless root = false
local function pick(source, opts)
  opts = opts or {}
  return function()
    local o = vim.deepcopy(opts)
    if not o.cwd and o.root ~= false then
      o.cwd = util.root.get()
    end
    o.root = nil
    Snacks.picker.pick(source, o)
  end
end

-- snacks picker options, passed to Snacks.setup in ui.lua
function M.picker_opts()
  return {
    win = {
      input = {
        keys = {
          ["<a-c>"] = { "toggle_cwd", mode = { "n", "i" } },
          ["<a-t>"] = { "trouble_open", mode = { "n", "i" } },
          ["<a-s>"] = { "flash", mode = { "n", "i" } },
          ["s"] = { "flash" },
        },
      },
    },
    actions = {
      toggle_cwd = function(p)
        local root = util.root.get({ buf = p.input.filter.current_buf })
        local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
        p:set_cwd(p:cwd() == root and cwd or root)
        p:find()
      end,
      trouble_open = function(...)
        return require("trouble.sources.snacks").actions.trouble_open.action(...)
      end,
      flash = function(picker)
        require("flash").jump({
          pattern = "^",
          label = { after = { 0, 0 } },
          search = {
            mode = "search",
            exclude = {
              function(win)
                return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "snacks_picker_list"
              end,
            },
          },
          action = function(match)
            local idx = picker.list:row2idx(match.pos[1])
            picker.list:_move(idx, true, true)
          end,
        })
      end,
    },
  }
end

local function pickers()
  local P = Snacks.picker
  -- stylua: ignore start
  map("n", "<leader>,", function() P.buffers() end, { desc = "Buffers" })
  map("n", "<leader>/", pick("grep"), { desc = "Grep (Root Dir)" })
  map("n", "<leader>:", function() P.command_history() end, { desc = "Command History" })
  map("n", "<leader><space>", pick("files"), { desc = "Find Files (Root Dir)" })
  -- find
  map("n", "<leader>fb", function() P.buffers() end, { desc = "Buffers" })
  map("n", "<leader>fB", function() P.buffers({ hidden = true, nofile = true }) end, { desc = "Buffers (all)" })
  map("n", "<leader>fc", pick("files", { cwd = vim.fn.stdpath("config") }), { desc = "Find Config File" })
  map("n", "<leader>ff", pick("files"), { desc = "Find Files (Root Dir)" })
  map("n", "<leader>fF", pick("files", { root = false }), { desc = "Find Files (cwd)" })
  map("n", "<leader>fg", function() P.git_files() end, { desc = "Find Files (git-files)" })
  map("n", "<leader>fr", pick("recent"), { desc = "Recent" })
  map("n", "<leader>fR", function() P.recent({ filter = { cwd = true } }) end, { desc = "Recent (cwd)" })
  -- git
  map("n", "<leader>gd", function() P.git_diff() end, { desc = "Git Diff (hunks)" })
  map("n", "<leader>gD", function() P.git_diff({ base = "origin", group = true }) end, { desc = "Git Diff (origin)" })
  map("n", "<leader>gs", function() P.git_status() end, { desc = "Git Status" })
  map("n", "<leader>gS", function() P.git_stash() end, { desc = "Git Stash" })
  -- search
  map("n", "<leader>sb", function() P.lines() end, { desc = "Buffer Lines" })
  map("n", "<leader>sB", function() P.grep_buffers() end, { desc = "Grep Open Buffers" })
  map("n", "<leader>sg", pick("grep"), { desc = "Grep (Root Dir)" })
  map("n", "<leader>sG", pick("grep", { root = false }), { desc = "Grep (cwd)" })
  map({ "n", "x" }, "<leader>sw", pick("grep_word"), { desc = "Visual selection or word (Root Dir)" })
  map({ "n", "x" }, "<leader>sW", pick("grep_word", { root = false }), { desc = "Visual selection or word (cwd)" })
  map("n", '<leader>s"', function() P.registers() end, { desc = "Registers" })
  map("n", "<leader>s/", function() P.search_history() end, { desc = "Search History" })
  map("n", "<leader>sa", function() P.autocmds() end, { desc = "Autocmds" })
  map("n", "<leader>sc", function() P.command_history() end, { desc = "Command History" })
  map("n", "<leader>sC", function() P.commands() end, { desc = "Commands" })
  map("n", "<leader>sd", function() P.diagnostics() end, { desc = "Diagnostics" })
  map("n", "<leader>sD", function() P.diagnostics_buffer() end, { desc = "Buffer Diagnostics" })
  map("n", "<leader>sh", function() P.help() end, { desc = "Help Pages" })
  map("n", "<leader>sH", function() P.highlights() end, { desc = "Highlights" })
  map("n", "<leader>si", function() P.icons() end, { desc = "Icons" })
  map("n", "<leader>sj", function() P.jumps() end, { desc = "Jumps" })
  map("n", "<leader>sk", function() P.keymaps() end, { desc = "Keymaps" })
  map("n", "<leader>sl", function() P.loclist() end, { desc = "Location List" })
  map("n", "<leader>sM", function() P.man() end, { desc = "Man Pages" })
  map("n", "<leader>sm", function() P.marks() end, { desc = "Marks" })
  map("n", "<leader>sR", function() P.resume() end, { desc = "Resume" })
  map("n", "<leader>sq", function() P.qflist() end, { desc = "Quickfix List" })
  map("n", "<leader>su", function() P.undo() end, { desc = "Undotree" })
  map("n", "<leader>uC", function() P.colorschemes() end, { desc = "Colorschemes" })
  -- scratch
  map("n", "<leader>.", function() Snacks.scratch() end, { desc = "Toggle Scratch Buffer" })
  map("n", "<leader>S", function() Snacks.scratch.select() end, { desc = "Select Scratch Buffer" })
  -- stylua: ignore end
end

local function which_key()
  local wk = require("which-key")
  wk.setup({
    preset = "helix",
    spec = {
      {
        mode = { "n", "x" },
        { "<leader><tab>", group = "tabs" },
        { "<leader>c", group = "code" },
        { "<leader>d", group = "debug" },
        { "<leader>f", group = "file/find" },
        { "<leader>g", group = "git" },
        { "<leader>gh", group = "hunks" },
        { "<leader>q", group = "quit/session" },
        { "<leader>s", group = "search" },
        { "<leader>sn", group = "noice" },
        { "<leader>u", group = "ui" },
        { "<leader>x", group = "diagnostics/quickfix" },
        { "[", group = "prev" },
        { "]", group = "next" },
        { "g", group = "goto" },
        { "gs", group = "surround" },
        { "z", group = "fold" },
        {
          "<leader>b",
          group = "buffer",
          expand = function()
            return require("which-key.extras").expand.buf()
          end,
        },
        {
          "<leader>w",
          group = "windows",
          proxy = "<c-w>",
          expand = function()
            return require("which-key.extras").expand.win()
          end,
        },
        { "gx", desc = "Open with system app" },
      },
    },
  })
  map("n", "<leader>?", function()
    wk.show({ global = false })
  end, { desc = "Buffer Keymaps (which-key)" })
  map("n", "<c-w><space>", function()
    wk.show({ keys = "<c-w>", loop = true })
  end, { desc = "Window Hydra Mode (which-key)" })
end

local function flash()
  require("flash").setup({})
  local f = require("flash")
  -- stylua: ignore start
  map({ "n", "x", "o" }, "s", function() f.jump() end, { desc = "Flash" })
  map({ "n", "x", "o" }, "S", function() f.treesitter() end, { desc = "Flash Treesitter" })
  map("o", "r", function() f.remote() end, { desc = "Remote Flash" })
  map({ "o", "x" }, "R", function() f.treesitter_search() end, { desc = "Treesitter Search" })
  map("c", "<c-s>", function() f.toggle() end, { desc = "Toggle Flash Search" })
  map({ "n", "o", "x" }, "<c-space>", function()
    f.treesitter({ actions = { ["<c-space>"] = "next", ["<BS>"] = "prev" } })
  end, { desc = "Treesitter Incremental Selection" })
  -- stylua: ignore end
end

-- whole buffer textobject (ag / ig)
local function ai_buffer(ai_type)
  local start_line, end_line = 1, vim.fn.line("$")
  if ai_type == "i" then
    local first, last = vim.fn.nextnonblank(start_line), vim.fn.prevnonblank(end_line)
    if first == 0 or last == 0 then
      return { from = { line = start_line, col = 1 } }
    end
    start_line, end_line = first, last
  end
  local to_col = math.max(vim.fn.getline(end_line):len(), 1)
  return { from = { line = start_line, col = 1 }, to = { line = end_line, col = to_col } }
end

-- which-key labels for the mini.ai textobjects
local function ai_whichkey()
  local objects = {
    { " ", desc = "whitespace" },
    { '"', desc = '" string' },
    { "'", desc = "' string" },
    { "(", desc = "() block" },
    { ")", desc = "() block with ws" },
    { "<", desc = "<> block" },
    { ">", desc = "<> block with ws" },
    { "?", desc = "user prompt" },
    { "U", desc = "use/call without dot" },
    { "[", desc = "[] block" },
    { "]", desc = "[] block with ws" },
    { "_", desc = "underscore" },
    { "`", desc = "` string" },
    { "a", desc = "argument" },
    { "b", desc = ")]} block" },
    { "c", desc = "class" },
    { "d", desc = "digit(s)" },
    { "e", desc = "CamelCase / snake_case" },
    { "f", desc = "function" },
    { "g", desc = "entire file" },
    { "i", desc = "indent" },
    { "o", desc = "block, conditional, loop" },
    { "q", desc = "quote `\"'" },
    { "t", desc = "tag" },
    { "u", desc = "use/call" },
    { "{", desc = "{} block" },
    { "}", desc = "{} with ws" },
  }
  local ret = { mode = { "o", "x" } }
  local mappings = {
    around = "a",
    inside = "i",
    around_next = "an",
    inside_next = "in",
    around_last = "al",
    inside_last = "il",
  }
  for name, prefix in pairs(mappings) do
    name = name:gsub("^around_", ""):gsub("^inside_", "")
    ret[#ret + 1] = { prefix, group = name }
    for _, obj in ipairs(objects) do
      ret[#ret + 1] = { prefix .. obj[1], desc = obj.desc }
    end
  end
  require("which-key").add(ret, { notify = false })
end

local function mini_ai()
  local ai = require("mini.ai")
  ai.setup({
    n_lines = 500,
    custom_textobjects = {
      o = ai.gen_spec.treesitter({ -- code block
        a = { "@block.outer", "@conditional.outer", "@loop.outer" },
        i = { "@block.inner", "@conditional.inner", "@loop.inner" },
      }),
      f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
      c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
      t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" }, -- tags
      d = { "%f[%d]%d+" }, -- digits
      e = { -- word with case
        { "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
        "^().*()$",
      },
      g = ai_buffer,
      u = ai.gen_spec.function_call(), -- u for "usage"
      U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }), -- without dot in function name
    },
  })
  ai_whichkey()
end

local function mini_pairs()
  local opts = {
    modes = { insert = true, command = true, terminal = false },
    -- skip autopair when next character is one of these
    skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
    -- skip autopair when the cursor is inside these treesitter nodes
    skip_ts = { "string" },
    -- skip autopair when next character is closing pair and there are more closing pairs than opening pairs
    skip_unbalanced = true,
    -- better deal with markdown code blocks
    markdown = true,
  }
  Snacks.toggle({
    name = "Mini Pairs",
    get = function()
      return not vim.g.minipairs_disable
    end,
    set = function(state)
      vim.g.minipairs_disable = not state
    end,
  }):map("<leader>up")
  local pairs = require("mini.pairs")
  pairs.setup(opts)
  local open = pairs.open
  pairs.open = function(pair, neigh_pattern)
    if vim.fn.getcmdline() ~= "" then
      return open(pair, neigh_pattern)
    end
    local o, c = pair:sub(1, 1), pair:sub(2, 2)
    local line = vim.api.nvim_get_current_line()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local next = line:sub(cursor[2] + 1, cursor[2] + 1)
    local before = line:sub(1, cursor[2])
    if opts.markdown and o == "`" and vim.bo.filetype == "markdown" and before:match("^%s*``") then
      return "`\n```" .. vim.api.nvim_replace_termcodes("<up>", true, true, true)
    end
    if opts.skip_next and next ~= "" and next:match(opts.skip_next) then
      return o
    end
    if opts.skip_ts and #opts.skip_ts > 0 then
      local ok, captures = pcall(vim.treesitter.get_captures_at_pos, 0, cursor[1] - 1, math.max(cursor[2] - 1, 0))
      for _, capture in ipairs(ok and captures or {}) do
        if vim.tbl_contains(opts.skip_ts, capture.capture) then
          return o
        end
      end
    end
    if opts.skip_unbalanced and next == c and c ~= o then
      local _, count_open = line:gsub(vim.pesc(pair:sub(1, 1)), "")
      local _, count_close = line:gsub(vim.pesc(pair:sub(2, 2)), "")
      if count_close > count_open then
        return o
      end
    end
    return open(pair, neigh_pattern)
  end
end

local function trouble()
  require("trouble").setup({
    modes = {
      lsp = { win = { position = "right" } },
    },
  })
  -- stylua: ignore start
  map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics (Trouble)" })
  map("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer Diagnostics (Trouble)" })
  map("n", "<leader>cs", "<cmd>Trouble symbols toggle<cr>", { desc = "Symbols (Trouble)" })
  map("n", "<leader>cS", "<cmd>Trouble lsp toggle<cr>", { desc = "LSP references/definitions/... (Trouble)" })
  map("n", "<leader>xL", "<cmd>Trouble loclist toggle<cr>", { desc = "Location List (Trouble)" })
  map("n", "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", { desc = "Quickfix List (Trouble)" })
  -- stylua: ignore end
  local function qf_jump(dir)
    return function()
      local t = require("trouble")
      if t.is_open() then
        t[dir]({ skip_groups = true, jump = true })
      else
        local ok, err = pcall(dir == "prev" and vim.cmd.cprev or vim.cmd.cnext)
        if not ok then
          vim.notify(err, vim.log.levels.ERROR)
        end
      end
    end
  end
  map("n", "[q", qf_jump("prev"), { desc = "Previous Trouble/Quickfix Item" })
  map("n", "]q", qf_jump("next"), { desc = "Next Trouble/Quickfix Item" })
end

local function todo_comments()
  require("todo-comments").setup({})
  local t = require("todo-comments")
  -- stylua: ignore start
  map("n", "]t", function() t.jump_next() end, { desc = "Next Todo Comment" })
  map("n", "[t", function() t.jump_prev() end, { desc = "Previous Todo Comment" })
  map("n", "<leader>xt", "<cmd>Trouble todo toggle<cr>", { desc = "Todo (Trouble)" })
  map("n", "<leader>xT", "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>", { desc = "Todo/Fix/Fixme (Trouble)" })
  map("n", "<leader>st", function() Snacks.picker.todo_comments() end, { desc = "Todo" })
  map("n", "<leader>sT", function() Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME" } }) end, { desc = "Todo/Fix/Fixme" })
  -- stylua: ignore end
end

local function grug_far()
  require("grug-far").setup({ headerMaxWidth = 80 })
  map({ "n", "x" }, "<leader>sr", function()
    local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
    require("grug-far").open({
      transient = true,
      prefills = { filesFilter = ext and ext ~= "" and "*." .. ext or nil },
    })
  end, { desc = "Search and Replace" })
end

local function persistence()
  require("persistence").setup({})
  local p = require("persistence")
  -- stylua: ignore start
  map("n", "<leader>qs", function() p.load() end, { desc = "Restore Session" })
  map("n", "<leader>qS", function() p.select() end, { desc = "Select Session" })
  map("n", "<leader>ql", function() p.load({ last = true }) end, { desc = "Restore Last Session" })
  map("n", "<leader>qd", function() p.stop() end, { desc = "Don't Save Current Session" })
  -- stylua: ignore end
end

local function neo_tree_setup()
  local function on_move(data)
    Snacks.rename.on_rename_file(data.source, data.destination)
  end
  local events = require("neo-tree.events")
  require("neo-tree").setup({
    sources = { "filesystem", "buffers", "git_status" },
    open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "Outline" },
    filesystem = {
      bind_to_cwd = false,
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true,
    },
    window = {
      mappings = {
        ["l"] = "open",
        ["h"] = "close_node",
        ["<space>"] = "none",
        ["Y"] = {
          function(state)
            vim.fn.setreg("+", state.tree:get_node():get_id(), "c")
          end,
          desc = "Copy Path to Clipboard",
        },
        ["O"] = {
          function(state)
            vim.ui.open(state.tree:get_node().path)
          end,
          desc = "Open with System Application",
        },
        ["P"] = { "toggle_preview", config = { use_float = false } },
      },
    },
    default_component_configs = {
      indent = {
        with_expanders = true,
        expander_collapsed = "",
        expander_expanded = "",
        expander_highlight = "NeoTreeExpander",
      },
      git_status = {
        symbols = {
          unstaged = "󰄱",
          staged = "󰄱",
        },
      },
    },
    event_handlers = {
      { event = events.FILE_MOVED, handler = on_move },
      { event = events.FILE_RENAMED, handler = on_move },
    },
  })
  vim.api.nvim_create_autocmd("TermClose", {
    pattern = "*lazygit",
    callback = function()
      if package.loaded["neo-tree.sources.git_status"] then
        require("neo-tree.sources.git_status").refresh()
      end
    end,
  })
end

-- neo-tree is set up on first use, or at startup when nvim opens a directory
local with_neo_tree = util.on_first_use(neo_tree_setup)

function M.neo_tree_now()
  with_neo_tree(function() end)()
end

local function neo_tree()
  local function exec(opts)
    return with_neo_tree(function()
      require("neo-tree.command").execute(opts)
    end)
  end
  map("n", "<leader>fe", function()
    exec({ toggle = true, dir = util.root.get() })()
  end, { desc = "Explorer NeoTree (Root Dir)" })
  map("n", "<leader>fE", function()
    exec({ toggle = true, dir = vim.uv.cwd() })()
  end, { desc = "Explorer NeoTree (cwd)" })
  map("n", "<leader>e", "<leader>fe", { desc = "Explorer NeoTree (Root Dir)", remap = true })
  map("n", "<leader>E", "<leader>fE", { desc = "Explorer NeoTree (cwd)", remap = true })
  map("n", "<leader>ge", exec({ source = "git_status", toggle = true }), { desc = "Git Explorer" })
  map("n", "<leader>be", exec({ source = "buffers", toggle = true }), { desc = "Buffer Explorer" })
end

-- runs during init.lua
function M.setup()
  pickers()
  neo_tree()
  local arg = vim.fn.argv(0) --[[@as string]]
  local stat = arg ~= "" and vim.uv.fs_stat(arg)
  if stat and stat.type == "directory" then
    M.neo_tree_now() -- hijack netrw for `nvim <dir>`
  end
end

-- runs after the UI is up
function M.later()
  which_key()
  flash()
  mini_ai()
  mini_pairs()
  trouble()
  todo_comments()
  grug_far()
  persistence()
end

return M
