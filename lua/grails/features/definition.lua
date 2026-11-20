-- textDocument/definition: views, templates, layouts, assets, controllers and actions.
local context = require 'grails.context'
local project = require 'grails.project'
local util = require 'grails.util'

local M = {}

local VIEW_EXTS = { '.gsp', '.jsp', '.gson' }
local ASSET_EXTS = {
  stylesheet = { '.css', '.scss', '.sass', '.less' },
  javascript = { '.js', '.es6', '.ts', '.coffee' },
}
local ASSET_TAGS = { stylesheet = true, javascript = true, image = true, assetPath = true, link = true }
local LINK_CALLS = { redirect = true, chain = true, forward = true, createLink = true, link = true }

--- `a/b` joined to a base directory under `views/`; an absolute `/a/b` ignores the base.
--- @return string? dir, string? name directory relative to `views/` and the last segment
local function split_path(value, base)
  local dir, name = value:match '^(.*)/([^/]+)$'
  if not dir then
    dir, name = '', value
  end
  if value:sub(1, 1) == '/' then
    return dir:sub(2), name
  end
  if not base then
    return nil
  end
  return base == '' and dir or (dir == '' and base or base .. '/' .. dir), name
end

local function views_rel(dir, file)
  return dir == '' and 'views/' .. file or 'views/' .. dir .. '/' .. file
end

--- @class grails.Request
--- @field root string
--- @field path string
--- @field encoding 'utf-8'|'utf-16'
--- @field controller? string logical name of the controller the cursor belongs to

local function files(req, rels)
  return vim.tbl_map(function(path)
    return util.location(path, req.encoding)
  end, project.find_files(req.root, rels, req.path))
end

local function template(req, value, base)
  local dir, name = split_path(value, base)
  return dir and files(req, { views_rel(dir, '_' .. name .. '.gsp') }) or {}
end

local function view(req, value, base)
  local dir, name = split_path(value, base)
  if not dir then
    return {}
  end
  return files(
    req,
    vim.tbl_map(function(ext)
      return views_rel(dir, name .. ext)
    end, VIEW_EXTS)
  )
end

local function layout(req, value)
  return files(req, { 'views/layouts/' .. value .. '.gsp' })
end

