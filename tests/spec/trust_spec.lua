local h = require 'helpers'
local ls = require 'grails.ls'
local trust = require 'grails.trust'

local T = {}

--- Writes `files` (path relative to a new temporary directory => lines) and returns that directory.
local function tree(files)
  local root = vim.fn.tempname()
  for rel, lines in pairs(files) do
    local path = root .. '/' .. rel
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(lines, path)
  end
  return root
end

--- A Grails build with one module, or a plain Gradle build when `grails` is false.
local function project(grails)
  local files = {
    ['settings.gradle'] = { "include 'app'" },
    ['gradlew'] = { '#!/bin/sh', 'touch "$(dirname "$0")/wrapper-ran"' },
    ['app/build.gradle'] = { "apply plugin: 'groovy'" },
    ['app/src/main/groovy/demo/Util.groovy'] = { 'package demo', 'class Util {}' },
  }
  if grails then
    files['app/grails-app/controllers/demo/DemoController.groovy'] = { 'package demo', 'class DemoController {}' }
  end
  return tree(files)
end

--- A fake grails-language-server that records each `initialize` request's params.
local function fake_server()
  local server = { inits = {} }
  server.cmd = function(dispatchers)
    local closing = false
    local function close()
      if not closing then
        closing = true
        dispatchers.on_exit(0, 0)
      end
    end
    return {
      request = function(method, params, callback)
        if method == 'initialize' then
          server.inits[#server.inits + 1] = params
        end
        local result = method == 'initialize' and { capabilities = {} } or vim.NIL
        vim.schedule(function()
          callback(nil, result)
        end)
        return true, 1
      end,
      notify = function(method)
        if method == 'exit' then
          close()
        end
        return true
      end,
      is_closing = function()
        return closing
      end,
      terminate = close,
    }
  end
  return server
end

--- Runs `fn` with grails_ls enabled on `server` (an existing jar, `java` = this nvim) and `vim.notify` recorded;
--- returns the notifications. `vim.notify_once` keeps its own memory, so each test uses a fresh root.
local function with_grails_ls(server, fn)
  local jar = vim.fn.tempname()
  vim.fn.writefile({}, jar)
  local saved_g, saved_notify, saved_cmd = vim.g.grails_ls, vim.notify, vim.lsp.config.grails_ls.cmd
  local notes = {}
  vim.g.grails_ls = { jar = jar, java = vim.v.progpath }
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level or vim.log.levels.INFO }
  end
  vim.lsp.config('grails_ls', { cmd = server.cmd })
  vim.lsp.enable 'grails_ls'
  local ok, err = pcall(fn)
  vim.lsp.enable('grails_ls', false)
  vim.wait(1000, function()
    return #vim.lsp.get_clients { name = 'grails_ls' } == 0
  end)
  vim.lsp.config('grails_ls', { cmd = saved_cmd })
  vim.g.grails_ls, vim.notify = saved_g, saved_notify
  assert(ok, err)
  return notes
end

