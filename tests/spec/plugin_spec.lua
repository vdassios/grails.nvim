local h = require 'helpers'

local T = {}

function T.reindex_drops_the_cache()
  local project = require 'grails.project'
  local before = project.modules(h.app)
  vim.cmd 'GrailsReindex'
  local after = project.modules(h.app)
  h.eq(before, after)
  assert(before ~= after, 'the module list was not rebuilt')
end

return T
