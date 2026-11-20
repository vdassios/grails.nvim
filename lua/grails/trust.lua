-- The roots the user trusts to run grails_ls (`:GrailsTrust`). grails_ls runs the project's Gradle build and AST
-- transformations, so it starts only for a trusted root. The only code that reads or writes the allowlist file,
-- `stdpath('state')/grails/trusted.json`: `{ "version": 1, "roots": ["/real/path"] }`. Roots are stored and
-- compared as real paths, so a symlink to a trusted root is trusted.
local M = {}

local VERSION = 1

--- The allowlist file.
function M.file()
  return vim.fs.joinpath(vim.fn.stdpath 'state', 'grails', 'trusted.json')
end

--- `path` with symlinks resolved; normalized `path` when it does not exist.
--- @param path string
--- @return string
function M.real(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

--- @return string[]
local function read()
  local fd = io.open(M.file(), 'r')
  if not fd then
    return {}
  end
  local text = fd:read '*a'
  fd:close()
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= 'table' or type(data.roots) ~= 'table' then
    vim.notify_once(('grails: ignoring %s: not a trusted-roots file'):format(M.file()), vim.log.levels.WARN)
    return {}
  end
  return vim.tbl_filter(function(root)
    return type(root) == 'string'
  end, data.roots)
end

--- @param roots string[]
local function write(roots)
  local file = M.file()
  vim.fn.mkdir(vim.fs.dirname(file), 'p')
  local partial = file .. '.part'
  local fd = assert(io.open(partial, 'w'))
  fd:write(vim.json.encode { version = VERSION, roots = roots })
  fd:close()
  assert(os.rename(partial, file))
end

--- @param root string
--- @return boolean
function M.is_trusted(root)
  return vim.list_contains(read(), M.real(root))
end

--- Adds `root` to the allowlist.
--- @param root string
function M.trust(root)
  local roots, real = read(), M.real(root)
  if not vim.list_contains(roots, real) then
    roots[#roots + 1] = real
    table.sort(roots)
    write(roots)
  end
end

--- Removes `root` from the allowlist; false when it was not in it.
--- @param root string
--- @return boolean
function M.revoke(root)
  local real = M.real(root)
  local roots = read()
  local kept = vim.tbl_filter(function(r)
    return r ~= real
  end, roots)
  if #kept == #roots then
    return false
  end
  write(kept)
  return true
end

return M
