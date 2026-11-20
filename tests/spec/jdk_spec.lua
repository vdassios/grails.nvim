-- The JDK grails_ls runs on, chosen per project root, and the launch gate.
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

--- A Grails build with one module; `extra` adds files (`gradle.properties`, `.sdkmanrc`).
local function project(extra)
  return tree(vim.tbl_extend('force', {
    ['settings.gradle'] = { "include 'app'" },
    ['app/grails-app/controllers/demo/DemoController.groovy'] = { 'package demo', 'class DemoController {}' },
    ['app/src/main/groovy/demo/Util.groovy'] = { 'package demo', 'class Util {}' },
  }, extra or {}))
end

--- A fake JDK at `home`: `bin/java` appends a line to `home/ran` on each run and answers `-version` with
--- `version` (stderr) and exit `code`. Returns `home/bin/java`.
local function jdk(home, version, code)
  vim.fn.mkdir(home .. '/bin', 'p')
  local java = home .. '/bin/java'
  local script = { '#!/bin/sh', 'echo "$@" >> "$(dirname "$0")/../ran"', ("echo '%s' >&2"):format(version), 'exit ' .. (code or 0) }
  vim.fn.writefile(script, java)
  vim.fn.setfperm(java, 'rwxr-xr-x')
  return java
end

--- How many times the fake JDK at `home` ran.
local function runs(home)
  return vim.fn.filereadable(home .. '/ran') == 1 and #vim.fn.readfile(home .. '/ran') or 0
end

