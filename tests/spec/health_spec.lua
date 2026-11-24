-- `:checkhealth grails`, and the notice when a parser the Lua server reads with is missing.
local h = require 'helpers'
local trust = require 'grails.trust'
local util = require 'grails.util'

local T = {}

--- Runs `fn` with `vim.notify` recorded; returns the notifications.
local function notes_of(fn)
  local saved = vim.notify
  local notes = {}
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level or vim.log.levels.INFO }
  end
  local ok, err = pcall(fn)
  vim.notify = saved
  assert(ok, err)
  return notes
end

function T.a_missing_parser_is_notified_once()
  local buf = h.edit 'core/grails-app/controllers/bookshop/BookController.groovy'
  local client = h.client(buf)
  local row, col = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "view: 'show'", 7)
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
  local add, get_parser = vim.treesitter.language.add, vim.treesitter.get_parser
  vim.treesitter.language.add = function(lang, ...)
    if lang == 'groovy' then
      return nil, 'no parser for groovy'
    end
    return add(lang, ...)
  end
  vim.treesitter.get_parser = function(source, lang, ...)
    if lang == 'groovy' then
      return nil
    end
    return get_parser(source, lang, ...)
  end
  util.missing_parsers = {}
  local results = {}
  local ok, notes = pcall(notes_of, function()
    for i = 1, 2 do
      results[i] = client:request_sync('textDocument/definition', params, 2000, buf).result
    end
  end)
  vim.treesitter.language.add, vim.treesitter.get_parser = add, get_parser
  util.missing_parsers = {}
  assert(ok, notes)
  h.eq({ {}, {} }, results, 'nothing found without the parser')
  h.eq(1, #notes, 'notified once')
  h.eq(vim.log.levels.WARN, notes[1].level)
  assert(notes[1].msg:find('`groovy`', 1, true) and notes[1].msg:find(':checkhealth grails', 1, true), notes[1].msg)
  h.eq(1, #client:request_sync('textDocument/definition', params, 2000, buf).result, 'found again with the parser')
end

--- A fake JDK whose `java -version` prints `version`. Returns its `bin/java`.
local function jdk(version)
  local java = vim.fn.tempname() .. '/bin/java'
  vim.fn.mkdir(vim.fs.dirname(java), 'p')
  vim.fn.writefile({ '#!/bin/sh', ("echo '%s' >&2"):format(version) }, java)
  vim.fn.setfperm(java, 'rwxr-xr-x')
  return java
end

--- The report of `:checkhealth grails`, run with `vim.g.grails_ls` = `settings`, as one string.
local function health(settings)
  local saved = vim.g.grails_ls
  vim.g.grails_ls = settings
  local ok, err = pcall(vim.cmd.checkhealth, 'grails')
  -- Neovim 0.13 runs the checks in an async task; every version sets the filetype once the report is written.
  local done = ok and vim.wait(10000, function()
    return vim.bo.filetype == 'checkhealth'
  end)
  vim.g.grails_ls = saved
  assert(ok, err)
  assert(done, ':checkhealth grails did not finish')
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  vim.cmd.bwipeout()
  return report
end

local function has(report, text)
  assert(report:find(text, 1, true), ('%q not in the report:\n%s'):format(text, report))
end

function T.checkhealth_reports_parsers_tools_jar_jdk_and_trust()
  h.edit 'core/grails-app/controllers/bookshop/BookController.groovy'
  local missing = vim.fn.tempname() .. '/server.jar'
  local java = jdk 'openjdk version "17.0.19" 2026-04-21'
  trust.revoke(h.app)
  local report = health { jar = missing, java = java }
  for _, lang in ipairs { 'groovy', 'html', 'gsp' } do
    has(report, ('`%s` parser'):format(lang))
  end
  has(report, 'curl')
  has(report, 'ERROR no server jar at ' .. missing)
  has(report, ('%s: not trusted'):format(h.app))
  has(report, ('`%s` is Java 17'):format(java))
  trust.trust(h.app)
  local jar = vim.fn.tempname()
  vim.fn.writefile({}, jar)
  report = health { jar = jar, java = jdk 'java version "1.8.0_412"' }
  trust.revoke(h.app)
  has(report, 'OK server jar: ' .. jar)
  has(report, ('OK %s: trusted'):format(h.app))
  has(report, 'is Java 8; the server needs Java 11 or later')
end

function T.checkhealth_without_a_grails_buffer()
  vim.cmd 'silent! %bwipeout!'
  local report = health { java = jdk 'openjdk version "21.0.13" 2026-01-20' }
  has(report, 'no Groovy or GSP file of a Grails project is open')
  has(report, 'is Java 21')
end

return T
