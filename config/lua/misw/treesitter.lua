-- Treesitter (nvim-treesitter main branch): parsers, highlight, indent, folds,
-- and textobject motions ]f [f ]c [c ]a [a (+ uppercase = end).
-- Parsers are compiled from vendored grammar sources by build-ide.sh into
-- site/parser (list: manifest/parsers.txt); nvim-treesitter never installs.
local util = require("misw.util")
local M = {}

local installed, queries = nil, {}

local function refresh()
  installed, queries = {}, {}
  for _, lang in ipairs(require("nvim-treesitter").get_installed("parsers")) do
    installed[lang] = true
  end
end

-- is there a parser (and optionally a query) for this filetype / buffer?
local function have(what, query)
  what = what or vim.api.nvim_get_current_buf()
  what = type(what) == "number" and vim.bo[what].filetype or what --[[@as string]]
  local lang = vim.treesitter.language.get_lang(what)
  if lang == nil or not (installed or {})[lang] then
    return false
  end
  if query then
    local key = lang .. ":" .. query
    if queries[key] == nil then
      queries[key] = vim.treesitter.query.get(lang, query) ~= nil
    end
    return queries[key]
  end
  return true
end

function M.foldexpr()
  return have(nil, "folds") and vim.treesitter.foldexpr() or "0"
end

function M.indentexpr()
  return have(nil, "indents") and require("nvim-treesitter").indentexpr() or -1
end

local moves = {
  goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
  goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
  goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
  goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
}

local function attach_moves(buf)
  if not have(vim.bo[buf].filetype, "textobjects") then
    return
  end
  for method, keymaps in pairs(moves) do
    for key, query in pairs(keymaps) do
      local desc = query:gsub("@", ""):gsub("%..*", "")
      desc = desc:sub(1, 1):upper() .. desc:sub(2)
      desc = (key:sub(1, 1) == "[" and "Prev " or "Next ") .. desc
      desc = desc .. (key:sub(2, 2) == key:sub(2, 2):upper() and " End" or " Start")
      -- in diff mode ]c/[c stay "next/prev change"
      if not (vim.wo.diff and key:find("[cC]")) then
        vim.keymap.set({ "n", "x", "o" }, key, function()
          require("nvim-treesitter-textobjects.move")[method](query, "textobjects")
        end, { buffer = buf, desc = desc, silent = true })
      end
    end
  end
end

function M.setup()
  require("nvim-treesitter").setup({ install_dir = vim.g.kide_site })
  require("nvim-treesitter-textobjects").setup({ move = { set_jumps = true } })
  refresh()

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("misw_treesitter", { clear = true }),
    callback = function(ev)
      if not have(ev.match) then
        return
      end
      if have(ev.match, "highlights") then
        pcall(vim.treesitter.start, ev.buf)
      end
      if have(ev.match, "indents") then
        util.set_default("indentexpr", "v:lua.require'misw.treesitter'.indentexpr()")
      end
      if have(ev.match, "folds") then
        if util.set_default("foldmethod", "expr") then
          util.set_default("foldexpr", "v:lua.require'misw.treesitter'.foldexpr()")
        end
      end
      attach_moves(ev.buf)
    end,
  })
end

return M
