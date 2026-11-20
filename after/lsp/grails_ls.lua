-- grails-language-server (https://github.com/vdassios/grails-language-server). `:GrailsInstallServer` downloads it.
-- It runs the project's Gradle build and its AST transformations, so it starts only in a root the user trusts
-- (`:GrailsTrust`, lua/grails/trust.lua), and `initializationOptions.trusted` comes from that allowlist.
-- Under after/ so it merges over any other lsp/grails_ls.lua on 'runtimepath' (nvim-lspconfig's), whatever the
-- plugin load order; the user's vim.lsp.config('grails_ls', ...) still wins (:help lsp-config-merge).
local ls = require 'grails.ls'

---@type vim.lsp.Config
return {
  -- A function, so the jar and `java` are looked up at each start (`vim.g.grails_ls`, `:GrailsInstallServer`), for
  -- the client's own root. `root_dir` checks the jar and `java` only while `cmd` is this function.
  cmd = ls.rpc,
  filetypes = { 'groovy', 'gsp' },
  root_dir = ls.root_dir,
  before_init = ls.before_init,
  -- Warns once when the server is older than this plugin needs.
  on_init = ls.on_init,
  handlers = {
    ['grails/status'] = ls.on_status,
  },
}
