-- The go-to-definition cases of the Lua server and grails-language-server, on the server repository's
-- `fixtures/grails4` project. tests/spec/integration_spec.lua runs each against the Lua server alone, then against
-- grails_ls once it is ready: a case's target must come from exactly the servers it names, and the other gives none.
--
-- This list is the Lua server's scope, frozen (docs/lua-server.md): it covers the `both` and `lua` cases and nothing
-- more, and grails_ls must cover every `both` case, because the Lua server goes silent once grails_ls is ready.
--
-- Each case: `file` below the fixture root; the cursor `at` bytes into the first occurrence of `text` in it; the
-- `target` file, at the line holding its text (line 0 without one); `servers`: 'both', 'lua' or 'java'.
local VIEWS = 'app/grails-app/views/'
local INDEX, LAYOUT = VIEWS .. 'book/index.gsp', VIEWS .. 'layouts/main.gsp'
local ROW = { VIEWS .. 'book/_row.gsp' }
local MAIN = { LAYOUT }
local CONTROLLERS = 'app/grails-app/controllers/fixture/library/'
local BOOKS, AUTHORS = CONTROLLERS .. 'BookController.groovy', CONTROLLERS .. 'AuthorController.groovy'
local MAPPINGS = CONTROLLERS .. 'UrlMappings.groovy'
local BOOK_CLASS = { BOOKS, 'class BookController' }
local CSS, JS = { 'app/grails-app/assets/stylesheets/main.css' }, { 'app/grails-app/assets/javascripts/app.js' }

--- @class grails.DefinitionCase
--- @field kind string
--- @field file string
--- @field text string
--- @field at integer
--- @field target string[] path below the fixture root, then the text of the target line
--- @field servers 'both'|'lua'|'java'

--- @type grails.DefinitionCase[]
return {
  -- GSP
  { kind = 'g:render template, relative', file = INDEX, text = 'template="row"', at = 11, target = ROW, servers = 'both' },
  { kind = 'g:render template, absolute', file = INDEX, text = 'template="/book/row"', at = 12, target = ROW, servers = 'both' },
  { kind = '<tmpl:name/>', file = INDEX, text = '<tmpl:row/>', at = 7, target = ROW, servers = 'both' },
  { kind = '<tmpl:/a/b/>', file = INDEX, text = '<tmpl:/book/row/>', at = 8, target = ROW, servers = 'both' },
  -- Relative names start from the controller rendering the page: its directory below views/, not the page's own.
  { kind = 'g:render template, nested page', file = VIEWS .. 'book/part/shelf.gsp', text = 'template="row"', at = 11, target = ROW, servers = 'both' },
  { kind = 'g:render contextPath', file = LAYOUT, text = 'template="row"', at = 11, target = ROW, servers = 'both' },
  { kind = 'g:include view, .gson', file = INDEX, text = 'view="summary"', at = 7, target = { VIEWS .. 'book/summary.gson' }, servers = 'both' },
  { kind = '<meta name="layout">', file = INDEX, text = 'content="main"', at = 10, target = MAIN, servers = 'both' },
  { kind = 'g:applyLayout name', file = INDEX, text = 'name="main"', at = 7, target = MAIN, servers = 'both' },
  { kind = 'asset:stylesheet src', file = INDEX, text = 'src="main.css"', at = 6, target = CSS, servers = 'both' },
  { kind = 'asset:javascript src, no extension', file = INDEX, text = 'src="app"', at = 6, target = JS, servers = 'both' },
  { kind = 'asset:link href', file = INDEX, text = 'href="main.css"', at = 7, target = CSS, servers = 'both' },
  { kind = 'g: tag controller', file = INDEX, text = 'controller="book" action="show"', at = 13, target = BOOK_CLASS, servers = 'both' },
  { kind = 'g: tag action, named controller', file = INDEX, text = 'action="show" id', at = 9, target = { BOOKS, 'def show(' }, servers = 'both' },
  { kind = "g: tag action, the view's controller", file = INDEX, text = 'action="save"', at = 9, target = { BOOKS, 'def save(' }, servers = 'both' },
  -- grails_ls reads controller and action only on g: tags: other namespaces use the names for their own ends.
  { kind = 'controller of another namespace', file = INDEX, text = 'sec:link controller="book"', at = 22, target = BOOK_CLASS, servers = 'lua' },
  -- Groovy
  { kind = 'render view, relative', file = BOOKS, text = 'view: "index"', at = 8, target = { VIEWS .. 'book/index.gsp' }, servers = 'both' },
  { kind = 'render view, .jsp', file = AUTHORS, text = 'view: "/book/legacy"', at = 9, target = { VIEWS .. 'book/legacy.jsp' }, servers = 'both' },
  { kind = 'render template', file = AUTHORS, text = 'template: "/book/row"', at = 13, target = ROW, servers = 'both' },
  { kind = 'static layout', file = AUTHORS, text = 'layout = "main"', at = 11, target = MAIN, servers = 'both' },
  { kind = 'redirect controller', file = AUTHORS, text = 'redirect(controller: "book"', at = 23, target = BOOK_CLASS, servers = 'both' },
  { kind = 'redirect action, named controller', file = AUTHORS, text = '"book", action: "index"', at = 18, target = { BOOKS, 'def index(' }, servers = 'both' },
  { kind = 'chain action, own controller', file = AUTHORS, text = 'chain(action: "index")', at = 16, target = { AUTHORS, 'def index(' }, servers = 'both' },
  { kind = 'forward action', file = AUTHORS, text = '"book", action: "show"', at = 18, target = { BOOKS, 'def show(' }, servers = 'both' },
  { kind = 'createLink controller', file = AUTHORS, text = 'createLink(controller: "book")', at = 25, target = BOOK_CLASS, servers = 'both' },
  { kind = 'g.link action', file = AUTHORS, text = 'g.link(action: "legacy")', at = 17, target = { AUTHORS, 'def legacy(' }, servers = 'both' },
  { kind = 'respond view', file = AUTHORS, text = 'view: "/book/index"', at = 9, target = { VIEWS .. 'book/index.gsp' }, servers = 'java' },
  { kind = 'static allowedMethods key', file = AUTHORS, text = 'save: "POST"', at = 1, target = { AUTHORS, 'def save(' }, servers = 'java' },
  { kind = 'UrlMappings controller', file = MAPPINGS, text = 'controller: "book"', at = 14, target = BOOK_CLASS, servers = 'java' },
}
