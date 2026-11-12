local h = require 'helpers'
local context = require 'grails.context'
local util = require 'grails.util'

local T = {}

--- Context at the `offset`-th byte of the `nth` match of `needle` in a fixture file.
local function at(rel, needle, offset, nth)
  local doc = assert(util.read(h.path(rel)))
  local row, col = h.pos(doc.lines, needle, offset, nth)
  local lang = rel:match '%.gsp$' and 'gsp' or 'groovy'
  return context.at(doc, lang, row, col)
end

local LIST = 'web/grails-app/views/book/list.gsp'
local BOOKS = 'core/grails-app/controllers/bookshop/BookController.groovy'

function T.gsp_attribute_value()
  local ctx = at(LIST, '/book/row', 2)
  h.eq({ ns = 'g', name = 'render' }, ctx.tag)
  h.eq('template', ctx.attr)
  h.eq('/book/row', ctx.value)
  local row, col = h.pos(util.read(h.path(LIST)).lines, '/book/row')
  h.eq({ row, col, row, col + #'/book/row' }, ctx.value_range)
end

function T.gsp_other_attributes()
  local ctx = at(LIST, 'action="show" id="${book.author', 9)
  h.eq('action', ctx.attr)
  h.eq('show', ctx.value)
  h.eq('author', ctx.attrs.controller)
  h.eq(nil, ctx.attrs.id) -- `${}` values are not plain
end

function T.gsp_tmpl_tag_name()
  local ctx = at(LIST, 'tmpl:/shared/footer', 6)
  h.eq({ ns = 'tmpl', name = '/shared/footer' }, ctx.tag)
  h.eq(nil, ctx.attr)
  h.eq('/shared/footer', ctx.value)
end

function T.gsp_meta_layout()
  local ctx = at(LIST, 'content="main"', 10)
  h.eq({ name = 'meta' }, ctx.tag)
  h.eq('main', ctx.value)
  h.eq('layout', ctx.attrs.name)
end

function T.gsp_computed_value_has_no_value()
  local ctx = at(LIST, '/book/${kind}', 2)
  h.eq('template', ctx.attr)
  h.eq(nil, ctx.value)
end

function T.gsp_inside_expression_is_nil()
  h.eq(nil, at(LIST, '${books}', 3))
  h.eq(nil, at(LIST, '[book: book]', 2))
end

function T.gsp_plain_html_is_nil()
  h.eq(nil, at(LIST, '<body>', 2))
end

function T.groovy_named_argument()
  local ctx = at(BOOKS, '/book/list', 2)
  h.eq('render', ctx.call)
  h.eq('view', ctx.named_arg)
  h.eq('/book/list', ctx.value)
  h.eq('BookController', ctx.enclosing_class)
  h.eq('index', ctx.enclosing_method)
end

function T.groovy_command_call_without_parentheses()
  local ctx = at(BOOKS, "view: 'show'", 8)
  h.eq('render', ctx.call)
  h.eq('show', ctx.value)
  h.eq('show', ctx.enclosing_method)
end

function T.groovy_other_named_arguments()
  local ctx = at(BOOKS, "action: 'show', id", 9)
  h.eq('redirect', ctx.call)
  h.eq('action', ctx.named_arg)
  h.eq({ controller = 'author', action = 'show' }, ctx.args)
  h.eq('save', ctx.enclosing_method) -- a closure property
end

function T.groovy_static_property()
  local ctx = at(BOOKS, "'main'", 1)
  h.eq('layout', ctx.property)
  h.eq('main', ctx.value)
end

function T.groovy_gstring_has_no_value()
  local ctx = at(BOOKS, '/book/${actionName}', 2)
  h.eq('view', ctx.named_arg)
  h.eq(nil, ctx.value)
end

function T.groovy_outside_a_string_is_nil()
  h.eq(nil, at(BOOKS, 'bookService.list', 2))
end

-- Line fallback, used inside a groovy ERROR node -------------------------------

local function scan(line, needle, offset)
  local _, col = h.pos({ line }, needle, offset)
  return context.scan_line(line, 7, col)
end

function T.scan_line_call_with_parentheses()
  local line = [[        render(view: "/book/list", model: [books: books])]]
  local ctx = scan(line, '/book/list', 2)
  h.eq('render', ctx.call)
  h.eq('view', ctx.named_arg)
  h.eq('/book/list', ctx.value)
  local _, col = h.pos({ line }, '/book/list')
  h.eq({ 7, col, 7, col + #'/book/list' }, ctx.value_range)
end

function T.scan_line_command_call_second_argument()
  local ctx = scan([[    g.redirect controller: 'author', action: "show"]], 'show', 1)
  h.eq('redirect', ctx.call)
  h.eq('action', ctx.named_arg)
  h.eq({ controller = 'author', action = 'show' }, ctx.args)
end

function T.scan_line_gstring_has_no_value()
  local ctx = scan([[render(view: "/book/${name}")]], '/book', 1)
  h.eq('view', ctx.named_arg)
  h.eq(nil, ctx.value)
  h.eq('/book/${x}', scan([[render(view: '/book/${x}')]], '/book', 1).value) -- single quotes do not interpolate
end

function T.scan_line_without_a_call_is_nil()
  h.eq(nil, scan([[def m = [view: 'show'] ]], 'show', 1))
  h.eq(nil, scan([[log.info "rendering"]], 'rendering', 1))
  h.eq(nil, scan([[render(view: 'show')]], 'render', 1)) -- cursor outside the string
end

return T
