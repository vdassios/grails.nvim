local h = require 'helpers'

local T = {}

local PAGE = table.concat({
  '<%@ page contentType="text/html" %>',
  '<%-- note --%>',
  '<g:if test="${x}"><g:render model="[a: 1]"/></g:if>',
  '%{ x.each { y }}%',
  '<script>var n = 1 << 2;</script>',
}, '\n')

--- The query file `queries/gsp/<name>.scm` of this checkout, parsed for the built `gsp` parser.
local function query(name)
  local path = h.root .. '/queries/gsp/' .. name .. '.scm'
  return vim.treesitter.query.parse('gsp', table.concat(assert(vim.fn.readfile(path)), '\n'))
end

--- `{ [capture] = { node text, ... } }` of `name` over PAGE.
local function captures(name)
  local q = query(name)
  local root = vim.treesitter.get_string_parser(PAGE, 'gsp'):parse()[1]:root()
  assert(not root:has_error(), 'the sample page has a parse error')
  local found = {}
  for id, node in q:iter_captures(root, PAGE) do
    local capture = q.captures[id]
    found[capture] = found[capture] or {}
    table.insert(found[capture], vim.treesitter.get_node_text(node, PAGE))
  end
  return found
end

function T.highlights()
  local found = captures 'highlights'
  h.eq({ 'g', 'g', 'g' }, found.module)
  h.eq({ 'if', 'render', 'if' }, found.tag)
  h.eq({ 'page' }, found['keyword.directive'])
  h.eq({ '<%-- note --%>' }, found.comment)
  assert(vim.list_contains(found['punctuation.special'], '}}%'), vim.inspect(found['punctuation.special']))
end

function T.injections()
  local q = query 'injections'
  local root = vim.treesitter.get_string_parser(PAGE, 'gsp'):parse()[1]:root()
  local found = { groovy = {}, html = {} }
  for _, match, metadata in q:iter_matches(root, PAGE) do
    for id, nodes in pairs(match) do
      if q.captures[id] == 'injection.content' then
        for _, node in ipairs(nodes) do
          table.insert(found[metadata['injection.language']], vim.treesitter.get_node_text(node, PAGE))
        end
      end
    end
  end
  h.eq({ 'x', '[a: 1]', ' x.each { y ' }, found.groovy)
  h.eq('<script>var n = 1 << 2;</script>', table.concat(found.html):match '<script>.*$')
end

function T.folds()
  h.eq({ '<%-- note --%>', '<g:if test="${x}">', '<g:render model="[a: 1]"/>', '%{ x.each { y }}%' }, captures('folds').fold)
end

return T
