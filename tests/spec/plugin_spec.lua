local h = require 'helpers'

local T = {}

function T.gsp_commentstring()
  h.edit 'web/grails-app/views/book/list.gsp'
  h.eq('gsp', vim.bo.filetype)
  h.eq('<%-- %s --%>', vim.bo.commentstring)
end

--- An in-process language server that answers hover.
local function hover_server()
  return {
    request = function(method, _, callback)
      local result = method == 'initialize' and { capabilities = { hoverProvider = true } } or nil
      vim.schedule(function()
        callback(nil, result)
      end)
      return true, 1
    end,
    notify = function()
      return true
    end,
    is_closing = function()
      return false
    end,
    terminate = function() end,
  }
end

--- Runs `K` in normal mode with hover and notify stubbed; returns how often each was called.
local function press_k()
  local hover, notify = vim.lsp.buf.hover, vim.notify
  local calls = { hover = 0, notify = 0 }
  vim.lsp.buf.hover = function()
    calls.hover = calls.hover + 1
  end
  vim.notify = function()
    calls.notify = calls.notify + 1
  end
  local ok, err = pcall(vim.cmd.normal, 'K')
  vim.lsp.buf.hover, vim.notify = hover, notify
  assert(ok, err)
  return calls
end

function T.k_without_a_hover_server_never_runs_man()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  h.eq(0, #vim.lsp.get_clients { bufnr = buf, method = 'textDocument/hover' })
  local wins = #vim.api.nvim_list_wins()
  h.eq({ hover = 0, notify = 1 }, press_k())
  h.eq(wins, #vim.api.nvim_list_wins(), 'no :Man window')
end

function T.k_with_a_hover_server_hovers()
  local buf = h.edit 'web/grails-app/views/book/show.gsp'
  local id = assert(vim.lsp.start({ name = 'hover-test', cmd = hover_server, root_dir = h.app }, { bufnr = buf }))
  vim.wait(2000, function()
    return #vim.lsp.get_clients { bufnr = buf, method = 'textDocument/hover' } > 0
  end)
  h.eq({ hover = 1, notify = 0 }, press_k())
  vim.lsp.get_client_by_id(id):stop(true)
end

function T.k_mapping_is_undone_with_the_filetype()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  assert(vim.fn.maparg('K', 'n', false, true).buffer == 1, 'no buffer-local K')
  vim.bo[buf].filetype = 'text'
  h.eq(vim.empty_dict(), vim.fn.maparg('K', 'n', false, true))
  vim.bo[buf].filetype = 'gsp'
end

--- Edits `rel` in a new buffer, so FileType runs again (another spec may have it loaded).
local function fresh(rel)
  local old = vim.fn.bufnr(h.path(rel))
  if old ~= -1 then
    vim.cmd.bwipeout { old, bang = true }
  end
  return h.edit(rel)
end

function T.k_leaves_a_mapping_of_the_user_alone()
  vim.keymap.set('n', 'K', '<Cmd>echo<CR>')
  local ok, err = pcall(function()
    local buf = fresh 'web/grails-app/views/book/list.gsp'
    h.eq(0, vim.fn.maparg('K', 'n', false, true).buffer, 'the global K is kept')
    -- A buffer-local K of the user survives the filetype's undo, which removes only a K the ftplugin set.
    vim.keymap.set('n', 'K', '<Cmd>echo "mine"<CR>', { buffer = buf })
    vim.bo[buf].filetype = 'text'
    h.eq('<Cmd>echo "mine"<CR>', vim.fn.maparg('K', 'n', false, true).rhs)
    vim.keymap.del('n', 'K', { buffer = buf })
  end)
  vim.keymap.del('n', 'K')
  assert(ok, err)
end

function T.k_is_not_mapped_when_default_mappings_are_off()
  vim.g.grails_default_mappings = false
  local ok, err = pcall(function()
    fresh 'web/grails-app/views/book/list.gsp'
    h.eq(vim.empty_dict(), vim.fn.maparg('K', 'n', false, true))
  end)
  vim.g.grails_default_mappings = nil
  assert(ok, err)
end

return T
