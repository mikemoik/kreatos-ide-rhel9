-- C/C++ and CMake (kreatos-ide-rhel9 only). The tools come from RHEL9 itself:
-- clangd, clang-format, clang-tidy (clang-tools-extra), gdb, lldb-dap (lldb).
-- Bundled here: neocmakelsp, clangd_extensions.nvim, cmake-tools.nvim,
-- neotest + neotest-gtest (GoogleTest), neogen (Doxygen comments) and the
-- cpp/cmake/make/doxygen parsers. LSP servers and debug adapters whose
-- binary is missing are skipped (see misw.lsp and misw.dap).
local M = {}

-- clangd flags as in LazyVim's clangd extra
M.clangd_cmd = {
  "clangd",
  "--background-index",
  "--clang-tidy",
  "--header-insertion=iwyu",
  "--completion-style=detailed",
  "--function-arg-placeholders",
  "--fallback-style=llvm",
}

-- program to debug: ask, starting from the cmake-tools build dir or cwd
function M.pick_program()
  return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
end

-- nvim-dap adapters + launch/attach configs for c and cpp; gdb first (default)
function M.dap()
  local dap = require("dap")
  local configs = {}
  if vim.fn.executable("gdb") == 1 then
    -- gdb >= 14 speaks DAP itself (RHEL9: gdb 16)
    dap.adapters.gdb = {
      type = "executable",
      command = "gdb",
      args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
    }
    vim.list_extend(configs, {
      {
        name = "Launch (gdb)",
        type = "gdb",
        request = "launch",
        program = M.pick_program,
        cwd = "${workspaceFolder}",
        stopAtBeginningOfMainSubprogram = false,
      },
      {
        name = "Attach to process (gdb)",
        type = "gdb",
        request = "attach",
        pid = require("dap.utils").pick_process,
        cwd = "${workspaceFolder}",
      },
    })
  end
  if vim.fn.executable("lldb-dap") == 1 then
    dap.adapters["lldb-dap"] = { type = "executable", command = "lldb-dap", name = "lldb-dap" }
    vim.list_extend(configs, {
      {
        name = "Launch (lldb-dap)",
        type = "lldb-dap",
        request = "launch",
        program = M.pick_program,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        -- lldb refuses to launch when it cannot switch off ASLR (personality()
        -- is blocked in containers: podman, toolbox, docker); gdb just warns
        disableASLR = false,
        args = {},
      },
      {
        name = "Attach to process (lldb-dap)",
        type = "lldb-dap",
        request = "attach",
        pid = require("dap.utils").pick_process,
      },
    })
  end
  dap.configurations.c = configs
  dap.configurations.cpp = configs
end

function M.setup()
  vim.lsp.config("clangd", {
    cmd = M.clangd_cmd,
    init_options = { usePlaceholders = true, completeUnimported = true, clangdFileStatus = true },
  })

  require("clangd_extensions").setup({})
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("misw_cpp", { clear = true }),
    pattern = { "c", "cpp", "objc", "objcpp", "cuda" },
    callback = function(ev)
      local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
      end
      map("<leader>ch", "<cmd>LspClangdSwitchSourceHeader<cr>", "Switch Source/Header (C/C++)")
      map("<leader>cH", "<cmd>ClangdTypeHierarchy<cr>", "Type Hierarchy (C/C++)")
      map("<leader>cs", "<cmd>ClangdSymbolInfo<cr>", "Symbol Info (C/C++)")
    end,
  })

  -- cmake-tools: build dirs per build type, compile_commands.json linked into
  -- the project root for clangd, debugging through gdb (its default is codelldb)
  require("cmake-tools").setup({
    cmake_build_directory = "build/${variant:buildType}",
    cmake_soft_link_compile_commands = true,
    cmake_dap_configuration = { name = "cpp", type = "gdb", request = "launch" },
  })
  local map = vim.keymap.set
  map("n", "<leader>mg", "<cmd>CMakeGenerate<cr>", { desc = "Generate (configure)" })
  map("n", "<leader>mb", "<cmd>CMakeBuild<cr>", { desc = "Build" })
  map("n", "<leader>mr", "<cmd>CMakeRun<cr>", { desc = "Run target" })
  map("n", "<leader>md", "<cmd>CMakeDebug<cr>", { desc = "Debug target" })
  map("n", "<leader>mt", "<cmd>CMakeSelectLaunchTarget<cr>", { desc = "Select launch target" })
  map("n", "<leader>mT", "<cmd>CMakeSelectBuildTarget<cr>", { desc = "Select build target" })
  map("n", "<leader>ms", "<cmd>CMakeSelectBuildType<cr>", { desc = "Select build type" })
  map("n", "<leader>mc", "<cmd>CMakeClean<cr>", { desc = "Clean" })

  -- neotest with the GoogleTest adapter; debugging a test goes through gdb
  -- (the adapter's default is codelldb). Keys as in LazyVim's test extra.
  require("neotest").setup({
    adapters = { require("neotest-gtest").setup({ debug_adapter = "gdb" }) },
  })
  local nt = function(fn)
    return function()
      fn(require("neotest"))
    end
  end
  -- stylua: ignore start
  map("n", "<leader>tt", nt(function(n) n.run.run(vim.fn.expand("%")) end), { desc = "Run File" })
  map("n", "<leader>tT", nt(function(n) n.run.run(vim.uv.cwd()) end), { desc = "Run All Test Files" })
  map("n", "<leader>tr", nt(function(n) n.run.run() end), { desc = "Run Nearest" })
  map("n", "<leader>tl", nt(function(n) n.run.run_last() end), { desc = "Run Last" })
  map("n", "<leader>td", nt(function(n) n.run.run({ strategy = "dap" }) end), { desc = "Debug Nearest" })
  map("n", "<leader>ts", nt(function(n) n.summary.toggle() end), { desc = "Toggle Summary" })
  map("n", "<leader>to", nt(function(n) n.output.open({ enter = true, auto_close = true }) end), { desc = "Show Output" })
  map("n", "<leader>tO", nt(function(n) n.output_panel.toggle() end), { desc = "Toggle Output Panel" })
  map("n", "<leader>tS", nt(function(n) n.run.stop() end), { desc = "Stop" })
  -- stylua: ignore end

  -- neogen: Doxygen (C/C++) or docstring (Python, …) skeleton for the
  -- function/class under the cursor, filled in with nvim's snippet engine
  require("neogen").setup({ snippet_engine = "nvim" })
  map("n", "<leader>cn", function()
    require("neogen").generate()
  end, { desc = "Generate Annotations (Neogen)" })
end

return M