local function asset(req, tag, value)
  local names = { value }
  local stem = value:gsub('%.[^./]+$', '')
  for _, ext in ipairs(ASSET_EXTS[tag] or {}) do
    if stem .. ext ~= value then
      names[#names + 1] = stem .. ext
    end
  end
  for _, name in ipairs(names) do
    local found = {}
    for _, dir in ipairs(project.asset_dirs(req.root, req.path)) do
      local path = vim.fs.joinpath(dir, name)
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == 'file' then
        found[#found + 1] = util.location(path, req.encoding)
      end
    end
    if #found > 0 then
      return found
    end
  end
  return {}
end

--- The class declaration of an artefact and its member `member`, from its syntax tree.
--- An action is a method that is not private, protected or static, or a property assigned a closure.
--- @return grails.Doc?, TSNode? class_name, TSNode? member_name
function M.find_in_class(path, class, member)
  local doc = util.read(path)
  local root = doc and util.parse(doc, 'groovy')
  if not root then
    return doc
  end
  for _, node in ipairs(root:named_children()) do
    local name = node:type() == 'class_definition' and node:field('name')[1]
    if name and util.node_text(doc, name) == class then
      local body = node:field('body')[1]
      if not member or not body then
        return doc, name
      end
      for _, m in ipairs(body:named_children()) do
        local mname
        if m:type() == 'function_definition' then
          local hidden = false
          for _, child in ipairs(m:named_children()) do
            local text = (child:type() == 'access_modifier' or child:type() == 'modifier') and util.node_text(doc, child)
            hidden = hidden or text == 'private' or text == 'protected' or text == 'static'
          end
          mname = not hidden and m:field('function')[1]
        elseif m:type() == 'declaration' then
          local value = m:field('value')[1]
          mname = value and value:type() == 'closure' and m:field('name')[1]
        end
        if mname and util.node_text(doc, mname) == member then
          return doc, name, mname
        end
      end
      return doc, name
    end
  end
  return doc
end

local function controller(req, name)
  local found = {}
  for _, a in ipairs(project.artefacts(req.root, { kind = 'controller', name = name }, req.path)) do
    local doc, class = M.find_in_class(a.path, a.class)
    -- A file that cannot be read (deleted since it was listed, no permission) is no target.
    if doc then
      found[#found + 1] = util.location(a.path, req.encoding, doc, class)
    end
  end
  return found
end

local function action(req, controller_name, name)
  if not controller_name then
    return {}
  end
  local found = {}
  for _, a in ipairs(project.artefacts(req.root, { kind = 'controller', name = controller_name }, req.path)) do
    local doc, _, member = M.find_in_class(a.path, a.class, name)
    if member then
      found[#found + 1] = util.location(a.path, req.encoding, doc, member)
    end
  end
  return found
end

--- @param req grails.Request
--- @param ctx grails.Context
--- @return lsp.Location[]
local function resolve_gsp(req, ctx)
  local tag, attr, value = ctx.tag, ctx.attr, ctx.value
  local base = project.view_dir(req.path)
  if tag.ns == 'tmpl' then
    return attr == nil and template(req, value, base) or {}
  end
  if tag.ns == nil then
    return (tag.name == 'meta' and ctx.attrs.name == 'layout') and layout(req, value) or {}
  end
  if tag.ns == 'asset' and ASSET_TAGS[tag.name] and (attr == 'src' or attr == 'href') then
    return asset(req, tag.name, value)
  end
  if attr == 'controller' then
    return controller(req, value)
  end
  if attr == 'action' then
    return action(req, ctx.attrs.controller or req.controller, value)
  end
  if tag.ns == 'g' then
    if attr == 'template' then
      local prefix = ctx.attrs.contextPath
      if prefix and prefix ~= '' then
        value = prefix:gsub('/+$', '') .. '/' .. value:gsub('^/+', '')
      end
      return template(req, value, base)
    elseif attr == 'view' then
      return view(req, value, base)
    elseif tag.name == 'applyLayout' and attr == 'name' then
      return layout(req, value)
    end
  end
  return {}
end

--- @param req grails.Request
--- @param ctx grails.Context
--- @return lsp.Location[]
local function resolve_groovy(req, ctx)
  local value, call, arg = ctx.value, ctx.call, ctx.named_arg
  if ctx.property == 'layout' then
    return req.controller and layout(req, value) or {}
  end
  if call == 'render' and arg == 'view' then
    return view(req, value, req.controller)
  end
  if call == 'render' and arg == 'template' then
    return template(req, value, req.controller)
  end
  if LINK_CALLS[call] and arg == 'controller' then
    return controller(req, value)
  end
  if LINK_CALLS[call] and arg == 'action' then
    return action(req, ctx.args.controller or req.controller, value)
  end
  return {}
end

--- Definition targets for a request, or an empty list when the cursor is on
--- nothing this server knows (results then come from other servers alone).
--- @param params lsp.TextDocumentPositionParams
--- @param encoding 'utf-8'|'utf-16'
--- @return lsp.Location[]
function M.definition(params, encoding)
  local path = vim.uri_to_fname(params.textDocument.uri)
  local lang = path:match '%.gsp$' and 'gsp' or path:match '%.groovy$' and 'groovy'
  local root = lang and project.find_root(path)
  local doc = root and util.read(path)
  if not doc then
    return {}
  end
  local row = params.position.line
  local col = util.to_byte(doc.lines[row + 1] or '', params.position.character, encoding)
  local ctx = context.at(doc, lang, row, col)
  if not ctx or not ctx.value or ctx.value == '' or ctx.value:find('$', 1, true) then
    return {}
  end

  local req = { root = root, path = path, encoding = encoding }
  if lang == 'gsp' then
    local base = project.view_dir(path)
    req.controller = base and base ~= '' and base:match '^[^/]+' or nil
    return resolve_gsp(req, ctx)
  end
  -- The controller is found by file name, so it is known even inside a parse error.
  local artefact = project.artefacts(root, { path = path })[1]
  req.controller = artefact and artefact.kind == 'controller' and artefact.name or nil
  return resolve_groovy(req, ctx)
end

return M
