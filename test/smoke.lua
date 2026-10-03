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

  -- debugging: a session started through nvim-dap stops at a breakpoint
  local dap = require("dap")
  local function debug_check(name, buf, line, config)
    require("dap.breakpoints").clear()
    require("dap.breakpoints").set({}, buf, line)
    local stopped_line
    dap.listeners.after.event_stopped["smoke"] = function(session, body)
      session:request("stackTrace", { threadId = body.threadId }, function(_, resp)
        stopped_line = resp and resp.stackFrames[1].line
      end)
    end
    config = vim.tbl_extend("force", { name = "smoke" }, config)
    local dok, derr = pcall(dap.run, config)
    local stopped = dok and vim.wait(60000, function()
      return stopped_line ~= nil
    end, 200)
    check(name .. " stops at breakpoint", stopped and stopped_line == line, derr or tostring(stopped_line))
    pcall(dap.terminate)
    vim.wait(10000, function()
      return dap.session() == nil
    end, 100)
  end
  local pybuf = open_in_project("dap", "pyproject.toml", "py", { "x = 1", "y = x + 1", "print(y)" })
  debug_check("debugpy", pybuf, 2, { type = "python", request = "launch", program = vim.api.nvim_buf_get_name(pybuf) })

  -- C/C++: a CMake project, configured + built with the RHEL toolchain
  local cpp = dir .. "/cpp"
  vim.fn.mkdir(cpp, "p")
  vim.fn.writefile({
    "cmake_minimum_required(VERSION 3.16)",
    "project(smoke CXX)",
    "add_executable(app main.cpp)",
  }, cpp .. "/CMakeLists.txt")
  vim.fn.writefile({
    "#include <cstdio>",
    "int main() {",
    "  int x = 1;",
    "  int y = x + 1;",
    '  std::printf("%d\\n", y);',
    "  return 0;",
    "}",
  }, cpp .. "/main.cpp")
  vim.fn.writefile({ "int broken() {", '  int x = "not an int";', "  return x;", "}" }, cpp .. "/broken.cpp")
  local cmake_out = vim.fn.system({ "sh", "-c", ("cd %s && cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug "
    .. "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null && cmake --build build >/dev/null "
    .. "&& ln -s build/compile_commands.json ."):format(cpp) })
  check("cmake configure + build", vim.v.shell_error == 0, cmake_out)
  local app = cpp .. "/build/app"

  vim.cmd.edit(cpp .. "/broken.cpp")
  local cbuf = vim.api.nvim_get_current_buf()
  check("lsp clangd attaches", wait_client(cbuf, "clangd"))
  check("lsp clangd reports diagnostics", vim.wait(60000, function()
    for _, d in ipairs(vim.diagnostic.get(cbuf)) do
      if d.severity == vim.diagnostic.severity.ERROR then
        return true
      end
    end
  end, 200), vim.inspect(vim.diagnostic.get(cbuf)))

  vim.cmd.edit(cpp .. "/CMakeLists.txt")
  check("lsp neocmake attaches", wait_client(vim.api.nvim_get_current_buf(), "neocmake"))

  local fbuf = open_in_project("fmt_cpp", "marker.txt", "cpp", { "int main(){return 0;}" })
  local fok, ferr = pcall(require("conform").format, { bufnr = fbuf })
  local got = vim.api.nvim_buf_get_lines(fbuf, 0, 1, false)[1]
  check("format clang-format", fok and got == "int main() { return 0; }", ferr or got)

  vim.cmd.edit(cpp .. "/main.cpp")
  local mbuf = vim.api.nvim_get_current_buf()
  debug_check("gdb (dap)", mbuf, 4, { type = "gdb", request = "launch", program = app, cwd = cpp })
  debug_check("lldb-dap", mbuf, 4, {
    type = "lldb-dap",
    request = "launch",
    program = app,
    cwd = cpp,
    disableASLR = false, -- as in misw.cpp: the test runs in a container
  })

  local cmok, cmerr = pcall(function()
    assert(package.loaded["cmake-tools"], "cmake-tools not loaded")
    assert(vim.fn.exists(":CMakeBuild") == 2, ":CMakeBuild missing")
    assert(vim.fn.exists(":ClangdTypeHierarchy") == 2, ":ClangdTypeHierarchy missing")
  end)
  check("cmake-tools + clangd_extensions loaded", cmok, cmerr)

  local ntok, nterr = pcall(function()
    local names = vim.tbl_map(function(a)
      return a.name
    end, require("neotest.config").adapters)
    assert(vim.tbl_contains(names, "neotest-gtest"), "adapters: " .. vim.inspect(names))
  end)
  check("neotest with gtest adapter", ntok, nterr)

  -- neogen writes a Doxygen skeleton above a C++ function
  local nbuf = open_in_project("neogen", "marker.txt", "cpp", { "int add(int a, int b) { return a + b; }" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  local gok, gerr = pcall(require("neogen").generate, { type = "func" })
  vim.cmd.stopinsert()
  local text = table.concat(vim.api.nvim_buf_get_lines(nbuf, 0, -1, false), "\n")
  check("neogen doxygen comment", gok and text:find("@param a", 1, true) ~= nil, gerr or text)

  -- the bundled CLI tools run and report the pinned version
  local versions = {}
  for _, row in ipairs(read_tsv(src .. "/manifest/tools.tsv")) do
    versions[row[1]] = row[4]:gsub("^v", "")
  end
  for _, t in ipairs({ { "fd", "fd" }, { "fzf", "fzf" }, { "lazygit", "lazygit" }, { "yazi", "yazi" }, { "ya", "yazi" } }) do
    local res = vim.system({ t[1], "--version" }, { text = true }):wait()
    local version = (res.stdout or "") .. (res.stderr or "")
    check(t[1] .. " " .. versions[t[2]], res.code == 0 and version:find(versions[t[2]], 1, true) ~= nil, version)
  end
  local found = vim.fn.system({ "fd", "--type", "f", "CMakeLists", src .. "/test/proj/customers-cpp" })
  check("fd finds files", vim.v.shell_error == 0 and found:find("app/CMakeLists.txt", 1, true) ~= nil, found)
  local picked = vim.fn.system({ "fzf", "--filter", "cstdb" }, "customer_db.cpp\nreport.cpp\n")
  check("fzf filters", vim.trim(picked) == "customer_db.cpp", picked)

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
