-- Options: LazyVim's defaults plus misw's own (relativenumber off, no swapfile).
local util = require("misw.util")

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.autoformat = true
vim.g.snacks_animate = true
vim.g.markdown_recommended_style = 0

-- runtime plugins nobody uses (lazy.nvim disabled these)
for _, p in ipairs({ "gzip", "tarPlugin", "tar", "zipPlugin", "zip", "tohtml", "tutor" }) do
  vim.g["loaded_" .. p] = 1
end
-- no spell checking in kide; no spell file downloads either (their
-- "Download? [y/N]" prompt ate the next keys)
vim.g.loaded_spellfile_plugin = 1

-- snacks writes lazygit's theme into the cache dir without creating it (a new
-- container has no ~/.cache: <leader>gg failed with E482)
vim.fn.mkdir(vim.fn.stdpath("cache"), "p")

local opt = vim.opt
opt.autowrite = true
-- clipboard provider detection is slow: set it after startup (see init.lua)
opt.clipboard = ""
opt.completeopt = "menu,menuone,noselect"
opt.conceallevel = 2
opt.confirm = true
opt.cursorline = true
opt.expandtab = true
opt.fillchars = {
  foldopen = "",
  foldclose = "",
  fold = " ",
  foldsep = " ",
  diff = "╱",
  eob = " ",
}
opt.foldlevel = 99
opt.foldmethod = "indent"
opt.foldtext = ""
opt.formatexpr = "v:lua.require'conform'.formatexpr()"
opt.formatoptions = "jcroqlnt"
opt.grepformat = "%f:%l:%c:%m"
opt.grepprg = "rg --vimgrep"
opt.ignorecase = true
opt.inccommand = "nosplit"
opt.jumpoptions = "view"
opt.laststatus = 3
opt.linebreak = true
opt.list = true
opt.mouse = "a"
opt.number = true
opt.pumblend = 10
opt.pumheight = 10
opt.relativenumber = false
opt.ruler = false
opt.scrolloff = 4
opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }
opt.shiftround = true
opt.shiftwidth = 2
opt.shortmess:append({ W = true, I = true, c = true, C = true })
opt.showmode = false
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.smartcase = true
opt.smartindent = true
opt.smoothscroll = true
opt.splitbelow = true
opt.splitkeep = "screen"
opt.splitright = true
opt.statuscolumn = [[%!v:lua.require'misw.util'.statuscolumn()]]
opt.swapfile = false
opt.tabstop = 2
opt.termguicolors = true
opt.timeoutlen = 300
opt.undofile = true
opt.undolevels = 10000
opt.updatetime = 200
opt.virtualedit = "block"
opt.wildmode = "longest:full,full"
opt.winminwidth = 5
opt.wrap = false

-- remembered so set_default() can tell "untouched" from "set by a plugin"
for _, o in ipairs({ "indentexpr", "foldmethod", "foldexpr" }) do
  util.global_options[o] = vim.o[o]
end
