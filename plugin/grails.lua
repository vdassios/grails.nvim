if vim.g.loaded_grails then
  return
end
vim.g.loaded_grails = true

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

-- Register the bundled GSP grammar with nvim-treesitter (main branch), so that
-- `:TSInstall gsp` builds it from this checkout. nvim-treesitter fires
-- `User TSUpdate` each time it reloads its parser table. The require is inside
-- the callback because nvim-treesitter may not be on the runtimepath yet when
-- this file is sourced.
vim.api.nvim_create_autocmd('User', {
  pattern = 'TSUpdate',
  group = vim.api.nvim_create_augroup('grails-parser', { clear = true }),
  callback = function()
    local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
    if ok then
      parsers.gsp = {
        install_info = { path = root .. '/tree-sitter-gsp' },
      }
    end
  end,
})

vim.api.nvim_create_user_command('GrailsAlternate', function()
  require('grails.alternate').jump()
end, { desc = 'Grails: go to the alternate file (action <-> view, domain <-> controller <-> service)' })

vim.api.nvim_create_user_command('GrailsReindex', function()
  require('grails.ls').reindex()
end, { desc = 'Grails: grails_ls reads the source files again, without Gradle' })

vim.api.nvim_create_user_command('GrailsInstallServer', function(opts)
  require('grails.ls').install(opts.bang, opts.args)
end, {
  bang = true,
  nargs = '?',
  desc = 'Grails: download the newest stable grails-language-server release, or the one tagged [tag] (! downloads it again)',
})

vim.api.nvim_create_user_command('GrailsReloadProject', function()
  require('grails.ls').reload_project()
end, { desc = 'Grails: grails_ls resolves the Gradle project again, ignoring its cache' })

vim.api.nvim_create_user_command('GrailsDownloadSources', function()
  require('grails.ls').download_sources()
end, { desc = "Grails: grails_ls fetches the libraries' missing sources jars" })

vim.api.nvim_create_user_command('GrailsTrust', function()
  require('grails.ls').trust()
end, { desc = "Grails: trust this buffer's project, so grails_ls may run its Gradle build" })

vim.api.nvim_create_user_command('GrailsUntrust', function()
  require('grails.ls').untrust()
end, { desc = "Grails: stop trusting this buffer's project and stop its grails_ls" })

-- <Plug>(grails-*) mappings for the commands, and default keys for them in Grails buffers (lua/grails/keymaps.lua).
require('grails.keymaps').define_plugs()
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'gsp', 'groovy' },
  group = vim.api.nvim_create_augroup('grails-keymaps', { clear = true }),
  callback = function(ev)
    require('grails.keymaps').set_defaults(ev.buf)
  end,
})
