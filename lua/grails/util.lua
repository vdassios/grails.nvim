local M = {}

--- The loaded buffer for a file, if any. Never creates a buffer.
--- @param path string
--- @return integer?
function M.find_buf(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == path then
      return buf
    end
  end
end

--- @class grails.Doc
--- @field path string
--- @field buf? integer loaded buffer holding the file
--- @field lines string[]

--- A file's text: from its loaded buffer when there is one, otherwise from disk.
--- @param path string
--- @return grails.Doc?
function M.read(path)
  local buf = M.find_buf(path)
  if buf then
    return { path = path, buf = buf, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) }
  end
  local fd = io.open(path, 'rb')
  if not fd then
    return nil
  end
  local text = fd:read '*a'
  fd:close()
  return { path = path, lines = vim.split(text, '\n', { plain = true }) }
end

--- Parsers already reported missing (`lang` => true).
--- @type table<string, true>
M.missing_parsers = {}

--- Syntax tree root of a document, or nil when the parser is missing (notified once per parser).
--- A loaded buffer reuses its own parser only when its filetype maps to `lang`,
--- so that a highlighter's parser is never replaced.
--- @param doc grails.Doc
--- @param lang string
--- @return TSNode?
function M.parse(doc, lang)
  local parser
  if doc.buf and vim.treesitter.language.get_lang(vim.bo[doc.buf].filetype) == lang then
    parser = vim.treesitter.get_parser(doc.buf, lang, { error = false })
  elseif vim.treesitter.language.add(lang) then
    parser = vim.treesitter.get_string_parser(table.concat(doc.lines, '\n'), lang)
  end
  if not parser then
    if not M.missing_parsers[lang] then
      M.missing_parsers[lang] = true
      local text = 'grails: no `%s` tree-sitter parser, so go to definition and :GrailsAlternate find nothing in %s code. '
        .. 'Install it (:TSInstall %s); :checkhealth grails checks the rest.'
      vim.notify(text:format(lang, lang == 'gsp' and 'GSP' or 'Groovy', lang), vim.log.levels.WARN)
    end
    return nil
  end
  return parser:parse()[1]:root()
end

--- Text of a node, read from the document's lines.
--- @param doc grails.Doc
--- @param node TSNode
--- @return string
function M.node_text(doc, node)
  local sr, sc, er, ec = node:range()
  if sr == er then
    return doc.lines[sr + 1]:sub(sc + 1, ec)
  end
  local parts = { doc.lines[sr + 1]:sub(sc + 1) }
  for row = sr + 1, er - 1 do
    parts[#parts + 1] = doc.lines[row + 1]
  end
  parts[#parts + 1] = (doc.lines[er + 1] or ''):sub(1, ec)
  return table.concat(parts, '\n')
end

--- A UTF-8 LSP Location for a file, at line 0 or at a node's range.
--- @param path string
--- @param node? TSNode
--- @return lsp.Location
function M.location(path, node)
  local range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } }
  if node then
    local sr, sc, er, ec = node:range()
    range = { start = { line = sr, character = sc }, ['end'] = { line = er, character = ec } }
  end
  return { uri = vim.uri_from_fname(path), range = range }
end

return M
