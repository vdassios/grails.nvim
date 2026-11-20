local h = require 'helpers'
local ls = require 'grails.ls'

local T = {}

--- Runs `fn` with `vim.g.grails_ls`, `$JAVA_HOME` and `vim.notify` replaced; returns the notifications.
local function with(settings, java_home, fn)
  local saved_g, saved_home, saved_notify, saved_once = vim.g.grails_ls, vim.env.JAVA_HOME, vim.notify, vim.notify_once
  local notes = {}
  vim.g.grails_ls, vim.env.JAVA_HOME = settings, java_home
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level or vim.log.levels.INFO }
  end
  vim.notify_once = vim.notify
  local ok, err = pcall(fn)
  vim.g.grails_ls, vim.env.JAVA_HOME, vim.notify, vim.notify_once = saved_g, saved_home, saved_notify, saved_once
  assert(ok, err)
  return notes
end

--- A fake grails-language-server: records requests, answers them from `answers`, and exposes the client's
--- dispatchers so a test can send `grails/status`.
local function fake_server(answers)
  local server = { requests = {} }
  server.cmd = function(dispatchers)
    server.dispatchers = dispatchers
    local closing = false
    local function close()
      if not closing then
        closing = true
        dispatchers.on_exit(0, 0)
      end
    end
    return {
      request = function(method, params, callback)
        server.requests[#server.requests + 1] = { method = method, params = params }
        local result = method == 'initialize' and { capabilities = { definitionProvider = true } } or (answers or {})[method]
        vim.schedule(function()
          callback(nil, result)
        end)
        return true, #server.requests
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
  function server.status(state, message)
    server.dispatchers.notification('grails/status', { state = state, message = message })
  end
  return server
end

--- Starts `server` as grails_ls on `buf`, with the handlers of after/lsp/grails_ls.lua.
local function start(server, buf)
  local config = vim.tbl_extend('force', vim.lsp.config.grails_ls, { cmd = server.cmd, root_dir = h.app })
  local client = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start(config, { bufnr = buf }))))
  vim.wait(2000, function()
    return client.initialized
  end)
  assert(client.initialized, 'grails_ls did not initialize')
  return client
end

local function stop_all()
  for _, client in ipairs(vim.lsp.get_clients { name = 'grails_ls' }) do
    client:stop(true)
  end
  vim.wait(1000, function()
    return #vim.lsp.get_clients { name = 'grails_ls' } == 0
  end)
end

function T.config_runs_the_jar_on_java_home()
  local home = vim.fn.tempname()
  vim.fn.mkdir(home .. '/bin', 'p')
  vim.fn.writefile({ '#!/bin/sh' }, home .. '/bin/java')
  vim.fn.setfperm(home .. '/bin/java', 'rwxr-xr-x')
  with(nil, home, function()
    h.eq({ home .. '/bin/java', '-jar', vim.fn.stdpath 'data' .. '/grails.nvim/grails-language-server-all.jar' }, ls.cmd())
  end)
  with({ java = '/opt/jdk/bin/java', jar = '/opt/gls.jar' }, home, function()
    h.eq({ '/opt/jdk/bin/java', '-jar', '/opt/gls.jar' }, ls.cmd())
  end)
  with(nil, '', function()
    h.eq('java', ls.cmd()[1])
  end)
  local config = vim.lsp.config.grails_ls
  h.eq({ 'groovy', 'gsp' }, config.filetypes)
  h.eq(nil, config.init_options, 'trusted comes from the allowlist (before_init), not a constant')
  h.eq('function', type(config.before_init))
  h.eq(nil, config.exit_timeout, 'Neovim quits without waiting: the server exits when its input ends')
end

function T.config_wins_over_another_grails_ls_on_the_runtimepath()
  -- nvim-lspconfig's lsp/grails_ls.lua, loaded before or after grails.nvim.
  local other = vim.fn.tempname()
  vim.fn.mkdir(other .. '/lsp', 'p')
  vim.fn.writefile({ "return { cmd = { 'grails-language-server' }, root_markers = { 'gradlew' } }" }, other .. '/lsp/grails_ls.lua')
  local saved = vim.o.runtimepath
  for _, order in ipairs { 'before', 'after' } do
    -- Plugin managers put plugin directories before every after/ directory (lazy.nvim, packages).
    local rtp = vim.opt.runtimepath:get()
    local at = order == 'before' and 1 or #rtp + 1
    for i, dir in ipairs(rtp) do
      if order == 'after' and dir:match '/after$' then
        at = i
        break
      end
    end
    table.insert(rtp, at, other)
    vim.opt.runtimepath = rtp
    local ok, err = pcall(function()
      local config = vim.lsp.config.grails_ls
      h.eq('function', type(config.cmd), order)
      h.eq('function', type(config.root_dir), order)
      h.eq('function', type(config.handlers['grails/status']), order)
    end)
    vim.o.runtimepath = saved
    assert(ok, err)
  end
end

