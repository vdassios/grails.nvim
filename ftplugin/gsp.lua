vim.bo.commentstring = '<%-- %s --%>'
vim.b.undo_ftplugin = (vim.b.undo_ftplugin and vim.b.undo_ftplugin .. ' | ' or '') .. 'setlocal commentstring<'
