-- The plugin against a real grails-language-server jar, on the server checkout's `fixtures/grails4` project.
-- Runs only with both set (else this spec has no tests and says so):
--   GRAILS_LS_JAR      the jar `./gradlew shadowJar` builds: <server>/build/libs/grails-language-server-all.jar
--   GRAILS_LS_FIXTURE  <server>/fixtures/grails4
-- The server runs on the `java` the plugin picks (`$JAVA_HOME`, else `java` on `PATH`), which must be a JDK 11 for
-- the fixture's Gradle 6.9. The first run resolves the fixture with Gradle, which can download for minutes.
local cases = require 'definition_cases'
local h = require 'helpers'
local ls = require 'grails.ls'
local trust = require 'grails.trust'

local T = {}

local jar, fixture = vim.env.GRAILS_LS_JAR, vim.env.GRAILS_LS_FIXTURE
if (jar or '') == '' or (fixture or '') == '' then
  print 'skip  integration_spec: set GRAILS_LS_JAR and GRAILS_LS_FIXTURE to run it against a server jar'
  return T
end
assert(vim.uv.fs_stat(jar), 'GRAILS_LS_JAR: no file at ' .. jar)
fixture = vim.fs.normalize(vim.fn.fnamemodify(fixture, ':p'))
local controller = fixture .. '/app/grails-app/controllers/fixture/library/BookController.groovy'
assert(vim.uv.fs_stat(controller), 'GRAILS_LS_FIXTURE: not the server repository fixtures/grails4: ' .. fixture)

-- Gradle resolution (a first run downloads Gradle and the fixture's dependencies), and the other requests.
local RESOLVE_MS, REQUEST_MS = 600000, 60000
-- How soon after `:qa` Neovim must have exited, and the server process be gone.
local QUIT_MS, SERVER_GONE_MS = 2000, 5000

-- The server's models, logs and analysis jar: kept out of the user's cache, shared by the tests (one Gradle run).
-- Gradle may take as long as the spec waits.
local cache = vim.fn.tempname()
local init_options = { cacheDir = cache, gradle = { timeoutSeconds = RESOLVE_MS / 1000 } }

--- A link to the jar under a name of its own, so `pgrep -f` finds only the servers this spec starts.
local function jar_link()
  local link = vim.fn.tempname() .. '-grails-ls.jar'
  assert(vim.uv.fs_symlink(jar, link))
  return link
end

--- Whether a process runs with `link` on its command line.
local function running(link)
  return vim.system({ 'pgrep', '-f', link }):wait().code == 0
end

--- Waits up to `ms` for `cond`; fails with `what` when it does not hold.
local function wait(ms, cond, what)
  if not vim.wait(ms, cond, 50) then
    error(('timed out after %d ms: %s'):format(ms, what), 2)
  end
end

--- Runs `fn(notes)` with grails_ls enabled on a jar link, its cache in `cache`, and `vim.notify` recorded in
--- `notes`; then stops the server, checks its process is gone, and puts everything back.
local function with_server(fn)
  local saved = { vim.g.grails_ls, vim.notify, vim.notify_once, vim.lsp.config._configs.grails_ls }
  local link, notes, once = jar_link(), {}, {}
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level or vim.log.levels.INFO }
  end
  vim.notify_once = function(msg, level)
    if not once[msg] then
      once[msg] = true
      vim.notify(msg, level)
    end
  end
  vim.g.grails_ls = { jar = link }
  vim.lsp.config('grails_ls', { init_options = init_options })
  -- Buffers other specs left open would attach (or be refused, with a notice) on enable.
  vim.cmd 'silent! %bwipeout!'
  vim.lsp.enable 'grails_ls'
  local ok, err = xpcall(fn, debug.traceback, notes)
  vim.lsp.enable('grails_ls', false)
  for _, client in ipairs(vim.lsp.get_clients { name = ls.name }) do
    client:stop()
  end
  local stopped = vim.wait(SERVER_GONE_MS, function()
    return #vim.lsp.get_clients { name = ls.name } == 0 and not running(link)
  end, 50)
  vim.cmd 'silent! %bwipeout!'
  trust.revoke(fixture)
  os.remove(link)
  vim.g.grails_ls, vim.notify, vim.notify_once = saved[1], saved[2], saved[3]
  vim.lsp.config._configs.grails_ls = saved[4]
  assert(ok, err)
  assert(stopped, 'the server did not stop within ' .. SERVER_GONE_MS .. ' ms')
end

--- The first recorded notification that contains `text`.
local function noted(notes, text)
  for _, n in ipairs(notes) do
    if n.msg:find(text, 1, true) then
      return n
    end
  end
end

