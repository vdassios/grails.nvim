vim.bo.commentstring = '<%-- %s --%>'

-- `K` is LSP hover, or a message when no attached server answers hover. Without this mapping, `K` in a gsp buffer
-- with no hover server runs 'keywordprg' (`:Man` by default), so `K` on `<head>` opens `man head`. Setting
-- 'keywordprg' instead would stop Neovim from mapping `K` to hover when a server attaches.
vim.keymap.set('n', 'K', function()
  if #vim.lsp.get_clients { bufnr = 0, method = 'textDocument/hover' } > 0 then
    vim.lsp.buf.hover()
  else
    vim.notify('No hover: no language server on this buffer answers it', vim.log.levels.INFO)
  end
end, { buffer = true, desc = 'LSP hover (grails.nvim: never :Man)' })

vim.b.undo_ftplugin = (vim.b.undo_ftplugin and vim.b.undo_ftplugin .. ' | ' or '') .. 'setlocal commentstring< | silent! nunmap <buffer> K'
