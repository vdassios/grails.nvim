local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
M.app = M.root .. '/tests/fixtures/app'

function M.eq(expected, actual, what)
  if not vim.deep_equal(expected, actual) then
    error(('%sexpected %s, got %s'):format(what and what .. ': ' or '', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

--- Absolute path of a fixture file.
function M.path(rel)
  return M.app .. '/' .. rel
end

--- 0-based row and byte column of the first `needle` in `lines`, plus `offset` bytes.
--- @param nth? integer use the nth occurrence
function M.pos(lines, needle, offset, nth)
  nth = nth or 1
  for row, line in ipairs(lines) do
    local init = 1
    while true do
      local col = line:find(needle, init, true)
      if not col then
        break
      end
      nth = nth - 1
      if nth == 0 then
        return row - 1, col - 1 + (offset or 0)
      end
      init = col + 1
    end
  end
  error('not found: ' .. needle, 2)
end

--- Edit a fixture file; returns the buffer.
function M.edit(rel)
  vim.cmd.edit(vim.fn.fnameescape(M.path(rel)))
  return vim.api.nvim_get_current_buf()
end

return M
