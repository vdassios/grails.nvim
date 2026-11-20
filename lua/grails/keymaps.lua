-- Default keymaps: buffer-local, in Groovy and GSP buffers of a Grails project, each to a <Plug> mapping that
-- plugin/grails.lua defines. A default is skipped when the user already maps its <Plug> mapping, or when its key
-- (or a prefix of it, or a longer key starting with it) is already mapped, so no existing mapping is replaced.
-- `vim.g.grails_default_mappings = false` turns them all off.
local M = {}

--- @class grails.Keymap
--- @field lhs string
--- @field plug string
--- @field command string
--- @field desc string

--- @type grails.Keymap[]
M.defaults = {
  { lhs = '<localleader>Ga', plug = '<Plug>(grails-alternate)', command = 'GrailsAlternate', desc = 'Grails: alternate file' },
  { lhs = '<localleader>Gi', plug = '<Plug>(grails-reindex)', command = 'GrailsReindex', desc = 'Grails: read the source files again' },
  { lhs = '<localleader>GI', plug = '<Plug>(grails-install-server)', command = 'GrailsInstallServer', desc = 'Grails: install grails-language-server' },
  { lhs = '<localleader>Gr', plug = '<Plug>(grails-reload-project)', command = 'GrailsReloadProject', desc = 'Grails: reload the Gradle project' },
  { lhs = '<localleader>Gs', plug = '<Plug>(grails-download-sources)', command = 'GrailsDownloadSources', desc = 'Grails: download sources jars' },
}

--- Defines the <Plug> mappings (global, normal mode).
function M.define_plugs()
  for _, map in ipairs(M.defaults) do
    vim.keymap.set('n', map.plug, '<Cmd>' .. map.command .. '<CR>', { desc = map.desc })
  end
end

--- Sets the default keymaps that are free in `buf`, if it belongs to a Grails project.
--- @param buf integer
function M.set_defaults(buf)
  if vim.g.grails_default_mappings == false then
    return
  end
  if not require('grails.project').find_root(vim.api.nvim_buf_get_name(buf)) then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    local undo = {}
    for _, map in ipairs(M.defaults) do
      -- hasmapto and mapcheck see global mappings and those local to the current buffer.
      if vim.fn.hasmapto(map.plug, 'n') == 0 and vim.fn.mapcheck(map.lhs, 'n') == '' then
        vim.keymap.set('n', map.lhs, map.plug, { buffer = buf, desc = map.desc })
        undo[#undo + 1] = 'silent! nunmap <buffer> ' .. map.lhs
      end
    end
    if #undo > 0 then
      -- No space before a `|`: `:unmap` takes trailing spaces as part of the key (`nunmap <buffer> K | ...`).
      local prev = vim.b.undo_ftplugin
      vim.b.undo_ftplugin = (prev and prev ~= '' and prev .. '| ' or '') .. table.concat(undo, '| ')
    end
  end)
end

return M
