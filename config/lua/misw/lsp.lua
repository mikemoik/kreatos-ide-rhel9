-- LSP: servers built from source by build.sh (ruff, ty),
-- configs from nvim-lspconfig, native vim.lsp.enable. A server whose binary is
-- not on PATH is skipped. Keymaps are set per buffer for what the server
-- supports.
local util = require("misw.util")
local icons = util.icons
local M = {}

M.servers = { "ty", "ruff" }

local function keys()
  local P = function(name, opts)
    return function()
      Snacks.picker[name](opts)
    end
  end
  local words = function(count, cycle)
    return function()
      Snacks.words.jump(count * vim.v.count1, cycle)
    end
  end
  local function source_action()
    vim.lsp.buf.code_action({ apply = true, context = { only = { "source" }, diagnostics = {} } })
  end
  -- { lhs, rhs, desc, has = method(s), mode = ..., words = only when snacks.words is on }
  return {
    { "<leader>cl", P("lsp_config"), "Lsp Info" },
    { "gd", P("lsp_definitions"), "Goto Definition", has = "definition" },
    { "gr", P("lsp_references"), "References", nowait = true },
    { "gI", P("lsp_implementations"), "Goto Implementation" },
    { "gy", P("lsp_type_definitions"), "Goto T[y]pe Definition" },
    { "gD", vim.lsp.buf.declaration, "Goto Declaration" },
    { "K", vim.lsp.buf.hover, "Hover" },
    { "gK", vim.lsp.buf.signature_help, "Signature Help", has = "signatureHelp" },
    { "<c-k>", vim.lsp.buf.signature_help, "Signature Help", mode = "i", has = "signatureHelp" },
    { "<leader>ca", vim.lsp.buf.code_action, "Code Action", mode = { "n", "x" }, has = "codeAction" },
    { "<leader>cc", vim.lsp.codelens.run, "Run Codelens", mode = { "n", "x" }, has = "codeLens" },
    {
      "<leader>cC",
      function()
        vim.lsp.codelens.enable(true, { bufnr = 0 })
      end,
      "Refresh & Display Codelens",
      has = "codeLens",
    },
    {
      "<leader>cR",
      function()
        Snacks.rename.rename_file()
      end,
      "Rename File",
      has = { "workspace/didRenameFiles", "workspace/willRenameFiles" },
    },
    { "<leader>cr", vim.lsp.buf.rename, "Rename", has = "rename" },
    { "<leader>cA", source_action, "Source Action", has = "codeAction" },
    { "]]", words(1), "Next Reference", has = "documentHighlight", words = true },
    { "[[", words(-1), "Prev Reference", has = "documentHighlight", words = true },
    { "<a-n>", words(1, true), "Next Reference", has = "documentHighlight", words = true },
    { "<a-p>", words(-1, true), "Prev Reference", has = "documentHighlight", words = true },
    {
      "<leader>ss",
      P("lsp_symbols", { filter = util.kind_filter }),
      "LSP Symbols",
      has = "documentSymbol",
    },
    {
      "<leader>sS",
      P("lsp_workspace_symbols", { filter = util.kind_filter }),
      "LSP Workspace Symbols",
      has = "workspace/symbol",
    },
    { "gai", P("lsp_incoming_calls"), "C[a]lls Incoming", has = "callHierarchy/incomingCalls" },
    { "gao", P("lsp_outgoing_calls"), "C[a]lls Outgoing", has = "callHierarchy/outgoingCalls" },
  }
end

local function supports(client, has, buf)
  if not has then
    return true
  end
  for _, method in ipairs(type(has) == "table" and has or { has }) do
    method = method:find("/") and method or ("textDocument/" .. method)
    if client:supports_method(method, buf) then
      return true
    end
  end
  return false
end

local function on_attach(client, buf)
  for _, k in ipairs(keys()) do
    if supports(client, k.has, buf) and not (k.words and not Snacks.words.is_enabled()) then
      vim.keymap.set(k.mode or "n", k[1], k[2], { buffer = buf, desc = k[3], nowait = k.nowait, silent = true })
    end
  end
  if
    client:supports_method("textDocument/inlayHint", buf)
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype ~= "vue"
  then
    vim.lsp.inlay_hint.enable(true, { bufnr = buf })
  end
  if client:supports_method("textDocument/foldingRange", buf) then
    vim.api.nvim_buf_call(buf, function()
      if util.set_default("foldmethod", "expr") then
        util.set_default("foldexpr", "v:lua.vim.lsp.foldexpr()")
      end
    end)
  end
end

function M.setup()
  vim.diagnostic.config({
    underline = true,
    update_in_insert = false,
    virtual_text = { spacing = 4, source = "if_many", prefix = "●" },
    severity_sort = true,
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = icons.diagnostics.Error,
        [vim.diagnostic.severity.WARN] = icons.diagnostics.Warn,
        [vim.diagnostic.severity.HINT] = icons.diagnostics.Hint,
        [vim.diagnostic.severity.INFO] = icons.diagnostics.Info,
      },
    },
  })

  vim.lsp.config("*", {
    capabilities = {
      workspace = {
        fileOperations = { didRename = true, willRename = true },
      },
    },
  })
  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        workspace = { checkThirdParty = false },
        codeLens = { enable = true },
        completion = { callSnippet = "Replace" },
        doc = { privateName = { "^_" } },
        hint = {
          enable = true,
          setType = false,
          paramType = true,
          paramName = "Disable",
          semicolon = "Disable",
          arrayIndex = "Disable",
        },
      },
    },
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("misw_lsp_attach", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client then
        on_attach(client, ev.buf)
      end
    end,
  })

  vim.lsp.enable(vim.tbl_filter(function(name)
    local cmd = vim.lsp.config[name].cmd
    return type(cmd) ~= "table" or vim.fn.executable(cmd[1]) == 1
  end, M.servers))

  -- lazydev: lua_ls knows the nvim runtime and plugin APIs
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("misw_lazydev", { clear = true }),
    pattern = "lua",
    once = true,
    callback = function()
      require("lazydev").setup({
        library = {
          { path = "${3rd}/luv/library", words = { "vim%.uv" } },
          { path = "snacks.nvim", words = { "Snacks" } },
        },
      })
    end,
  })
end

return M
