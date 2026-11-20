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
  local notes = with({ jar = vim.fn.tempname(), java = '/no/such/java' }, nil, function()
    ls.root_dir(buf, on_dir)
  end)
  h.eq({}, roots)
  h.eq(vim.log.levels.WARN, notes[1].level)
  assert(notes[1].msg:find 'GrailsInstallServer', notes[1].msg)

  local jar = vim.fn.tempname()
  vim.fn.writefile({}, jar)
  local java = vim.fn.tempname() .. '/bin/java'
  vim.fn.mkdir(vim.fs.dirname(java), 'p')
  vim.fn.writefile({ '#!/bin/sh', [[echo 'openjdk version "17.0.19"' >&2]] }, java)
  vim.fn.setfperm(java, 'rwxr-xr-x')
  with({ jar = jar, java = java }, nil, function()
    ls.root_dir(buf, on_dir)
    vim.wait(2000, function()
      return #roots > 0
    end)
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

function T.pick_release_prefers_the_newest_stable_release_with_the_jar()
  local function rel(tag, pre, name, url, digest)
    return { tag_name = tag, prerelease = pre, assets = { { name = name or ls.asset, browser_download_url = url or tag, digest = digest } } }
  end
  local releases = {
    { tag_name = 'v0.4.0', draft = true, assets = { { name = ls.asset, browser_download_url = 'd' } } },
    rel('v0.3.0-rc1', true),
    rel('v0.2.1', false, 'other.zip'),
    rel('v0.2.0', false, nil, 'u', 'sha256:ab'),
    rel('v0.1.0', false),
  }
  h.eq({ tag = 'v0.2.0', url = 'u', digest = 'sha256:ab', prerelease = false }, ls.pick_release(releases))
  h.eq({ tag = 'v0.3.0-rc1', url = 'v0.3.0-rc1', prerelease = true }, ls.pick_release { releases[2], releases[3] }, 'only pre-releases')
  h.eq({ tag = 'v0.1.0', url = 'v0.1.0', prerelease = false }, ls.pick_release(releases, 'v0.1.0'), 'a tag')
  h.eq({ tag = 'v0.3.0-rc1', url = 'v0.3.0-rc1', prerelease = true }, ls.pick_release(releases, 'v0.3.0-rc1'), 'a pre-release tag')
  h.eq(nil, ls.pick_release(releases, 'v0.4.0'), 'a draft')
  h.eq(nil, ls.pick_release(releases, 'v0.2.1'), 'a release without the jar')
  h.eq(nil, ls.pick_release {})
end

--- A release list entry with the jar.
local function release(tag, digest, prerelease)
  local asset = { name = ls.asset, browser_download_url = 'https://example.invalid/' .. tag .. '/' .. ls.asset, digest = digest }
  return { tag_name = tag, prerelease = prerelease or false, assets = { asset } }
end

local function sha256(text)
  return 'sha256:' .. vim.fn.sha256(text)
end

--- Runs `:GrailsInstallServer` (`ls.install(force, tag)`) into a fresh install directory (or `dir`) with `vim.system`
--- stubbed for `curl`: `answer(url, args)` returns the result (`code`, `stdout`, `stderr`, and `body`, which is
--- written to the `-o` file). Other commands run for real. Returns the outcome, the notifications, the curl command
--- lines and the install directory.
local function install(answer, opts)
  opts = opts or {}
  local dir = opts.dir or vim.fn.tempname()
  local saved_system, saved_dir = vim.system, ls.install_dir
  local calls = {}
  vim.system = function(cmd, sysopts, on_exit)
    if cmd[1] ~= 'curl' then
      return saved_system(cmd, sysopts, on_exit)
    end
    calls[#calls + 1] = cmd
    local res = answer(cmd[#cmd], cmd)
    local out = vim.list_contains(cmd, '-o') and cmd[vim.fn.index(cmd, '-o') + 2]
    if out and res.body then
      vim.fn.writefile({ res.body }, out, 'b')
    end
    vim.schedule(function()
      on_exit { code = res.code or 0, signal = 0, stdout = res.stdout or '', stderr = res.stderr or '' }
    end)
    return {}
  end
  ls.install_dir = function()
    return dir
  end
  local results = {}
  local notes = with(opts.settings, nil, function()
    for _ = 1, opts.runs or 1 do
      ls.install(opts.force, opts.tag, function(ok)
        results[#results + 1] = ok
      end)
    end
    vim.wait(5000, function()
      return #results == (opts.runs or 1)
    end)
  end)
  vim.system, ls.install_dir = saved_system, saved_dir
  local msgs = vim.tbl_map(function(n)
    return n.msg
  end, notes)
  return { ok = results[1], results = results, notes = notes, msgs = table.concat(msgs, '\n'), calls = calls, dir = dir }
end

--- `answer` for `install`: the release list `list`, and `bytes` for every jar URL.
local function github(list, bytes)
  return function(url)
    if url == ls.releases_url then
      return { stdout = vim.json.encode(list) }
    end
    return { body = bytes or 'jar bytes' }
  end
end

--- Files in `dir`, sorted.
local function files(dir)
  local names = {}
  for name in vim.fs.dir(dir) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function T.install_takes_the_newest_stable_release_and_checks_its_digest()
  local list = { release('v0.3.0-rc1', sha256 'rc', true), release('v0.2.0', sha256 'jar bytes'), release('v0.1.0', sha256 'old') }
  local r = install(github(list))
  h.eq(true, r.ok, r.msgs)
  assert(r.msgs:find 'installed v0%.2%.0 at', r.msgs)
  assert(not r.msgs:find 'pre%-release', r.msgs)
  h.eq({ 'jar bytes' }, vim.fn.readfile(r.dir .. '/' .. ls.asset))
  h.eq({ 'v0.2.0' }, vim.fn.readfile(r.dir .. '/version'))
  h.eq('rw-r--r--', vim.fn.getfperm(r.dir .. '/' .. ls.asset))
  h.eq({ ls.asset, 'version' }, files(r.dir), 'no temporary file is left')
  for _, cmd in ipairs(r.calls) do
    assert(vim.list_contains(cmd, '--max-time'), table.concat(cmd, ' '))
    assert(vim.list_contains(cmd, '--fail') or vim.list_contains(cmd, '--fail-with-body'), table.concat(cmd, ' '))
  end

  local again = install(github(list, 'other bytes'), { dir = r.dir })
  h.eq(true, again.ok)
  assert(again.notes[#again.notes].msg:find 'v0%.2%.0 is installed already', again.msgs)
  h.eq(1, #again.calls, 'no download')

  local forced = install(github(list), { dir = r.dir, force = true })
  h.eq(true, forced.ok, forced.msgs)
  h.eq(2, #forced.calls)
end

function T.install_takes_the_newest_pre_release_when_no_stable_release_has_the_jar()
  local stable_without_jar = { tag_name = 'v0.2.0', prerelease = false, assets = { { name = 'other.zip', browser_download_url = 'x' } } }
  local list = { release('v0.3.0-rc1', sha256 'jar bytes', true), stable_without_jar, release('v0.1.0-m6', sha256 'old', true) }
  local r = install(github(list))
  h.eq(true, r.ok, r.msgs)
  assert(r.msgs:find 'installed v0%.3%.0%-rc1', r.msgs)
  assert(r.msgs:find 'pre%-release', r.msgs)
  h.eq({ 'v0.3.0-rc1' }, vim.fn.readfile(r.dir .. '/version'))
end

function T.install_takes_a_given_tag()
  local list = { release('v0.2.0', sha256 'new'), release('v0.1.0-m6', sha256 'jar bytes', true) }
  local r = install(github(list), { tag = 'v0.1.0-m6' })
  h.eq(true, r.ok, r.msgs)
  h.eq({ 'v0.1.0-m6' }, vim.fn.readfile(r.dir .. '/version'))
  assert(r.msgs:find 'installed v0%.1%.0%-m6 %(a pre%-release%) at', r.msgs)
  h.eq('https://example.invalid/v0.1.0-m6/' .. ls.asset, r.calls[2][#r.calls[2]])

  local missing = install(github(list), { tag = 'v9.9.9' })
  h.eq(false, missing.ok)
  h.eq(vim.log.levels.ERROR, missing.notes[#missing.notes].level)
  assert(missing.msgs:find 'v9%.9%.9', missing.msgs)
  h.eq(1, #missing.calls)
end

function T.install_fails_readably_without_curl()
  local r = install(function()
    error "vim/_core/system:324: ENOENT: no such file or directory (cmd): 'curl'"
  end)
  h.eq(false, r.ok)
  h.eq(vim.log.levels.ERROR, r.notes[#r.notes].level)
  assert(r.notes[#r.notes].msg:find 'curl', r.msgs)
end

function T.install_fails_readably_on_a_stalled_download_and_keeps_the_installed_jar()
  local list = { release('v0.2.0', sha256 'jar bytes') }
  local r = install(github { release('v0.1.0', sha256 'jar bytes') })
  h.eq(true, r.ok, r.msgs)
  local stalled = install(function(url)
    if url == ls.releases_url then
      return { stdout = vim.json.encode(list) }
    end
    return { code = 28, body = 'half a', stderr = 'curl: (28) Operation timed out after 120002 milliseconds with 6 bytes received' }
  end, { dir = r.dir })
  h.eq(false, stalled.ok)
  h.eq(vim.log.levels.ERROR, stalled.notes[#stalled.notes].level)
  assert(stalled.notes[#stalled.notes].msg:find 'timed out', stalled.msgs)
  h.eq({ 'jar bytes' }, vim.fn.readfile(r.dir .. '/' .. ls.asset))
  h.eq({ 'v0.1.0' }, vim.fn.readfile(r.dir .. '/version'))
  h.eq({ ls.asset, 'version' }, files(r.dir), 'the partial download is removed')
end

function T.install_refuses_a_download_that_does_not_match_the_digest()
  local r = install(github({ release('v0.2.0', sha256 'the real jar') }, 'tampered bytes'))
  h.eq(false, r.ok)
  h.eq(vim.log.levels.ERROR, r.notes[#r.notes].level)
  assert(r.notes[#r.notes].msg:find 'digest', r.msgs)
  h.eq({}, files(r.dir), 'nothing is installed')
end

function T.install_warns_when_the_release_has_no_digest()
  local r = install(github { release('v0.1.0-m6', vim.NIL, true) })
  h.eq(true, r.ok, r.msgs)
  local warned = vim.tbl_filter(function(n)
    return n.level == vim.log.levels.WARN
  end, r.notes)
  h.eq(1, #warned, r.msgs)
  assert(warned[1].msg:find 'no digest', warned[1].msg)
  h.eq({ 'jar bytes' }, vim.fn.readfile(r.dir .. '/' .. ls.asset))
end

function T.install_explains_a_rate_limited_api()
  local body = vim.json.encode {
    message = "API rate limit exceeded for 192.0.2.1. (But here's the good news: Authenticated requests get a higher rate limit.)",
    documentation_url = 'https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting',
  }
  local r = install(function()
    return { code = 22, stdout = body, stderr = 'curl: (22) The requested URL returned error: 403' }
  end)
  h.eq(false, r.ok)
  local msg = r.notes[#r.notes].msg
  assert(msg:find 'rate limit', msg)
  assert(not msg:find '{', msg)
end

function T.install_checks_its_own_jar_not_the_users_override()
  local override = vim.fn.tempname()
  vim.fn.writefile({ 'my own build' }, override)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'v0.2.0' }, dir .. '/version')
  local r = install(github { release('v0.2.0', sha256 'jar bytes') }, { dir = dir, settings = { jar = override } })
  h.eq(true, r.ok, r.msgs)
  h.eq(2, #r.calls, 'downloaded: the install target has no jar')
  h.eq({ 'jar bytes' }, vim.fn.readfile(dir .. '/' .. ls.asset))
  h.eq({ 'my own build' }, vim.fn.readfile(override))
end

function T.concurrent_installs_do_not_share_a_temporary_file()
  local r = install(github { release('v0.2.0', sha256 'jar bytes') }, { runs = 2 })
  h.eq({ true, true }, r.results, r.msgs)
  h.eq({ ls.asset, 'version' }, files(r.dir))
end

return T
