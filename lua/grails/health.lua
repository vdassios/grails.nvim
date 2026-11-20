-- `:checkhealth grails`: the parsers, the tools `:GrailsInstallServer` runs, the server jar, and for each open Grails
-- project its trust state and the JDK grails_ls would run on.
local M = {}

local health = vim.health

--- Parsers: `lang` => what is lost without it, and whether that is an error.
local PARSERS = {
  { lang = 'groovy', error = true, without = 'the Lua server finds nothing in Groovy code, and GSP pages have no Groovy highlighting' },
  { lang = 'gsp', error = true, without = 'GSP pages have no highlighting, folds or injections, and the Lua server finds nothing in them' },
  { lang = 'html', error = false, without = 'the HTML of GSP pages is not highlighted' },
}

local function parsers()
  health.start 'tree-sitter parsers'
  for _, p in ipairs(PARSERS) do
    local ok, err = vim.treesitter.language.add(p.lang)
    if ok then
      health.ok(('`%s` parser'):format(p.lang))
    else
      local report = p.error and health.error or health.warn
      local install = p.lang == 'gsp' and ':TSInstall gsp, or build it from tree-sitter-gsp/ (docs/grammar.md)' or (':TSInstall ' .. p.lang)
      report(('no `%s` parser (%s): %s'):format(p.lang, err or 'not found', p.without), { install })
    end
  end
end

local function tools()
  health.start ':GrailsInstallServer'
  if vim.fn.executable 'curl' == 1 then
    health.ok '`curl` found'
  else
    health.warn('`curl` not found: :GrailsInstallServer cannot download the server', {
      'Install curl, or download the jar yourself and set vim.g.grails_ls.jar.',
    })
  end
  local sum = vim.fn.executable 'sha256sum' == 1 and 'sha256sum' or vim.fn.executable 'shasum' == 1 and 'shasum' or nil
  if sum then
    health.ok(('`%s` found'):format(sum))
  else
    health.warn('neither `sha256sum` nor `shasum` found: :GrailsInstallServer cannot check a download', { 'Install coreutils.' })
  end
end

--- Reports the `java` grails_ls runs on for `root` (nil: no project root), with its `java -version`.
--- @param root? string
local function jdk(root)
  local ls = require 'grails.ls'
  local java = ls.java(root)
  if vim.fn.executable(java) ~= 1 then
    health.error(('`%s` is not executable'):format(java), { "Set JAVA_HOME, the project's JDK or vim.g.grails_ls.java." })
    return
  end
  local ok, res = pcall(function()
    return vim.system({ java, '-version' }, { text = true }):wait(10000)
  end)
  if not ok then
    health.error(('`%s` could not be run: %s'):format(java, res))
    return
  end
  local version, problem = ls.java_version(java, res)
  if problem then
    health.error(problem)
  elseif version then
    health.ok(('`%s` is Java %d'):format(java, version))
  else
    health.ok(('`%s` runs (version not read)'):format(java))
  end
end

--- The Grails roots of the loaded Groovy and GSP buffers, sorted.
--- @return string[]
local function roots()
  local ls = require 'grails.ls'
  local found = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.bo[buf].filetype
    if vim.api.nvim_buf_is_loaded(buf) and (ft == 'groovy' or ft == 'gsp') then
      local root = ls.project_root(buf)
      if root then
        found[root] = true
      end
    end
  end
  local list = vim.tbl_keys(found)
  table.sort(list)
  return list
end

local function server()
  local ls = require 'grails.ls'
  health.start 'grails_ls'
  if vim.lsp.is_enabled(ls.name) then
    health.ok '`grails_ls` is enabled'
  else
    health.info "`grails_ls` is not enabled: vim.lsp.enable 'grails_ls' turns it on"
  end
  local own_cmd = vim.lsp.config[ls.name].cmd ~= ls.rpc
  if own_cmd then
    health.info 'grails_ls runs your own `cmd`, so the jar and `java` are yours to check'
  else
    local jar = ls.jar()
    if vim.uv.fs_stat(jar) then
      health.ok('server jar: ' .. jar)
    else
      health.error('no server jar at ' .. jar, { 'Run :GrailsInstallServer, or set vim.g.grails_ls.jar.' })
    end
  end
  local trust = require 'grails.trust'
  local list = roots()
  if #list == 0 then
    health.info 'no Groovy or GSP file of a Grails project is open: open one to check its trust and JDK'
    if not own_cmd then
      jdk(nil)
    end
    return
  end
  for _, root in ipairs(list) do
    health.start('grails_ls in ' .. root)
    if trust.is_trusted(root) then
      health.ok(root .. ': trusted')
    else
      health.warn(root .. ': not trusted, so grails_ls does not start there', { 'Run :GrailsTrust in one of its files.' })
    end
    if not own_cmd then
      jdk(root)
    end
  end
end

function M.check()
  health.start 'grails.nvim'
  if vim.fn.has 'nvim-0.11.3' == 1 then
    health.ok 'Neovim 0.11.3 or later'
  else
    health.error 'grails.nvim needs Neovim 0.11.3 or later'
  end
  parsers()
  tools()
  server()
end

return M