--- Waits until `client` reports `ready`; fails with the server's failure message when it reports `failed`.
local function wait_ready(client, notes)
  local ready = vim.wait(RESOLVE_MS, function()
    local state = ls.states[client.id]
    assert(state ~= 'failed', 'grails_ls failed: ' .. vim.inspect(notes))
    return state == 'ready'
  end, 50)
  assert(ready, ('not ready after %d ms, state %s'):format(RESOLVE_MS, tostring(ls.states[client.id])))
end

--- `path` below the fixture root, real paths on both sides (the server answers with real paths).
local function below_fixture(path)
  return vim.fs.relpath(trust.real(fixture), trust.real(path)) or path
end

--- What a case expects: `path:line` (0-based) of its target, the line the first holding the target's text.
local function expected(case)
  local path, text = case.target[1], case.target[2]
  if not text then
    return path .. ':0'
  end
  for i, line in ipairs(vim.fn.readfile(fixture .. '/' .. path)) do
    if line:find(text, 1, true) then
      return path .. ':' .. (i - 1)
    end
  end
  error(('%s: no line holds %q in %s'):format(case.kind, text, path))
end

--- The definition targets, as `path:line`, the client named `name` gives at a case's position.
local function define(case, name)
  vim.cmd.edit(vim.fn.fnameescape(fixture .. '/' .. case.file))
  local buf = vim.api.nvim_get_current_buf()
  local client
  wait(REQUEST_MS, function()
    client = vim.lsp.get_clients({ bufnr = buf, name = name })[1]
    return client ~= nil and client.initialized
  end, name .. ' attached to ' .. case.file)
  local row, col = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), case.text, case.at)
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
  local res, err = client:request_sync('textDocument/definition', params, REQUEST_MS, buf)
  assert(res and not res.err, ('%s: definition from %s failed: %s'):format(case.kind, name, vim.inspect(res and res.err or err)))
  local result = res.result or {}
  if result.uri or result.targetUri then
    result = { result }
  end
  return vim.tbl_map(function(loc)
    local range = loc.range or loc.targetSelectionRange
    return below_fixture(vim.uri_to_fname(loc.uri or loc.targetUri)) .. ':' .. range.start.line
  end, result)
end

