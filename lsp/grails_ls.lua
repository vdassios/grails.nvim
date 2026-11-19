-- grails-language-server (https://github.com/vdassios/grails-language-server). `:GrailsInstallServer` downloads it.
-- It runs the project's Gradle build and its AST transformations, so enabling it trusts the project.
---@type vim.lsp.Config
return {
  -- a function, so the jar and `java` are looked up at each start (`vim.g.grails_ls`, `:GrailsInstallServer`)
  cmd = function(dispatchers)
    return vim.lsp.rpc.start(require('grails.ls').cmd(), dispatchers)
  end,
  filetypes = { 'groovy', 'gsp' },
  root_dir = function(bufnr, on_dir)
    require('grails.ls').root_dir(bufnr, on_dir)
  end,
  init_options = { trusted = true },
  -- on quit, wait for the server's shutdown (under a second when idle) so it gets `exit`; without it the JVM outlives
  -- Neovim by a minute
  exit_timeout = 5000,
  handlers = {
    ['grails/status'] = function(...)
      return require('grails.ls').on_status(...)
    end,
  },
}
