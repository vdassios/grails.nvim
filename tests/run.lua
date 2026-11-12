-- Dependency-free test runner: runs every function of each tests/spec/*_spec.lua
-- (in name order) and exits non-zero when any fails. An argument filters spec files.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
package.path = root .. '/tests/?.lua;' .. package.path

local filter = _G.arg[1]
local files = vim.fn.glob(root .. '/tests/spec/*_spec.lua', false, true)
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
  local spec_name = vim.fs.basename(file):gsub('%.lua$', '')
  if not filter or spec_name:find(filter, 1, true) then
    local spec = dofile(file)
    local names = vim.tbl_keys(spec)
    table.sort(names)
    for _, name in ipairs(names) do
      local ok, err = xpcall(spec[name], debug.traceback)
      if ok then
        passed = passed + 1
        print(('ok    %s: %s'):format(spec_name, name))
      else
        failed = failed + 1
        print(('FAIL  %s: %s\n%s'):format(spec_name, name, err))
      end
    end
  end
end

print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
