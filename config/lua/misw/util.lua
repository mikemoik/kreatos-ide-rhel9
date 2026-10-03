-- Shared helpers: the parts of LazyVim's util that the config relies on
-- (root detection, safe buffer defaults, autoformat state, lualine pieces).
-- Ported from LazyVim (Apache-2.0), trimmed to what is used here.
local M = {}

M.icons = require("misw.icons").icons
M.kind_filter = require("misw.icons").kind_filter

-- Run fn once the UI is up (LazyVim's "VeryLazy"); headless runs it on VimEnter.
function M.later(fn)
  local event = #vim.api.nvim_list_uis() > 0 and "UIEnter" or "VimEnter"
  if vim.v.vim_did_enter == 1 then
    return vim.schedule(fn)
  end
  vim.api.nvim_create_autocmd(event, { once = true, callback = vim.schedule_wrap(fn) })
end

-- Wrap a function so `setup` runs exactly once before its first call.
function M.on_first_use(setup)
  local done = false
  return function(fn)
    return function(...)
      if not done then
        done = true
        setup()
      end
      return fn(...)
    end
  end
end

-- 'statuscolumn' expression (snacks draws signs, numbers, folds)
function M.statuscolumn()
  return package.loaded.snacks and require("snacks.statuscolumn").get() or ""
end

---------------------------------------------------------------- root ----

M.root = {}
M.root.spec = { "lsp", { ".git", "lua" }, "cwd" }
M.root.cache = {}

local function realpath(path)
  if path == "" or path == nil then
    return nil
  end
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function bufpath(buf)
  return realpath(vim.api.nvim_buf_get_name(buf))
end

local detectors = {}

function detectors.cwd()
  return { vim.uv.cwd() }
end

function detectors.lsp(buf)
  local path = bufpath(buf)
  if not path then
    return {}
  end
  local roots = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    for _, ws in ipairs(client.config.workspace_folders or {}) do
      roots[#roots + 1] = vim.uri_to_fname(ws.uri)
    end
    if client.root_dir then
      roots[#roots + 1] = client.root_dir
    end
  end
  return vim.tbl_filter(function(p)
    p = realpath(p)
    return p and path:find(p, 1, true) == 1
  end, roots)
end

function detectors.pattern(buf, patterns)
  local path = bufpath(buf) or vim.uv.cwd()
  local found = vim.fs.find(function(name)
    for _, p in ipairs(patterns) do
      if name == p or (p:sub(1, 1) == "*" and name:find(vim.pesc(p:sub(2)) .. "$")) then
        return true
      end
    end
    return false
  end, { path = path, upward = true })[1]
  return found and { vim.fs.dirname(found) } or {}
end

local function detect(buf)
  for _, spec in ipairs(M.root.spec) do
    local paths = type(spec) == "table" and detectors.pattern(buf, spec) or detectors[spec](buf)
    local roots = {}
    for _, p in ipairs(paths) do
      local pp = realpath(p)
      if pp and not vim.tbl_contains(roots, pp) then
        roots[#roots + 1] = pp
      end
    end
    table.sort(roots, function(a, b)
      return #a > #b
    end)
    if #roots > 0 then
      return roots[1]
    end
  end
end

---@param opts? {buf?: integer}
function M.root.get(opts)
  local buf = opts and opts.buf or vim.api.nvim_get_current_buf()
  local ret = M.root.cache[buf]
  if not ret then
    ret = detect(buf) or vim.uv.cwd()
    M.root.cache[buf] = ret
  end
  return ret
end

function M.root.cwd()
  return realpath(vim.uv.cwd()) or ""
end

function M.root.git()
  local root = M.root.get()
  local git = vim.fs.find(".git", { path = root, upward = true })[1]
  return git and vim.fn.fnamemodify(git, ":h") or root
end

vim.api.nvim_create_autocmd({ "LspAttach", "BufWritePost", "DirChanged", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("misw_root_cache", { clear = true }),
  callback = function(ev)
    M.root.cache[ev.buf] = nil
  end,
})

------------------------------------------------------- safe defaults ----

-- Global values captured before plugins/ftplugins touch them.
M.global_options = {}
local defaults = {}

-- Set a buffer-local option only if nothing but $VIMRUNTIME changed it,
-- so treesitter indent/folds win over runtime ftplugins but not over plugins.
function M.set_default(option, value)
  local l = vim.api.nvim_get_option_value(option, { scope = "local" })
  local g = M.global_options[option] or vim.api.nvim_get_option_value(option, { scope = "global" })
  defaults[("%s=%s"):format(option, value)] = true
  if l ~= g and not defaults[("%s=%s"):format(option, l)] then
    local info = vim.api.nvim_get_option_info2(option, { scope = "local" })
    local scripts = vim.tbl_filter(function(e)
      return e.sid == info.last_set_sid
    end, vim.fn.getscriptinfo())
    if not (#scripts == 1 and vim.startswith(scripts[1].name, vim.fn.expand("$VIMRUNTIME"))) then
      return false
    end
  end
  vim.api.nvim_set_option_value(option, value, { scope = "local" })
  return true
end

---------------------------------------------------------- autoformat ----

M.format = {}

function M.format.enabled(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local baf = vim.b[buf].autoformat
  if baf ~= nil then
    return baf
  end
  return vim.g.autoformat == nil or vim.g.autoformat
end

function M.format.enable(enable, buf)
  if buf then
    vim.b.autoformat = enable
  else
    vim.g.autoformat = enable
    vim.b.autoformat = nil
  end
end

---@param opts? {buf?: integer, force?: boolean}
function M.format.run(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if not (opts.force or M.format.enabled(buf)) then
    return
  end
  -- conform runs its formatters, or the LSP formatter when it has none (ruff for Python)
  require("conform").format({ bufnr = buf })
end

function M.format.snacks_toggle(buf)
  return Snacks.toggle({
    name = "Auto Format (" .. (buf and "Buffer" or "Global") .. ")",
    get = function()
      if not buf then
        return vim.g.autoformat == nil or vim.g.autoformat
      end
      return M.format.enabled()
    end,
    set = function(state)
      M.format.enable(state, buf)
    end,
  })
end

------------------------------------------------------------- lualine ----

M.lualine = {}

local function lualine_format(component, text, hl_group)
  text = text:gsub("%%", "%%%%")
  if not hl_group or hl_group == "" then
    return text
  end
  component.hl_cache = component.hl_cache or {}
  local lualine_hl_group = component.hl_cache[hl_group]
  if not lualine_hl_group then
    local utils = require("lualine.utils.utils")
    local gui = vim.tbl_filter(function(x)
      return x
    end, {
      utils.extract_highlight_colors(hl_group, "bold") and "bold",
      utils.extract_highlight_colors(hl_group, "italic") and "italic",
    })
    lualine_hl_group = component:create_hl({
      fg = utils.extract_highlight_colors(hl_group, "fg"),
      gui = #gui > 0 and table.concat(gui, ",") or nil,
    }, "LV_" .. hl_group)
    component.hl_cache[hl_group] = lualine_hl_group
  end
  return component:format_hl(lualine_hl_group) .. text .. component:get_default_hl()
end

function M.lualine.pretty_path()
  local opts = {
    modified_hl = "MatchParen",
    directory_hl = "",
    filename_hl = "Bold",
    modified_sign = "",
    readonly_icon = " 󰌾 ",
    length = 3,
  }
  return function(self)
    local path = vim.fn.expand("%:p") --[[@as string]]
    if path == "" then
      return ""
    end
    path = vim.fs.normalize(path)
    local root = M.root.get()
    local cwd = M.root.cwd()
    if path:find(cwd, 1, true) == 1 then
      path = path:sub(#cwd + 2)
    elseif path:find(root, 1, true) == 1 then
      path = path:sub(#root + 2)
    end
    local parts = vim.split(path, "[\\/]")
    if #parts > opts.length then
      parts = { parts[1], "…", unpack(parts, #parts - opts.length + 2, #parts) }
    end
    if opts.modified_hl and vim.bo.modified then
      parts[#parts] = parts[#parts] .. opts.modified_sign
      parts[#parts] = lualine_format(self, parts[#parts], opts.modified_hl)
    else
      parts[#parts] = lualine_format(self, parts[#parts], opts.filename_hl)
    end
    local dir = ""
    if #parts > 1 then
      dir = table.concat({ unpack(parts, 1, #parts - 1) }, "/")
      dir = lualine_format(self, dir .. "/", opts.directory_hl)
    end
    local readonly = ""
    if vim.bo.readonly then
      readonly = lualine_format(self, opts.readonly_icon, opts.modified_hl)
    end
    return dir .. parts[#parts] .. readonly
  end
end

function M.lualine.root_dir()
  local function get()
    local cwd = M.root.cwd()
    local root = M.root.get()
    local name = vim.fs.basename(root)
    if root == cwd then
      return nil -- root is cwd: not shown
    end
    return name
  end
  return {
    function()
      return "󱉭  " .. get()
    end,
    cond = function()
      return type(get()) == "string"
    end,
    color = function()
      return { fg = Snacks.util.color("Special") }
    end,
  }
end

return M
