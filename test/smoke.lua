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

  -- a small project per case: servers stay quiet on loose files
  local function open_in_project(name, marker, ext, lines)
    local project = ("%s/%s"):format(dir, name)
    vim.fn.mkdir(project, "p")
    vim.fn.writefile({ marker == "pyproject.toml" and "[project]" or "{}" }, project .. "/" .. marker)
    local file = ("%s/main.%s"):format(project, ext)
    vim.fn.writefile(lines, file)
    vim.cmd.edit(file)
    return vim.api.nvim_get_current_buf()
  end
  local function wait_client(buf, server)
    return vim.wait(20000, function()
      return #vim.lsp.get_clients({ bufnr = buf, name = server }) > 0
    end, 100)
  end

  -- LSP servers attach and answer: each must report its own diagnostic
  -- (matched on the diagnostic's source)
  local lsp_cases = {
    { server = "ruff", source = "ruff", marker = "pyproject.toml", ext = "py", text = { "import os" } },
    { server = "ty", source = "ty", marker = "pyproject.toml", ext = "py", text = { 'x: int = "not an int"' } },
  }
  for _, case in ipairs(lsp_cases) do
    local buf = open_in_project("lsp_" .. case.server, case.marker, case.ext, case.text)
    local attached = wait_client(buf, case.server)
    check("lsp " .. case.server .. " attaches", attached)
    local diagnosed = attached
      and vim.wait(30000, function()
        for _, d in ipairs(vim.diagnostic.get(buf)) do
          if (d.source or ""):lower():find(case.source, 1, true) then
            return true
          end
        end
      end, 200)
    check("lsp " .. case.server .. " reports diagnostics", diagnosed, vim.inspect(vim.diagnostic.get(buf)))
  end

  -- formatting the way format-on-save does it: conform's formatter for the
  -- filetype, else the LSP formatter (ruff)
  local fmt_cases = {
    { name = "ruff (lsp)", lsp = "ruff", marker = "pyproject.toml", ext = "py", text = "x=[1,2]", want = "x = [1, 2]" },
    { name = "shfmt", marker = "marker.txt", ext = "sh", text = "if true;then echo hi;fi", want = "if true; then echo hi; fi" },
  }
  for i, case in ipairs(fmt_cases) do
    local buf = open_in_project("fmt_" .. i, case.marker, case.ext, { case.text })
    if case.lsp then
      wait_client(buf, case.lsp)
    end
    local fok, ferr = pcall(require("conform").format, { bufnr = buf })
    local got = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    check("format " .. case.name, fok and got == case.want, ferr or got)
  end

  -- debugging: nvim-dap-python + the bundled debugpy stop at a breakpoint
  local dap = require("dap")
  local dbuf = open_in_project("dap", "pyproject.toml", "py", { "x = 1", "y = x + 1", "print(y)" })
  require("dap.breakpoints").set({}, dbuf, 2)
  local stopped_line
  dap.listeners.after.event_stopped["smoke"] = function(session, body)
    session:request("stackTrace", { threadId = body.threadId }, function(_, resp)
      stopped_line = resp and resp.stackFrames[1].line
    end)
  end
  local dok, derr = pcall(dap.run, {
    type = "python",
    request = "launch",
    name = "smoke",
    program = vim.api.nvim_buf_get_name(dbuf),
  })
  local stopped = dok and vim.wait(30000, function()
    return stopped_line ~= nil
  end, 200)
  check("debugpy stops at breakpoint", stopped and stopped_line == 2, derr or tostring(stopped_line))
  pcall(dap.terminate)
  vim.wait(5000, function()
    return dap.session() == nil
  end, 100)

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