--- A fake grails-language-server rpc for `vim.lsp.rpc.start`.
local function fake_rpc(dispatchers)
  local closing = false
  local function close()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 0)
    end
  end
  return {
    request = function(method, _, callback)
      local result = method == 'initialize' and { capabilities = {}, serverInfo = { version = require('grails.ls').min_server_version } } or vim.NIL
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

--- Runs `fn(spawned)` with `vim.g.grails_ls`, `$JAVA_HOME`, `$SDKMAN_DIR` set, `vim.notify` recorded and
--- `vim.lsp.rpc.start` replaced by a fake server that records each `{ cmd, extra }` in `spawned`. grails_ls is
--- enabled with the plugin's own config, so its `cmd` and `root_dir` run. Returns the notifications.
local function with(env, fn)
  local saved = { vim.g.grails_ls, vim.env.JAVA_HOME, vim.env.SDKMAN_DIR, vim.notify, vim.notify_once, vim.lsp.rpc.start }
  local notes, spawned = {}, {}
  vim.g.grails_ls, vim.env.JAVA_HOME, vim.env.SDKMAN_DIR = env.settings, env.java_home or '', env.sdkman or vim.fn.tempname()
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level or vim.log.levels.INFO }
  end
  local once = {}
  vim.notify_once = function(msg, level)
    if not once[msg] then
      once[msg] = true
      vim.notify(msg, level)
    end
  end
  vim.lsp.rpc.start = function(cmd, dispatchers, extra)
    spawned[#spawned + 1] = { cmd = cmd, extra = extra }
    return fake_rpc(dispatchers)
  end
  -- Buffers other specs left open would attach (or be refused, with a notice) on enable.
  vim.cmd 'silent! %bwipeout!'
  vim.lsp.enable 'grails_ls'
  local ok, err = pcall(fn, spawned)
  vim.lsp.enable('grails_ls', false)
  vim.wait(1000, function()
    return #vim.lsp.get_clients { name = 'grails_ls' } == 0
  end)
  vim.g.grails_ls, vim.env.JAVA_HOME, vim.env.SDKMAN_DIR, vim.notify, vim.notify_once, vim.lsp.rpc.start = unpack(saved)
  assert(ok, err)
  return notes
end

--- Runs `fn` with `cfg` merged into the user's grails_ls config, then puts the user's config back.
local function with_config(cfg, fn)
  local saved = vim.lsp.config._configs.grails_ls
  vim.lsp.config('grails_ls', cfg)
  local ok, err = pcall(fn)
  vim.lsp.config.grails_ls = saved or {}
  assert(ok, err)
end

local function edit(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

--- The grails_ls client attached to `buf` within `ms`, or nil.
local function client(buf, ms)
  local found
  vim.wait(ms or 2000, function()
    found = vim.lsp.get_clients({ bufnr = buf, name = 'grails_ls' })[1]
    return found ~= nil and found.initialized
  end)
  return found
end

local function messages(notes)
  return table.concat(
    vim.tbl_map(function(n)
      return n.msg
    end, notes),
    '\n'
  )
end

local function jar()
  local path = vim.fn.tempname()
  vim.fn.writefile({}, path)
  return path
end

function T.java_resolution_order_for_a_trusted_root()
  local sdkman = vim.fn.tempname()
  local from_setting = jdk(vim.fn.tempname(), 'openjdk version "21.0.1"')
  local from_gradle = jdk(vim.fn.tempname(), 'openjdk version "17.0.1"')
  local from_sdkman = jdk(sdkman .. '/candidates/java/11.0.28-amzn', 'openjdk version "11.0.28"')
  local home = vim.fn.tempname()
  local from_home = jdk(home, 'openjdk version "17.0.2"')
  local props = { '# the build JDK', ('org.gradle.java.home = %s'):format(vim.fs.dirname(vim.fs.dirname(from_gradle))) }
  local root = project { ['gradle.properties'] = props, ['.sdkmanrc'] = { '# sdk env', 'java=11.0.28-amzn' } }
  trust.trust(root)
  local results = {}
  with({ java_home = home, sdkman = sdkman, settings = { java = from_setting } }, function()
    results[#results + 1] = ls.java(root)
    vim.g.grails_ls = nil
    results[#results + 1] = ls.java(root)
    os.remove(root .. '/gradle.properties')
    results[#results + 1] = ls.java(root)
    os.remove(root .. '/.sdkmanrc')
    results[#results + 1] = ls.java(root)
    vim.env.JAVA_HOME = ''
    results[#results + 1] = ls.java(root)
  end)
  trust.revoke(root)
  h.eq({ from_setting, from_gradle, from_sdkman, from_home, 'java' }, results)
end

function T.untrusted_root_reads_no_project_file()
  local sdkman = vim.fn.tempname()
  jdk(sdkman .. '/candidates/java/11.0.28-amzn', 'openjdk version "11.0.28"')
  local gradle_home = vim.fn.tempname()
  jdk(gradle_home, 'openjdk version "17.0.1"')
  local root = project { ['gradle.properties'] = { 'org.gradle.java.home=' .. gradle_home }, ['.sdkmanrc'] = { 'java=11.0.28-amzn' } }
  local java
  with({ sdkman = sdkman }, function()
    java = ls.java(root)
  end)
  h.eq('java', java)
end

function T.two_roots_run_on_their_own_jdk()
  local sdkman = vim.fn.tempname()
  local java_a = jdk(sdkman .. '/candidates/java/11.0.28-amzn', 'openjdk version "11.0.28"')
  local java_b = jdk(sdkman .. '/candidates/java/17.0.19-amzn', 'openjdk version "17.0.19"')
  local home = vim.fn.tempname()
  jdk(home, 'openjdk version "21.0.1"')
  local a = project { ['.sdkmanrc'] = { 'java=11.0.28-amzn' } }
  local b = project { ['.sdkmanrc'] = { 'java=17.0.19-amzn' } }
  trust.trust(a)
  trust.trust(b)
  local spawned
  with({ java_home = home, sdkman = sdkman, settings = { jar = jar() } }, function(s)
    spawned = s
    local buf_a = edit(a .. '/app/src/main/groovy/demo/Util.groovy')
    assert(client(buf_a), 'no client for the first root')
    local buf_b = edit(b .. '/app/src/main/groovy/demo/Util.groovy')
    assert(client(buf_b), 'no client for the second root')
    assert(client(buf_a).id ~= client(buf_b).id, 'one client for both roots')
  end)
  trust.revoke(a)
  trust.revoke(b)
  h.eq({ java_a, java_b }, { spawned[1].cmd[1], spawned[2].cmd[1] })
  h.eq(0, runs(home), 'the JDK of $JAVA_HOME ran')
end

function T.invalid_java_home_warns_once_and_falls_back_to_path()
  local home = vim.fn.tempname()
  vim.fn.mkdir(home, 'p')
  local java
  local notes = with({ java_home = home }, function()
    java = ls.java()
    ls.java()
  end)
  h.eq('java', java)
  h.eq(1, #notes, messages(notes))
  h.eq(vim.log.levels.WARN, notes[1].level)
  assert(notes[1].msg:find('JAVA_HOME', 1, true) and notes[1].msg:find(home, 1, true), notes[1].msg)
end

function T.sdkmanrc_with_a_bad_or_missing_jdk_warns_and_falls_through()
  local sdkman = vim.fn.tempname()
  -- A JDK reachable only by escaping the candidates directory.
  local escaped = jdk(sdkman .. '/evil', 'openjdk version "17.0.1"')
  local home = vim.fn.tempname()
  local from_home = jdk(home, 'openjdk version "17.0.2"')
  for _, id in ipairs { '../../evil', 'a/b', 'nope-amzn' } do
    local root = project { ['.sdkmanrc'] = { 'java=' .. id } }
    trust.trust(root)
    local java
    local notes = with({ java_home = home, sdkman = sdkman }, function()
      java = ls.java(root)
      ls.java(root)
    end)
    trust.revoke(root)
    h.eq(from_home, java, id)
    assert(java ~= escaped, id)
    h.eq(1, #notes, id .. ': ' .. messages(notes))
    h.eq(vim.log.levels.WARN, notes[1].level, id)
    assert(notes[1].msg:find('.sdkmanrc', 1, true) and notes[1].msg:find(id, 1, true), notes[1].msg)
  end
end

function T.java_version_is_checked_once_per_binary()
  local home = vim.fn.tempname()
  local java = jdk(home, 'openjdk version "17.0.19" 2026-04-21 LTS')
  local root = project()
  trust.trust(root)
  local spawned
  with({ settings = { java = java, jar = jar() } }, function(s)
    spawned = s
    assert(client(edit(root .. '/app/src/main/groovy/demo/Util.groovy')), 'no client')
    assert(client(edit(root .. '/app/grails-app/controllers/demo/DemoController.groovy')), 'no client')
  end)
  trust.revoke(root)
  h.eq(1, #spawned)
  h.eq({ '-version' }, vim.fn.readfile(home .. '/ran'), 'java ran other than for one -version check')
end

function T.no_jdk_or_an_old_one_is_reported_and_not_started()
  local cases = {
    -- The macOS /usr/bin/java stub when no JDK is installed.
    { version = 'The operation couldn’t be completed. Unable to locate a Java Runtime.', code = 1, says = 'Unable to locate a Java Runtime' },
    { version = 'java version "1.8.0_392"', says = 'Java 8' },
    { version = 'openjdk version "10" 2018-03-20', says = 'Java 10' },
  }
  for _, case in ipairs(cases) do
    local java = jdk(vim.fn.tempname(), case.version, case.code)
    local root = project()
    trust.trust(root)
    local spawned
    local notes = with({ settings = { java = java, jar = jar() } }, function(s)
      spawned = s
      h.eq(nil, client(edit(root .. '/app/src/main/groovy/demo/Util.groovy'), 500), case.says)
    end)
    trust.revoke(root)
    h.eq(0, #spawned, case.says)
    h.eq(1, #notes, messages(notes))
    h.eq(vim.log.levels.WARN, notes[1].level)
    assert(notes[1].msg:find(case.says, 1, true) and notes[1].msg:find(java, 1, true), notes[1].msg)
  end
end

function T.java_not_executable_is_reported_and_not_started()
  local root = project()
  trust.trust(root)
  local missing = vim.fn.tempname() .. '/bin/java'
  local spawned
  local notes = with({ settings = { java = missing, jar = jar() } }, function(s)
    spawned = s
    h.eq(nil, client(edit(root .. '/app/src/main/groovy/demo/Util.groovy'), 200))
  end)
  trust.revoke(root)
  h.eq(0, #spawned)
  h.eq(1, #notes, messages(notes))
  assert(notes[1].msg:find('not executable', 1, true) and notes[1].msg:find(missing, 1, true), notes[1].msg)
end

function T.overridden_cmd_is_not_gated_on_the_jar_or_java()
  local root = project()
  trust.trust(root)
  local started, notes = 0, nil
  local function cmd(dispatchers)
    started = started + 1
    return fake_rpc(dispatchers)
  end
  with_config({ cmd = cmd }, function()
    notes = with({ settings = { java = vim.fn.tempname(), jar = vim.fn.tempname() } }, function()
      assert(client(edit(root .. '/app/src/main/groovy/demo/Util.groovy')), 'no client with an overridden cmd')
    end)
  end)
  trust.revoke(root)
  h.eq({}, notes)
  h.eq(1, started)
end

function T.cmd_env_cwd_and_detached_reach_the_process()
  local root = project()
  trust.trust(root)
  local java = jdk(vim.fn.tempname(), 'openjdk version "17.0.19"')
  local spawned
  with_config({ cmd_env = { GRAILS_OPTS = '-Xmx2g' }, cmd_cwd = root, detached = false }, function()
    with({ settings = { java = java, jar = jar() } }, function(s)
      spawned = s
      assert(client(edit(root .. '/app/src/main/groovy/demo/Util.groovy')), 'no client')
    end)
  end)
  trust.revoke(root)
  h.eq({ env = { GRAILS_OPTS = '-Xmx2g' }, cwd = root, detached = false }, spawned[1].extra)
  h.eq(java, spawned[1].cmd[1])
end

return T
