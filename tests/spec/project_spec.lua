local h = require 'helpers'
local project = require 'grails.project'

local T = {}

function T.root_from_a_nested_file()
  h.eq(h.app, project.find_root(h.path 'web/grails-app/views/book/list.gsp'))
  h.eq(h.app, project.find_root(h.path 'core/grails-app/controllers/bookshop/BookController.groovy'))
end

function T.no_root_outside_a_grails_project()
  h.eq(nil, project.find_root(h.root .. '/tests/run.lua'))
  h.eq(nil, project.find_root '')
end

function T.root_without_settings_is_the_grails_app_parent()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/grails-app/views', 'p')
  dir = vim.uv.fs_realpath(dir)
  h.eq(dir, project.find_root(dir .. '/grails-app/views/index.gsp'))
  vim.fn.delete(dir, 'rf')
end

function T.a_build_nested_in_another_build_is_its_own_project()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/demo/app/grails-app/views', 'p')
  vim.fn.mkdir(dir .. '/demo/app/core/grails-app/views', 'p')
  dir = vim.uv.fs_realpath(dir)
  vim.fn.writefile({}, dir .. '/settings.gradle')
  vim.fn.writefile({}, dir .. '/demo/app/settings.gradle.kts')
  h.eq(dir .. '/demo/app', project.find_root(dir .. '/demo/app/grails-app/views/index.gsp'))
  h.eq(dir .. '/demo/app', project.find_root(dir .. '/demo/app/core/grails-app/views/index.gsp'), 'a module of the nested build')
  vim.fn.delete(dir, 'rf')
end

function T.modules()
  h.eq({ h.path 'core', h.path 'web' }, project.modules(h.app))
end

function T.current_module_searched_first()
  h.eq({ h.path 'web', h.path 'core' }, project.search_order(h.app, h.path 'web/grails-app/views/book/list.gsp'))
end

function T.logical_names()
  h.eq('book', project.logical_name('BookController', 'Controller'))
  h.eq('fooBar', project.logical_name('FooBarService', 'Service'))
  h.eq('URL', project.logical_name('URLController', 'Controller'))
  h.eq('book', project.logical_name('Book', ''))
end

function T.artefact_index()
  local found = {}
  for _, a in ipairs(project.artefacts(h.app, {})) do
    found[#found + 1] = a.kind .. ' ' .. a.name
  end
  table.sort(found)
  h.eq({ 'controller author', 'controller book', 'domain author', 'domain book', 'service book' }, found)
end

function T.reset_drops_the_cache()
  project.modules(h.app)
  project.reset(h.app)
  h.eq({ h.path 'core', h.path 'web' }, project.modules(h.app))
end

function T.view_dir()
  h.eq('book', project.view_dir(h.path 'web/grails-app/views/book/list.gsp'))
  h.eq('', project.view_dir(h.path 'web/grails-app/views/index.gsp'))
  h.eq(nil, project.view_dir(h.path 'core/grails-app/domain/bookshop/Book.groovy'))
end

return T
