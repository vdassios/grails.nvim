local h = require 'helpers'

local T = {}

function T.gsp_commentstring()
  h.edit 'web/grails-app/views/book/list.gsp'
  h.eq('gsp', vim.bo.filetype)
  h.eq('<%-- %s --%>', vim.bo.commentstring)
end

function T.reindex_drops_the_cache()
  local project = require 'grails.project'
  local before = project.modules(h.app)
  vim.cmd 'GrailsReindex'
  local after = project.modules(h.app)
  h.eq(before, after)
  assert(before ~= after, 'the module list was not rebuilt')
end

return T
