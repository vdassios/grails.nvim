local h = require 'helpers'

local T = {}

local LIST = 'web/grails-app/views/book/list.gsp'
local BOOKS = 'core/grails-app/controllers/bookshop/BookController.groovy'
local AUTHORS = 'core/grails-app/controllers/bookshop/AuthorController.groovy'

--- Definition results, as `path:line`, for the `offset`-th byte of the `nth` match of `needle`.
local function define(rel, needle, offset, nth)
  local buf = h.edit(rel)
  local client = h.client(buf)
  local row, col = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), needle, offset, nth)
  local res = client:request_sync('textDocument/definition', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = row, character = col },
  }, 2000, buf)
  assert(res and not res.err, vim.inspect(res))
  return vim.tbl_map(function(loc)
    return vim.fs.relpath(h.app, vim.uri_to_fname(loc.uri)) .. ':' .. loc.range.start.line
  end, res.result)
end

local function views(rel)
  return 'web/grails-app/views/' .. rel .. ':0'
end

-- GSP --------------------------------------------------------------------------

function T.gsp_render_template_absolute()
  h.eq({ views 'book/_row.gsp' }, define(LIST, '/book/row', 3))
end

function T.gsp_tmpl_tag_relative_and_absolute()
  h.eq({ views 'book/_row.gsp' }, define(LIST, 'tmpl:row', 6))
  h.eq({ views 'shared/_footer.gsp' }, define(LIST, 'tmpl:/shared/footer', 8))
end

function T.gsp_include_view_relative()
  h.eq({ views 'book/show.gsp' }, define(LIST, 'view="show"', 7))
end

function T.gsp_meta_layout()
  h.eq({ views 'layouts/main.gsp' }, define(LIST, 'content="main"', 10))
end

function T.gsp_assets_with_extension_fallback()
  h.eq({ 'web/grails-app/assets/stylesheets/app.scss:0' }, define(LIST, 'src="app.css"', 6))
  h.eq({ 'web/grails-app/assets/javascripts/app.js:0' }, define(LIST, 'src="app"', 6))
  h.eq({ 'web/grails-app/assets/images/logo.svg:0' }, define(LIST, 'logo.svg', 1))
end

function T.gsp_controller_attribute()
  h.eq({ AUTHORS .. ':2' }, define(LIST, 'controller="author"', 13))
end

function T.gsp_action_in_named_controller()
  h.eq({ AUTHORS .. ':4' }, define(LIST, 'action="show" id="${book.author', 9))
end

function T.gsp_action_in_the_view_controller()
  h.eq({ BOOKS .. ':12' }, define(LIST, 'action="show" id="${book.id', 9))
end

function T.gsp_missing_or_computed_targets_are_empty()
  h.eq({}, define(LIST, '/missing/thing', 3))
  h.eq({}, define(LIST, '/book/${kind}', 3))
end

-- Groovy -----------------------------------------------------------------------

function T.groovy_render_view_absolute_and_relative()
  h.eq({ views 'book/list.gsp' }, define(BOOKS, '/book/list', 3))
  h.eq({ views 'book/show.gsp' }, define(BOOKS, "view: 'show'", 8))
end

function T.groovy_render_template_relative()
  h.eq({ views 'book/_row.gsp' }, define(BOOKS, "template: 'row'", 12))
end

function T.groovy_redirect_controller_and_action()
  h.eq({ AUTHORS .. ':2' }, define(BOOKS, "controller: 'author', action: 'show'", 14))
  h.eq({ AUTHORS .. ':4' }, define(BOOKS, "action: 'show', id", 10))
end

function T.groovy_action_as_closure_property()
  h.eq({ AUTHORS .. ':8' }, define(BOOKS, "action: 'list'", 10))
end

function T.groovy_action_in_the_current_controller()
  h.eq({ BOOKS .. ':12' }, define(BOOKS, "redirect action: 'show'", 19))
end

function T.groovy_static_layout()
  h.eq({ views 'layouts/main.gsp' }, define(BOOKS, "layout = 'main'", 11))
end

function T.groovy_missing_or_computed_targets_are_empty()
  h.eq({}, define(BOOKS, '/book/nothing', 3))
  h.eq({}, define(BOOKS, '/book/${actionName}', 3))
  h.eq({}, define(BOOKS, "action: 'helper'", 10)) -- private methods are not actions
end

-- Files changed outside Neovim -----------------------------------------------------

--- A one-module project in a temporary directory (real path), with a view linking to the `book` controller.
local function scratch_project()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/grails-app/views/book', 'p')
  vim.fn.mkdir(dir .. '/grails-app/controllers/shop', 'p')
  dir = vim.uv.fs_realpath(dir)
  vim.fn.writefile({}, dir .. '/settings.gradle')
  vim.fn.writefile({ '<g:link controller="book">Books</g:link>' }, dir .. '/grails-app/views/book/index.gsp')
  return dir
end

local CONTROLLER = { 'package shop', '', 'class BookController {', '}' }

--- Definition results, as `path:line` relative to `dir`, for `controller="book"` in the scratch project's view.
local function define_book(dir)
  local buf = vim.fn.bufadd(dir .. '/grails-app/views/book/index.gsp')
  vim.cmd.buffer(buf)
  local res = h.client(buf):request_sync('textDocument/definition', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = 0, character = #'<g:link controller="b' },
  }, 2000, buf)
  assert(res and not res.err, vim.inspect(res))
  return vim.tbl_map(function(loc)
    return vim.fs.relpath(dir, vim.uri_to_fname(loc.uri)) .. ':' .. loc.range.start.line
  end, res.result)
end

local function drop_project(dir)
  for _, client in ipairs(vim.lsp.get_clients { name = 'grails' }) do
    if client.root_dir == dir then
      client:stop(true)
    end
  end
  vim.cmd.bwipeout { dir .. '/grails-app/views/book/index.gsp', bang = true }
  vim.fn.delete(dir, 'rf')
end

function T.an_unreadable_target_gives_no_location()
  local dir = scratch_project()
  local path = dir .. '/grails-app/controllers/shop/BookController.groovy'
  local ok, err = pcall(function()
    vim.fn.writefile(CONTROLLER, path)
    vim.fn.setfperm(path, '---------')
    h.eq({}, define_book(dir))
  end)
  drop_project(dir)
  assert(ok, err)
end

return T
