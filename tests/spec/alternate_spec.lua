local h = require 'helpers'
local alternate = require 'grails.alternate'

local T = {}

local BOOKS = 'core/grails-app/controllers/bookshop/BookController.groovy'

local function target(rel, action)
  local loc = alternate.target(h.path(rel), action)
  return loc and vim.fs.relpath(h.app, vim.uri_to_fname(loc.uri)) .. ':' .. loc.range.start.line
end

function T.view_to_its_action()
  h.eq(BOOKS .. ':12', target 'web/grails-app/views/book/show.gsp')
end

function T.view_without_an_action_to_the_controller()
  h.eq(BOOKS .. ':0', target 'web/grails-app/views/book/list.gsp')
end

function T.action_to_its_view()
  h.eq('web/grails-app/views/book/show.gsp:0', target(BOOKS, 'show'))
end

function T.cycle_domain_controller_service()
  h.eq(BOOKS .. ':0', target 'core/grails-app/domain/bookshop/Book.groovy')
  h.eq('core/grails-app/services/bookshop/BookService.groovy:0', target(BOOKS, nil))
  h.eq('core/grails-app/services/bookshop/BookService.groovy:0', target(BOOKS, 'index')) -- no index.gsp
  h.eq('core/grails-app/domain/bookshop/Book.groovy:0', target 'core/grails-app/services/bookshop/BookService.groovy')
end

function T.nothing_outside_a_project()
  h.eq(nil, alternate.target(h.root .. '/tests/run.lua'))
end

function T.command_jumps_from_the_cursor_action()
  local buf = h.edit(BOOKS)
  local row = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "render view: 'show'")
  vim.api.nvim_win_set_cursor(0, { row + 1, 8 })
  vim.cmd 'GrailsAlternate'
  h.eq(h.path 'web/grails-app/views/book/show.gsp', vim.api.nvim_buf_get_name(0))
  vim.cmd 'GrailsAlternate'
  h.eq(h.path(BOOKS), vim.api.nvim_buf_get_name(0))
  h.eq(13, vim.api.nvim_win_get_cursor(0)[1])
end

return T
