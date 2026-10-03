-- Debugging (misw's own setup): nvim-dap + dap-ui + virtual text + dap-python
-- (debugpy bundled by build.sh, started through kide-python; tests via pytest).
local M = {}

function M.setup()
  local dap = require("dap")
  local dapui = require("dapui")
  local dap_python = require("dap-python")

  dapui.setup({})
  require("nvim-dap-virtual-text").setup({
    commented = true, -- show virtual text alongside comment
  })

  dap_python.setup(vim.fn.executable("kide-python") == 1 and "kide-python" or "python3")
  dap_python.test_runner = "pytest"

  vim.fn.sign_define("DapBreakpoint", {
    text = "",
    texthl = "DiagnosticSignError",
    linehl = "",
    numhl = "",
  })
  vim.fn.sign_define("DapBreakpointRejected", {
    text = "",
    texthl = "DiagnosticSignError",
    linehl = "",
    numhl = "",
  })
  vim.fn.sign_define("DapStopped", {
    text = "",
    texthl = "DiagnosticSignWarn",
    linehl = "Visual",
    numhl = "DiagnosticSignWarn",
  })

  -- open the UI when a session starts
  dap.listeners.after.event_initialized["dapui_config"] = function()
    dapui.open()
  end

  local map = vim.keymap.set
  -- stylua: ignore start
  map("n", "<leader>db", function() dap.toggle_breakpoint() end, { desc = "toggle breakpoint" })
  map("n", "<leader>dc", function() dap.continue() end, { desc = "continue / start" })
  map("n", "<leader>do", function() dap.step_over() end, { desc = "step over" })
  map("n", "<leader>di", function() dap.step_into() end, { desc = "step into" })
  map("n", "<leader>dO", function() dap.step_out() end, { desc = "step out" })
  map("n", "<leader>dq", function() dap.terminate() end, { desc = "quit" })
  map("n", "<leader>du", function() dapui.toggle() end, { desc = "toggle UI" })
  map("n", "<leader>dt", function() dap_python.test_method() end, { desc = "test method" })
  map("n", "<leader>dT", function() dap_python.test_class() end, { desc = "test class" })
  -- stylua: ignore end
end

return M
