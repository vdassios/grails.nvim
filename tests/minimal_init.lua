-- nvim --headless -u tests/minimal_init.lua -l tests/run.lua [filter]
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

vim.opt.runtimepath:prepend(root)
-- `groovy` and `html` parsers, as installed by nvim-treesitter.
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/site')
vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'

-- Build the `gsp` parser from this checkout.
local so = vim.fn.tempname() .. '-gsp.so'
local function fail(msg)
  io.stderr:write(msg .. '\n')
  os.exit(1)
end
local build = vim.system({ 'tree-sitter', 'build', '-o', so, root .. '/tree-sitter-gsp' }):wait()
if build.code ~= 0 then
  fail('tree-sitter build failed: ' .. (build.stderr or ''))
end
vim.treesitter.language.add('gsp', { path = so })
if not vim.treesitter.language.add 'groovy' then
  fail 'the groovy parser is missing: install it with nvim-treesitter'
end
