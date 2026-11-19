local h = require 'helpers'
local keymaps = require 'grails.keymaps'

local T = {}

local controller = 'core/grails-app/controllers/bookshop/BookController.groovy'

--- Edits `rel` in a new buffer, so FileType runs again (another spec may have it loaded).
local function fresh(rel)
  local old = vim.fn.bufnr(h.path(rel))
  if old ~= -1 then
    vim.cmd.bwipeout { old, bang = true }
  end
  return h.edit(rel)
end

--- The normal-mode mapping of `lhs` (`<localleader>` is `\` in the tests) in the current buffer.
local function map(lhs)
  return vim.fn.maparg(lhs:gsub('<localleader>', '\\'), 'n', false, true)
end

function T.defaults_in_a_grails_buffer()
  fresh(controller)
  for _, m in ipairs(keymaps.defaults) do
    local got = map(m.lhs)
    h.eq(m.plug, got.rhs, m.lhs)
    h.eq(1, got.buffer, m.lhs)
  end
  -- The key runs the command: \Gi rebuilds the Lua server's index.
  local project = require 'grails.project'
  local before = project.modules(h.app)
  vim.api.nvim_feedkeys(vim.keycode '\\Gi', 'mx', false)
  assert(before ~= project.modules(h.app), 'the module list was not rebuilt')
end

function T.defaults_in_gsp_buffers()
  fresh 'web/grails-app/views/book/show.gsp'
  h.eq('<Plug>(grails-alternate)', map('<localleader>Ga').rhs)
end

function T.defaults_are_undone_with_the_filetype()
  local buf = fresh 'web/grails-app/views/book/list.gsp'
  vim.bo[buf].filetype = 'text'
  for _, m in ipairs(keymaps.defaults) do
    h.eq(vim.empty_dict(), map(m.lhs), m.lhs)
  end
  h.eq(vim.empty_dict(), vim.fn.maparg('K', 'n', false, true), 'K (ftplugin/gsp.lua)')
  vim.bo[buf].filetype = 'gsp'
  h.eq('<Plug>(grails-alternate)', map('<localleader>Ga').rhs)
end

function T.no_defaults_outside_a_grails_project()
  local file = vim.fn.tempname() .. '.groovy'
  vim.fn.writefile({ 'class A {}' }, file)
  vim.cmd.edit(file)
  h.eq('groovy', vim.bo.filetype)
  h.eq(vim.empty_dict(), map '<localleader>Ga')
end

function T.a_user_mapping_to_the_plug_replaces_the_default()
  vim.keymap.set('n', '<F9>', '<Plug>(grails-alternate)')
  local ok, err = pcall(function()
    fresh(controller)
    h.eq(vim.empty_dict(), map '<localleader>Ga')
    h.eq('<Plug>(grails-reload-project)', map('<localleader>Gr').rhs)
  end)
  vim.keymap.del('n', '<F9>')
  assert(ok, err)
end

function T.a_key_already_mapped_is_left_alone()
  vim.keymap.set('n', '\\Gr', '<Cmd>echo<CR>')
  vim.keymap.set('n', '\\Gs', '<Cmd>echo<CR>')
  vim.keymap.set('n', '\\Gaz', '<Cmd>echo<CR>')
  local ok, err = pcall(function()
    fresh(controller)
    h.eq(0, map('<localleader>Gr').buffer)
    h.eq(0, map('<localleader>Gs').buffer)
    -- \Ga would make \Gaz wait for a timeout: not set either.
    h.eq(0, vim.fn.maparg('\\Gaz', 'n', false, true).buffer)
    h.eq(vim.empty_dict(), map '<localleader>Ga')
    h.eq('<Plug>(grails-reindex)', map('<localleader>Gi').rhs)
  end)
  for _, lhs in ipairs { '\\Gr', '\\Gs', '\\Gaz' } do
    vim.keymap.del('n', lhs)
  end
  assert(ok, err)
end

function T.defaults_can_be_turned_off()
  vim.g.grails_default_mappings = false
  local ok, err = pcall(function()
    fresh(controller)
    for _, m in ipairs(keymaps.defaults) do
      h.eq(vim.empty_dict(), map(m.lhs), m.lhs)
    end
  end)
  vim.g.grails_default_mappings = nil
  assert(ok, err)
end

function T.plug_mappings_exist()
  for _, m in ipairs(keymaps.defaults) do
    h.eq('<Cmd>' .. m.command .. '<CR>', vim.fn.maparg(m.plug, 'n'), m.plug)
  end
end

return T
