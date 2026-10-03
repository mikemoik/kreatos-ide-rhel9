-- Smoke test, run inside kide after startup:
--   KIDE_SRC=<repo> kide --headless "+lua dofile('<repo>/test/smoke.lua')"
-- Exits 0 when every check passes, 1 otherwise.
local src = assert(vim.env.KIDE_SRC, "KIDE_SRC not set")
local failures, passes = {}, 0

-- print() in headless mode goes to the message area, not reliably to stdout
local function out(line)
  io.stdout:write(line, "\n")
end

local function check(name, ok, detail)
  if ok then
    passes = passes + 1
    out("ok    " .. name)
  else
    failures[#failures + 1] = name
    out("FAIL  " .. name .. (detail and (": " .. tostring(detail)) or ""))
  end
end

local function read_tsv(path)
  local rows = {}
  for line in io.lines(path) do
    if line ~= "" and not line:match("^#") then
      rows[#rows + 1] = vim.split(line, "\t")
    end
  end
  return rows
end

local function run()
  -- startup must be clean
  local msgs = vim.api.nvim_exec2("messages", { output = true }).output
  check("startup without errors", not (msgs:match("E%d+:") or msgs:match("[Ee]rror")), msgs)

  -- every vendored plugin is on the runtimepath
  local rtp = vim.o.rtp
  for _, row in ipairs(read_tsv(src .. "/manifest/plugins.tsv")) do
    check("plugin " .. row[1], rtp:find("/pack/vendor/opt/" .. row[1], 1, true) ~= nil)
  end

  -- every parser loads and its highlights query compiles (query-only
  -- languages like ecma are pulled in through `; inherits:` by these)
  for _, row in ipairs(read_tsv(src .. "/manifest/parsers.lock.tsv")) do
    local lang = row[1]
    if row[2] ~= "-" then
      local ok, err = pcall(vim.treesitter.language.add, lang)
      check("parser " .. lang, ok, err)
      local qok, qerr = pcall(vim.treesitter.query.get, lang, "highlights")
      check("highlights query " .. lang, qok, qerr)
    end
  end

  -- treesitter highlighting attaches to real files
  local samples = { lua = "local x = 1\n", py = "x = 1\n", sh = "x=1\n", ts = "const x: number = 1\n" }
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for ext, text in pairs(samples) do
    local file = dir .. "/sample." .. ext
    vim.fn.writefile(vim.split(text, "\n"), file)
    vim.cmd.edit(file)
    local buf = vim.api.nvim_get_current_buf()
    check("treesitter highlight ." .. ext, vim.treesitter.highlighter.active[buf] ~= nil, vim.bo[buf].filetype)
  end

  -- LSP servers attach and answer (a diagnostic proves the server works).
  -- Each case is a small project: servers stay quiet on loose files.
  local lsp_cases = {
    { server = "lua_ls", marker = ".luarc.json", ext = "lua", text = "print(undefined_global_x)\n" },
  }
  for _, case in ipairs(lsp_cases) do
    local project = ("%s/lsp_%s"):format(dir, case.server)
    vim.fn.mkdir(project, "p")
    vim.fn.writefile({ "{}" }, project .. "/" .. case.marker)
    local file = ("%s/main.%s"):format(project, case.ext)
    vim.fn.writefile(vim.split(case.text, "\n"), file)
    vim.cmd.edit(file)
    local buf = vim.api.nvim_get_current_buf()
    local attached = vim.wait(20000, function()
      return #vim.lsp.get_clients({ bufnr = buf, name = case.server }) > 0
    end, 100)
    check("lsp " .. case.server .. " attaches", attached)
    local diagnosed = attached and vim.wait(30000, function()
      return #vim.diagnostic.get(buf) > 0
    end, 200)
    check("lsp " .. case.server .. " reports diagnostics", diagnosed)
  end

  -- formatters run through conform
  local fmt_cases = {
    { formatter = "stylua", ext = "lua", text = "local   x={1,2}", want = "local x = { 1, 2 }" },
  }
  for _, case in ipairs(fmt_cases) do
    local file = ("%s/fmt_%s.%s"):format(dir, case.formatter, case.ext)
    vim.fn.writefile({ case.text }, file)
    vim.cmd.edit(file)
    local buf = vim.api.nvim_get_current_buf()
    local fok, ferr = pcall(require("conform").format, { bufnr = buf, formatters = { case.formatter } })
    local got = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    check("format " .. case.formatter, fok and got == case.want, ferr or got)
  end

  -- completion engine starts with the Lua fuzzy matcher
  vim.api.nvim_exec_autocmds("InsertEnter", {})
  local ok, err = pcall(function()
    assert(package.loaded["blink.cmp"], "blink.cmp not loaded")
    assert(require("blink.cmp.config").fuzzy.implementation == "lua", "fuzzy implementation is not lua")
  end)
  check("blink.cmp (lua matcher)", ok, err)

  out(("\n%d passed, %d failed"):format(passes, #failures))
  vim.cmd(#failures == 0 and "qall!" or "cquit 1")
end

-- after util.later() work (VimEnter) has run
vim.defer_fn(function()
  local ok, err = pcall(run)
  if not ok then
    out("FAIL  smoke test crashed: " .. tostring(err))
    vim.cmd("cquit 1")
  end
end, 1000)
