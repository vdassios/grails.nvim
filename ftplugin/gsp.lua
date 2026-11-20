vim.bo.commentstring = '<%-- %s --%>'

local undo = 'setlocal commentstring<'

-- `K` is LSP hover, or a message when no attached server answers hover. Without this mapping, `K` in a gsp buffer
-- with no hover server runs 'keywordprg' (`:Man` by default), so `K` on `<head>` opens `man head`. Setting
-- 'keywordprg' instead would stop Neovim from mapping `K` to hover when a server attaches. Like the default keys
-- (lua/grails/keymaps.lua), it is not set when `K` (or a key starting with it) is already mapped, or with
-- `vim.g.grails_default_mappings = false`, and the undo removes only a `K` set here.
if vim.g.grails_default_mappings ~= false and vim.fn.mapcheck('K', 'n') == '' then
  vim.keymap.set('n', 'K', function()
    if #vim.lsp.get_clients { bufnr = 0, method = 'textDocument/hover' } > 0 then
      vim.lsp.buf.hover()
    else
      vim.notify('No hover: no language server on this buffer answers it', vim.log.levels.INFO)
    end
  end, { buffer = true, desc = 'LSP hover (grails.nvim: never :Man)' })
  undo = undo .. '| silent! nunmap <buffer> K'
end

-- No space before a `|`: `:unmap` takes trailing spaces as part of the key.
local prev = vim.b.undo_ftplugin
vim.b.undo_ftplugin = (prev and prev ~= '' and prev .. '| ' or '') .. undo
