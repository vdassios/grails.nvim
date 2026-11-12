---@type vim.lsp.Config
return {
  cmd = function(dispatchers)
    return require('grails.server').start(dispatchers)
  end,
  filetypes = { 'gsp', 'groovy' },
  root_dir = function(bufnr, on_dir)
    local root = require('grails.project').find_root(vim.api.nvim_buf_get_name(bufnr))
    if root then
      on_dir(root)
    end
  end,
}