function T.root_dir_is_the_trusted_gradle_root_once_the_jar_exists()
  local buf = h.edit 'core/grails-app/controllers/bookshop/BookController.groovy'
  local trust = require 'grails.trust'
  trust.trust(h.app)
  local roots = {}
  local function on_dir(root)
    roots[#roots + 1] = root
  end
  local notes = with({ jar = vim.fn.tempname(), java = vim.v.progpath }, nil, function()
    ls.root_dir(buf, on_dir)
  end)
  h.eq({}, roots)
  h.eq(vim.log.levels.WARN, notes[1].level)
  assert(notes[1].msg:find 'GrailsInstallServer', notes[1].msg)

  local jar = vim.fn.tempname()
  vim.fn.writefile({}, jar)
  with({ jar = jar, java = vim.v.progpath }, nil, function()
    ls.root_dir(buf, on_dir)
  end)
  trust.revoke(h.app)
  h.eq({ h.app }, roots)
end

function T.status_is_lsp_progress_and_a_failure_is_notified()
  local buf = h.edit 'core/grails-app/controllers/bookshop/BookController.groovy'
  local server = fake_server()
  local client = start(server, buf)
  local events = {}
  local group = vim.api.nvim_create_augroup('grails-ls-test', { clear = true })
  vim.api.nvim_create_autocmd('LspProgress', {
    group = group,
    callback = function(ev)
      local value = ev.data.params.value
      events[#events + 1] = value.kind .. ':' .. (value.message or '')
    end,
  })
  local notes = with(nil, nil, function()
    for _, state in ipairs { 'resolving', 'indexing', 'ready', 'resolving' } do
      server.status(state)
    end
    server.status('failed', 'Gradle exited with 1')
    vim.wait(100)
  end)
  vim.api.nvim_del_augroup_by_id(group)
  h.eq({ 'begin:resolving the project', 'report:indexing', 'end:ready', 'begin:resolving the project', 'end:failed' }, events)
  h.eq({ { msg = 'grails_ls: Gradle exited with 1', level = vim.log.levels.ERROR } }, notes)
  h.eq('failed', ls.states[client.id])
  stop_all()
end

function T.lua_server_leaves_definition_to_a_ready_grails_ls()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local lua_client = h.client(buf)
  local row, col = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '/book/row', 1)
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
  local function count()
    return #lua_client:request_sync('textDocument/definition', params, 1000, buf).result
  end
  h.eq(1, count())
  local server = fake_server()
  start(server, buf)
  server.status 'resolving'
  vim.wait(50)
  h.eq(1, count(), 'still answers while grails_ls resolves')
  server.status 'ready'
  vim.wait(50)
  h.eq(0, count())
  stop_all()
  h.eq(1, count(), 'answers again once grails_ls is gone')
end

function T.commands_send_the_server_requests()
  local buf = h.edit 'core/grails-app/controllers/bookshop/BookController.groovy'
  local server = fake_server {
    ['grails/downloadSources'] = { available = 12, unavailable = 2, failed = 0 },
    ['grails/reloadProject'] = vim.NIL,
  }
  start(server, buf)
  local notes = with(nil, nil, function()
    vim.cmd 'GrailsDownloadSources'
    vim.cmd 'GrailsReloadProject'
    vim.wait(100)
  end)
  local methods = vim.tbl_map(function(r)
    return r.method
  end, server.requests)
  h.eq({ 'initialize', 'grails/downloadSources', 'grails/reloadProject' }, methods)
  h.eq(
    {
      'grails_ls: downloading sources jars',
      'grails_ls: reloading the project',
      'grails_ls: sources jars: 12 available, 2 published by no library, 0 failed',
      'grails_ls: project reloaded',
    },
    vim.tbl_map(function(n)
      return n.msg
    end, notes)
  )
  stop_all()
  notes = with(nil, nil, function()
    vim.cmd 'GrailsReloadProject'
  end)
  h.eq(vim.log.levels.WARN, notes[2].level, 'no client: warned')
end

function T.pick_release_takes_the_newest_with_the_jar()
  local releases = {
    { tag_name = 'v0.3.0', draft = true, assets = { { name = ls.asset, browser_download_url = 'd' } } },
    { tag_name = 'v0.2.0-rc1', prerelease = true, assets = { { name = 'other.zip', browser_download_url = 'x' } } },
    { tag_name = 'v0.1.0-m6', prerelease = true, assets = { { name = ls.asset, browser_download_url = 'u' } } },
  }
  h.eq({ tag = 'v0.1.0-m6', url = 'u' }, ls.pick_release(releases))
  h.eq(nil, ls.pick_release {})
end

function T.install_downloads_the_jar_once()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'jar bytes' }, dir .. '/release.jar')
  local list = { { tag_name = 'v0.1.0-m6', assets = { { name = ls.asset, browser_download_url = 'file://' .. dir .. '/release.jar' } } } }
  vim.fn.writefile({ vim.json.encode(list) }, dir .. '/releases.json')
  local saved_url, saved_dir = ls.releases_url, ls.install_dir
  ls.releases_url = 'file://' .. dir .. '/releases.json'
  ls.install_dir = function()
    return dir .. '/data'
  end
  local function install(force)
    local result
    local notes = with(nil, nil, function()
      ls.install(force, function(ok)
        result = ok
      end)
      vim.wait(5000, function()
        return result ~= nil
      end)
    end)
    return result, notes[#notes].msg
  end
  local ok1, msg1 = install(false)
  local ok2, msg2 = install(false)
  vim.fn.writefile({ 'newer bytes' }, dir .. '/release.jar')
  local ok3, msg3 = install(true)
  ls.releases_url, ls.install_dir = saved_url, saved_dir
  h.eq(true, ok1, msg1)
  assert(msg1:find 'installed v0.1.0%-m6', msg1)
  h.eq(true, ok2)
  assert(msg2:find 'installed already', msg2)
  h.eq(true, ok3)
  h.eq({ 'newer bytes' }, vim.fn.readfile(dir .. '/data/' .. ls.asset))
  h.eq({ 'v0.1.0-m6' }, vim.fn.readfile(dir .. '/data/version'))
  h.eq(0, vim.fn.filereadable(dir .. '/data/' .. ls.asset .. '.part'))
end

return T
