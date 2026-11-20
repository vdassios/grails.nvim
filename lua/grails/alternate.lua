-- :GrailsAlternate: controller action <-> view, and cycling between the
-- same-named domain class, controller and service.
local context = require 'grails.context'
local definition = require 'grails.features.definition'
local project = require 'grails.project'
local util = require 'grails.util'

local M = {}

local CYCLE = { 'domain', 'controller', 'service' }

--- Same-named artefacts in cycle order, and the index of `path` among them.
local function cycle(root, name, path)
  local list = {}
  for _, kind in ipairs(CYCLE) do
    vim.list_extend(list, project.artefacts(root, { kind = kind, name = name }, path))
  end
  for i, a in ipairs(list) do
    if a.path == path then
      return list, i
    end
  end
  return list, 0
end

--- The action under the cursor in a controller buffer.
local function action_at_cursor(path)
  local doc = util.read(path)
  local root = doc and util.parse(doc, 'groovy')
  if not root then
    return nil
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local node = root:named_descendant_for_range(row - 1, col, row - 1, col)
  local _, method = context.enclosing(doc, node)
  return method
end

--- Where `:GrailsAlternate` goes from a file.
--- @param path string
--- @param action? string action under the cursor, for a controller
--- @return lsp.Location?
function M.target(path, action)
  local root = project.find_root(path)
  if not root then
    return nil
  end
  local dir = project.view_dir(path)
  if dir then
    -- A view: its action in the controller that owns the directory, else the controller.
    local controller = dir:match '^[^/]+'
    local name = vim.fs.basename(path):gsub('%.[^.]+$', '')
    local controllers = controller and project.artefacts(root, { kind = 'controller', name = controller }, path) or {}
    for _, a in ipairs(controllers) do
      local _, _, member = definition.find_in_class(a.path, a.class, name)
      if member then
        return util.location(a.path, member)
      end
    end
    return controllers[1] and util.location(controllers[1].path)
  end
  local current = project.artefacts(root, { path = path })[1]
  if not current then
    return nil
  end
  if current.kind == 'controller' and action then
    local views = project.find_files(root, {
      'views/' .. current.name .. '/' .. action .. '.gsp',
      'views/' .. current.name .. '/' .. action .. '.jsp',
      'views/' .. current.name .. '/' .. action .. '.gson',
    }, path)
    if views[1] then
      return util.location(views[1])
    end
  end
  local list, i = cycle(root, current.name, path)
  local next = list[i % #list + 1]
  if next and next.path ~= path then
    return util.location(next.path)
  end
end

--- Jump from the current buffer to its alternate file.
function M.jump()
  local path = vim.api.nvim_buf_get_name(0)
  local action = path:match '%.groovy$' and action_at_cursor(path)
  local loc = M.target(path, action or nil)
  if not loc then
    vim.notify('grails.nvim: no alternate file', vim.log.levels.WARN)
    return
  end
  vim.lsp.util.show_document(loc, 'utf-8', { focus = true })
end

return M