local function edit(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

--- The grails_ls client attached to `buf` within `ms`, or nil.
local function client(buf, ms)
  local found
  vim.wait(ms or 500, function()
    found = vim.lsp.get_clients({ bufnr = buf, name = 'grails_ls' })[1]
    return found ~= nil and found.initialized
  end)
  return found
end

function T.allowlist_file_holds_real_paths()
  local root = project(true)
  local link = vim.fn.tempname()
  assert(vim.uv.fs_symlink(root, link))
  h.eq(false, trust.is_trusted(root))
  trust.trust(link)
  h.eq(true, trust.is_trusted(root), 'trusted through the symlink')
  h.eq(true, trust.is_trusted(link .. '/'))
  local data = vim.json.decode(table.concat(vim.fn.readfile(trust.file()), '\n'))
  h.eq(1, data.version)
  assert(vim.list_contains(data.roots, vim.uv.fs_realpath(root)), vim.inspect(data))
  assert(not vim.list_contains(data.roots, link), 'stored the symlink')
  h.eq(true, trust.revoke(root))
  h.eq(false, trust.is_trusted(link))
  h.eq(false, trust.revoke(root), 'already revoked')
end

function T.untrusted_root_gives_one_notice_and_no_client()
  local root = project(true)
  local server = fake_server()
  local notes = with_grails_ls(server, function()
    local buf = edit(root .. '/app/grails-app/controllers/demo/DemoController.groovy')
    h.eq(nil, client(buf))
    edit(root .. '/app/src/main/groovy/demo/Util.groovy')
    vim.wait(50)
  end)
  h.eq({}, server.inits)
  h.eq(1, #notes, vim.inspect(notes))
  assert(notes[1].msg:find(':GrailsTrust', 1, true), notes[1].msg)
  assert(notes[1].msg:find(root, 1, true), notes[1].msg)
  h.eq(0, vim.fn.filereadable(root .. '/wrapper-ran'))
end

function T.untrusted_root_keeps_the_lua_server()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  h.eq(false, trust.is_trusted(h.app))
  local lua_client = h.client(buf)
  local row, col = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '/book/row', 1)
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
  h.eq(1, #lua_client:request_sync('textDocument/definition', params, 1000, buf).result)
end

function T.trusting_starts_the_client_and_revoking_stops_it()
  local root = project(true)
  local server = fake_server()
  local notes = with_grails_ls(server, function()
    local controller = edit(root .. '/app/grails-app/controllers/demo/DemoController.groovy')
    local util = edit(root .. '/app/src/main/groovy/demo/Util.groovy')
    h.eq(nil, client(util, 100))
    vim.cmd 'GrailsTrust'
    local started = client(util)
    assert(started, 'no client after :GrailsTrust')
    h.eq(started, client(controller), 'one client for both open buffers')
    h.eq(1, #server.inits)
    h.eq(true, server.inits[1].initializationOptions.trusted)

    vim.cmd 'GrailsUntrust'
    vim.wait(1000, function()
      return started:is_stopped()
    end)
    assert(started:is_stopped(), 'client still running after :GrailsUntrust')
    h.eq(false, trust.is_trusted(root))
  end)
  local msgs = vim.tbl_map(function(n)
    return n.msg
  end, notes)
  assert(msgs[#msgs]:find 'no longer trusted', vim.inspect(msgs))
end

function T.symlinked_path_to_a_trusted_root_starts_the_client()
  local root = project(true)
  local link = vim.fn.tempname()
  assert(vim.uv.fs_symlink(root, link))
  trust.trust(root)
  local server = fake_server()
  with_grails_ls(server, function()
    local buf = edit(link .. '/app/src/main/groovy/demo/Util.groovy')
    assert(client(buf), 'no client through the symlink')
    h.eq(true, server.inits[1].initializationOptions.trusted)
  end)
  trust.revoke(root)
end

function T.plain_gradle_build_never_starts_a_client()
  local root = project(false)
  trust.trust(root)
  local server = fake_server()
  local notes = with_grails_ls(server, function()
    h.eq(nil, client(edit(root .. '/app/src/main/groovy/demo/Util.groovy')))
    h.eq(nil, client(edit(root .. '/app/build.gradle'), 100))
    vim.cmd 'GrailsTrust'
  end)
  trust.revoke(root)
  h.eq({}, server.inits)
  h.eq({ { msg = 'GrailsTrust: this buffer is not in a Grails project', level = vim.log.levels.WARN } }, notes)
end

function T.build_files_in_a_trusted_root_start_none()
  local root = project(true)
  vim.fn.writefile({ 'pipeline {}' }, root .. '/Jenkinsfile')
  trust.trust(root)
  local server = fake_server()
  with_grails_ls(server, function()
    for _, rel in ipairs { 'settings.gradle', 'app/build.gradle', 'Jenkinsfile' } do
      local buf = edit(root .. '/' .. rel)
      vim.bo[buf].filetype = 'groovy'
      h.eq(nil, client(buf, 100), rel)
    end
  end)
  trust.revoke(root)
  h.eq({}, server.inits)
end

function T.trusted_is_computed_whatever_starts_the_client()
  local root = project(true)
  local server = fake_server()
  local buf = edit(root .. '/app/src/main/groovy/demo/Util.groovy')
  -- Started directly, bypassing root_dir, with a config that claims trust.
  local config = vim.tbl_extend('force', vim.lsp.config.grails_ls, { cmd = server.cmd, root_dir = root, init_options = { trusted = true } })
  local id = assert(vim.lsp.start(config, { bufnr = buf }))
  local started = assert(client(buf))
  h.eq(false, server.inits[1].initializationOptions.trusted)
  started:stop(true)
  vim.wait(1000, function()
    return started:is_stopped()
  end)
  h.eq(true, vim.lsp.get_client_by_id(id) == nil or started:is_stopped())
end

return T