--- The mismatches of `found` (targets by case index) against the cases' targets, for the servers marked `side`.
local function mismatches(found, side, label)
  local wrong = {}
  for i, case in ipairs(cases) do
    local want = (case.servers == 'both' or case.servers == side) and { expected(case) } or {}
    if not vim.deep_equal(want, found[i]) then
      wrong[#wrong + 1] = ('%s [%s] %s: expected %s, got %s'):format(label, case.servers, case.kind, vim.inspect(want), vim.inspect(found[i]))
    end
  end
  return wrong
end

function T.definition_cases_give_one_target_before_and_after_ready()
  with_server(function(notes)
    -- The fixture is not trusted yet, so grails_ls does not start: the Lua server answers alone.
    local lua, java, handed = {}, {}, {}
    vim.lsp.enable 'grails'
    for i, case in ipairs(cases) do
      lua[i] = define(case, 'grails')
    end
    h.eq(0, #vim.lsp.get_clients { name = ls.name }, 'grails_ls clients before :GrailsTrust')

    vim.cmd 'GrailsTrust'
    local client
    wait(REQUEST_MS, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = ls.name })[1]
      return client ~= nil and client.initialized
    end, 'grails_ls attached after :GrailsTrust')
    wait_ready(client, notes)
    for i, case in ipairs(cases) do
      java[i] = define(case, ls.name)
      -- grails_ls is ready in the buffer: the Lua server is silent there.
      handed[i] = define(case, 'grails')
    end

    local wrong = mismatches(lua, 'lua', 'Lua server')
    vim.list_extend(wrong, mismatches(java, 'java', 'grails_ls'))
    for i, case in ipairs(cases) do
      if #handed[i] > 0 then
        wrong[#wrong + 1] = ('Lua server after ready, %s: expected nothing, got %s'):format(case.kind, vim.inspect(handed[i]))
      end
    end
    assert(#wrong == 0, table.concat(wrong, '\n'))
  end)
end

function T.real_server_on_the_grails4_fixture()
  with_server(function(notes)
    vim.cmd.edit(vim.fn.fnameescape(controller))
    local buf = vim.api.nvim_get_current_buf()
    -- Not trusted: a notice and no server.
    wait(2000, function()
      return noted(notes, 'not trusted') ~= nil
    end, 'the not-trusted notice')
    vim.wait(500)
    h.eq(0, #vim.lsp.get_clients { bufnr = buf, name = ls.name }, 'clients before :GrailsTrust')

    vim.cmd 'GrailsTrust'
    assert(trust.is_trusted(fixture), 'the fixture root is in the allowlist')
    local client
    wait(REQUEST_MS, function()
      client = vim.lsp.get_clients({ bufnr = buf, name = ls.name })[1]
      return client ~= nil and client.initialized
    end, 'grails_ls attached after :GrailsTrust')
    h.eq(trust.real(fixture), trust.real(client.root_dir), 'root')
    h.eq(init_options, client.config.init_options, 'init_options')
    wait_ready(client, notes)

    -- Hover on `render` (a method Grails adds to controllers).
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local row, col = h.pos(lines, 'render(', 1)
    local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
    local res, err = client:request_sync('textDocument/hover', params, REQUEST_MS, buf)
    assert(res and not res.err, 'hover failed: ' .. vim.inspect(res and res.err or err))
    local value = res.result and res.result.contents and (res.result.contents.value or res.result.contents)
    assert(type(value) == 'string' and value:find('void render(Map', 1, true), 'hover on render: ' .. vim.inspect(res.result))

    vim.cmd 'GrailsReloadProject'
    wait(RESOLVE_MS, function()
      assert(not noted(notes, 'grails/reloadProject failed'), vim.inspect(notes))
      return noted(notes, 'project reloaded') ~= nil
    end, ':GrailsReloadProject answered')
    wait_ready(client, notes)

    vim.cmd 'GrailsReindex'
    wait(REQUEST_MS, function()
      assert(not noted(notes, 'grails/reindex failed'), vim.inspect(notes))
      return noted(notes, 'source files rescanned') ~= nil
    end, ':GrailsReindex answered')

    for _, n in ipairs(notes) do
      assert(n.level < vim.log.levels.WARN, 'warning or error: ' .. n.msg)
    end
  end)
end

function T.quitting_neovim_with_a_ready_server_is_prompt()
  local link, dir = jar_link(), vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local marker, init = dir .. '/quit-at', dir .. '/init.lua'
  -- A Neovim of its own (the runner cannot quit itself), set up like tests/minimal_init.lua but without parsers.
  vim.fn.writefile({
    ('local root, link, init_options = %q, %q, %s'):format(h.root, link, vim.inspect(init_options, { newline = ' ', indent = '' })),
    'vim.opt.runtimepath:prepend(root)',
    "vim.opt.runtimepath:append(root .. '/after')",
    'vim.opt.swapfile = false',
    "vim.opt.shadafile = 'NONE'",
    'vim.g.grails_ls = { jar = link }',
    "vim.lsp.config('grails_ls', { init_options = init_options })",
    "vim.lsp.enable 'grails_ls'",
  }, init)
  local script = {
    "local ls = require 'grails.ls'",
    ('local marker, request_ms, resolve_ms = %q, %d, %d'):format(marker, REQUEST_MS, RESOLVE_MS),
    'local client',
    'local function fail(what)',
    "  io.stderr:write(what .. '\\n')",
    "  vim.cmd 'cquit 2'",
    'end',
    'if not vim.wait(request_ms, function()',
    '  client = vim.lsp.get_clients({ bufnr = 0, name = ls.name })[1]',
    '  return client ~= nil',
    'end, 50) then',
    "  fail 'grails_ls did not attach'",
    'end',
    'if not vim.wait(resolve_ms, function()',
    "  return ls.states[client.id] == 'ready'",
    'end, 50) then',
    "  fail('grails_ls not ready: ' .. tostring(ls.states[client.id]))",
    'end',
    'vim.fn.writefile({ tostring(vim.uv.hrtime()) }, marker)',
    "vim.cmd 'qall!'",
  }
  vim.fn.writefile(script, dir .. '/quit.lua')

  trust.trust(fixture)
  local exited_at, result
  -- The child inherits $XDG_STATE_HOME (tests/minimal_init.lua), so it reads the allowlist just written.
  local cmd = { vim.v.progpath, '--headless', '-u', init, '-c', 'luafile ' .. vim.fn.fnameescape(dir .. '/quit.lua'), controller }
  local ok, err = pcall(function()
    vim.system(cmd, { text = true }, function(res)
      exited_at, result = vim.uv.hrtime(), res
    end)
    wait(RESOLVE_MS + 10000, function()
      return result ~= nil
    end, 'the child Neovim exited')
    assert(result.code == 0, ('child Neovim exited with %d: %s'):format(result.code, result.stderr))
    local quit_at = tonumber(vim.fn.readfile(marker)[1])
    local quit_ms = (exited_at - quit_at) / 1e6
    assert(quit_ms < QUIT_MS, ('Neovim took %d ms to quit'):format(quit_ms))
    wait(SERVER_GONE_MS, function()
      return not running(link)
    end, 'the server process gone after :qa')
  end)
  if running(link) then
    vim.system({ 'pkill', '-f', link }):wait()
  end
  trust.revoke(fixture)
  os.remove(link)
  assert(ok, err)
end

return T
