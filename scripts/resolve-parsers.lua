-- nvim -l resolve-parsers.lua <parsers.lua> <parsers.txt>
-- Prints one TSV line per language, wanted ones plus everything they
-- `require` (recursively): lang, url, revision, location. Query-only
-- languages (no parser, e.g. ecma) get "-" for url/revision.
local parsers = dofile(arg[1])

local wanted = {}
for line in io.lines(arg[2]) do
  line = vim.trim(line)
  if line ~= "" and not line:match("^#") then
    wanted[#wanted + 1] = line
  end
end

local seen, out = {}, {}
local function add(lang)
  if seen[lang] then
    return
  end
  seen[lang] = true
  local p = parsers[lang]
  if not p then
    error("unknown treesitter language: " .. lang)
  end
  local info = p.install_info
  out[#out + 1] = table.concat({
    lang,
    info and info.url or "-",
    info and info.revision or "-",
    info and info.location or "-",
  }, "\t")
  for _, dep in ipairs(p.requires or {}) do
    add(dep)
  end
end

for _, lang in ipairs(wanted) do
  add(lang)
end
table.sort(out)
io.write(table.concat(out, "\n"), "\n")
