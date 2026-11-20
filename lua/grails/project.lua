-- Workspace model: project root, modules and the artefact file index.
-- Built lazily from file names only, cached per root.
local M = {}

local uv = vim.uv

--- Directories never searched for modules.
local SKIP = { build = true, node_modules = true, out = true, target = true, src = true, ['grails-app'] = true }

--- Artefact kinds found by file name: directory under `grails-app/` and class name suffix.
--- A domain class is any class under `domain/`.
M.kinds = {
  { kind = 'domain', dir = 'domain', suffix = '' },
  { kind = 'controller', dir = 'controllers', suffix = 'Controller' },
  { kind = 'service', dir = 'services', suffix = 'Service' },
  { kind = 'taglib', dir = 'taglib', suffix = 'TagLib' },
  { kind = 'interceptor', dir = 'controllers', suffix = 'Interceptor' },
}

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == 'directory'
end

local function is_file(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == 'file'
end

--- Logical name of an artefact class: `FooBarController` gives `fooBar`. As in
--- Grails, a name starting with two capitals keeps its case (`URLController` gives `URL`).
--- @param class string
--- @param suffix string
--- @return string
function M.logical_name(class, suffix)
  if suffix ~= '' and #class > #suffix and class:sub(-#suffix) == suffix then
    class = class:sub(1, -#suffix - 1)
  end
  if class:match '^%u%u' then
    return class
  end
  return class:sub(1, 1):lower() .. class:sub(2)
end

--- Project root for a file: the nearest ancestor holding `grails-app/`, then the
--- nearest ancestor of that with a `settings.gradle(.kts)`, as Gradle picks the build
--- (a Grails build nested in another Gradle build is its own project). Nil outside a Grails project.
--- @param path string
--- @return string?
function M.find_root(path)
  if not path or path == '' then
    return nil
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  local app = vim.fs.find('grails-app', { upward = true, path = vim.fs.dirname(path), type = 'directory', limit = 1 })[1]
  if not app then
    return nil
  end
  local root = vim.fs.dirname(app)
  local settings = vim.fs.find({ 'settings.gradle', 'settings.gradle.kts' }, { upward = true, path = root, type = 'file', limit = 1 })[1]
  return settings and vim.fs.dirname(settings) or root
end

--- @class grails.Artefact
--- @field kind string
--- @field class string class name, from the file name
--- @field name string logical name
--- @field path string
--- @field module string

--- @class grails.Index
--- @field modules? string[]
--- @field artefacts? grails.Artefact[]

--- @type table<string, grails.Index>
local cache = {}

--- Drop the cached index of one root, or of every root.
--- @param root? string
function M.reset(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

--- Drop the index of the project holding `path`.
--- @param path string
function M.invalidate(path)
  local root = M.find_root(path)
  if root then
    M.reset(root)
  end
end

local function index(root)
  cache[root] = cache[root] or {}
  return cache[root]
end

--- Module directories (each holds a `grails-app/`), up to three levels below the root. A directory with its own
--- `settings.gradle(.kts)` is another build (`find_root`), so it and everything below it are left out.
--- @param root string
--- @return string[]
function M.modules(root)
  local idx = index(root)
  if idx.modules then
    return idx.modules
  end
  local mods = {}
  local skip = function(dir)
    local name = vim.fs.basename(dir)
    if SKIP[name] or name:sub(1, 1) == '.' then
      return false
    end
    local path = vim.fs.joinpath(root, dir)
    return not (is_file(vim.fs.joinpath(path, 'settings.gradle')) or is_file(vim.fs.joinpath(path, 'settings.gradle.kts')))
  end
  for name, type in vim.fs.dir(root, { depth = 4, skip = skip }) do
    if type == 'directory' and vim.fs.basename(name) == 'grails-app' then
      local dir = vim.fs.dirname(name)
      mods[#mods + 1] = dir == '.' and root or vim.fs.joinpath(root, dir)
    end
  end
  table.sort(mods)
  idx.modules = mods
  return mods
end

--- The module holding `path`, if any.
--- @param root string
--- @param path string
--- @return string?
function M.module_of(root, path)
  local best
  for _, mod in ipairs(M.modules(root)) do
    if vim.fs.relpath(mod, path) and (not best or #mod > #best) then
      best = mod
    end
  end
  return best
end

--- Modules with the one holding `path` first: lookups search every module,
--- because controllers and views often live in different ones.
--- @param root string
--- @param path? string
--- @return string[]
function M.search_order(root, path)
  local current = path and M.module_of(root, path)
  local order = { current }
  for _, mod in ipairs(M.modules(root)) do
    if mod ~= current then
      order[#order + 1] = mod
    end
  end
  return order
end

local function artefacts(root)
  local idx = index(root)
  if idx.artefacts then
    return idx.artefacts
  end
  local list = {}
  for _, mod in ipairs(M.modules(root)) do
    for _, kind in ipairs(M.kinds) do
      local dir = vim.fs.joinpath(mod, 'grails-app', kind.dir)
      if is_dir(dir) then
        for name, type in vim.fs.dir(dir, { depth = math.huge }) do
          local class = type == 'file' and vim.fs.basename(name):match '^(%u[%w_]*)%.groovy$'
          if class and (kind.suffix == '' or (#class > #kind.suffix and class:sub(-#kind.suffix) == kind.suffix)) then
            list[#list + 1] = {
              kind = kind.kind,
              class = class,
              name = M.logical_name(class, kind.suffix),
              path = vim.fs.joinpath(dir, name),
              module = mod,
            }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    return a.path < b.path
  end)
  idx.artefacts = list
  return list
end

--- Artefacts matching a filter, those in the module of `from` first.
--- @param root string
--- @param filter { kind?: string, name?: string, class?: string, path?: string }
--- @param from? string
--- @return grails.Artefact[]
function M.artefacts(root, filter, from)
  local found = {}
  for _, mod in ipairs(M.search_order(root, from)) do
    for _, a in ipairs(artefacts(root)) do
      if
        a.module == mod
        and (not filter.kind or a.kind == filter.kind)
        and (not filter.name or a.name == filter.name)
        and (not filter.class or a.class == filter.class)
        and (not filter.path or a.path == filter.path)
      then
        found[#found + 1] = a
      end
    end
  end
  return found
end

--- Existing files under `grails-app/` of any module, those in the module of `from` first.
--- @param root string
--- @param rels string[] paths relative to `grails-app/`, tried in order per module
--- @param from? string
--- @return string[]
function M.find_files(root, rels, from)
  local found = {}
  for _, mod in ipairs(M.search_order(root, from)) do
    for _, rel in ipairs(rels) do
      local path = vim.fs.joinpath(mod, 'grails-app', rel)
      if is_file(path) then
        found[#found + 1] = path
      end
    end
  end
  return found
end

--- Asset directories (`grails-app/assets/*/`) of every module, those in the module of `from` first.
--- @param root string
--- @param from? string
--- @return string[]
function M.asset_dirs(root, from)
  local dirs = {}
  for _, mod in ipairs(M.search_order(root, from)) do
    local assets = vim.fs.joinpath(mod, 'grails-app', 'assets')
    if is_dir(assets) then
      local subs = {}
      for name, type in vim.fs.dir(assets) do
        if type == 'directory' then
          subs[#subs + 1] = vim.fs.joinpath(assets, name)
        end
      end
      table.sort(subs)
      vim.list_extend(dirs, subs)
    end
  end
  return dirs
end

--- The view directory of a GSP file, relative to `grails-app/views/` (`book` for
--- `views/book/show.gsp`, `''` for a file directly in `views/`). Nil outside `views/`.
--- @param path string
--- @return string?
function M.view_dir(path)
  local rel = path:match '/grails%-app/views/(.*)$'
  if not rel then
    return nil
  end
  local dir = vim.fs.dirname(rel)
  return dir == '.' and '' or dir
end

return M
