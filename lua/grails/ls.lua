-- Client side of grails-language-server (`after/lsp/grails_ls.lua`): where the jar and `java` are, the `grails/status`
-- notification, the server's own requests, and `:GrailsInstallServer`.
local M = {}

M.name = 'grails_ls'
M.asset = 'grails-language-server-all.jar'
M.releases_url = 'https://api.github.com/repos/vdassios/grails-language-server/releases?per_page=30'

--- @class grails.LsSettings
--- @field java? string the `java` to run the server with
--- @field jar? string the server jar, instead of the one `:GrailsInstallServer` downloads

--- @return grails.LsSettings
local function settings()
  return vim.g.grails_ls or {}
end

--- Where `:GrailsInstallServer` puts the jar.
function M.install_dir()
  return vim.fs.joinpath(vim.fn.stdpath 'data', 'grails.nvim')
end

function M.jar()
  return settings().jar and vim.fs.normalize(settings().jar) or vim.fs.joinpath(M.install_dir(), M.asset)
end

local function warn(text, ...)
  vim.notify_once(('grails_ls: ' .. text):format(...), vim.log.levels.WARN)
end

--- Lines of `path`, or an empty list when it cannot be read.
--- @param path string
--- @return string[]
local function lines(path)
  local ok, read = pcall(vim.fn.readfile, path)
  return ok and read or {}
end

--- `org.gradle.java.home` in `<root>/gradle.properties` (Java properties syntax: `=`, `:` or blanks separate the
--- key, `\` escapes).
--- @param root string
--- @return string?
local function gradle_java_home(root)
  for _, line in ipairs(lines(vim.fs.joinpath(root, 'gradle.properties'))) do
    local value = line:match '^%s*org%.gradle%.java%.home%s*[=:%s]%s*(.-)%s*$'
    if value and value ~= '' then
      return (value:gsub('\\(.)', '%1'))
    end
  end
end

--- `java=<id>` in `<root>/.sdkmanrc`.
--- @param root string
--- @return string?
local function sdkman_id(root)
  for _, line in ipairs(lines(vim.fs.joinpath(root, '.sdkmanrc'))) do
    local id = line:match '^%s*java%s*=%s*(.-)%s*$'
    if id and id ~= '' then
      return id
    end
  end
end

--- `<home>/bin/java` when it is executable.
--- @param home string
--- @return string?
local function home_java(home)
  local java = vim.fs.joinpath(home, 'bin', 'java')
  if vim.fn.executable(java) == 1 then
    return java
  end
end

--- The `java` the server runs on for `root`, first match wins: `vim.g.grails_ls.java`; for a trusted `root`,
--- `org.gradle.java.home` in its `gradle.properties`, then `java=<id>` in its `.sdkmanrc` (an SDKMAN JDK under
--- `$SDKMAN_DIR`, default `~/.sdkman`); the JDK of `$JAVA_HOME`; `java` from `PATH`. A source that names no usable
--- JDK is warned about once and skipped. The server must run on the project's JDK: it compiles with the project's
--- Groovy, whose class-file reader is bounded by the JDK version. Project files are read only for a trusted root,
--- because they name a binary to run.
--- @param root? string
--- @return string
function M.java(root)
  if settings().java then
    return vim.fs.normalize(settings().java)
  end
  if root and require('grails.trust').is_trusted(root) then
    local home = gradle_java_home(root)
    if home then
      local java = home:sub(1, 1) == '/' and home_java(home)
      if java then
        return java
      end
      warn('org.gradle.java.home in %s/gradle.properties is %s, which has no bin/java; ignoring it', root, home)
    end
    local id = sdkman_id(root)
    if id then
      local sdkman = vim.env.SDKMAN_DIR and vim.env.SDKMAN_DIR ~= '' and vim.env.SDKMAN_DIR or vim.fs.joinpath(vim.env.HOME, '.sdkman')
      if id:find '[/\\]' or id == '.' or id == '..' then
        warn('%s/.sdkmanrc names java=%s, which is not an SDKMAN identifier; ignoring it', root, id)
      else
        local java = home_java(vim.fs.joinpath(sdkman, 'candidates', 'java', id))
        if java then
          return java
        end
        warn('%s/.sdkmanrc names java=%s, which is not installed (sdk install java %s); ignoring it', root, id, id)
      end
    end
  end
  local home = vim.env.JAVA_HOME
  if home and home ~= '' then
    local java = home_java(home)
    if java then
      return java
    end
    warn('JAVA_HOME is %s, which has no bin/java; ignoring it', home)
  end
  return 'java'
end

--- The command that runs the server for `root`.
--- @param root? string
function M.cmd(root)
  return { M.java(root), '-jar', M.jar() }
end

--- `cmd` of the client: the server on the JDK of the client's root, with the config's `cmd_env`, `cmd_cwd` and
--- `detached` (which Neovim applies itself only to a list `cmd`).
--- @param dispatchers vim.lsp.rpc.Dispatchers
--- @param config vim.lsp.ClientConfig
function M.rpc(dispatchers, config)
  local extra = { env = config.cmd_env, cwd = config.cmd_cwd, detached = config.detached }
  return vim.lsp.rpc.start(M.cmd(config.root_dir), dispatchers, extra)
end

--- What the result of `java -version` says about `java`: its major version (nil when unreadable), and why it cannot
--- run the server, if it cannot: no JDK behind the binary (such as the macOS `/usr/bin/java` stub) or a Java older
--- than 11.
--- @param java string
--- @param res vim.SystemCompleted
--- @return integer? version
--- @return string? problem
function M.java_version(java, res)
  local out = vim.trim((res.stderr or '') .. '\n' .. (res.stdout or ''))
  if res.code ~= 0 then
    return nil, ('`%s` found no usable JDK: %s. Install JDK 11 or later, or set vim.g.grails_ls.java.'):format(java, out:match '[^\n]*')
  end
  local major, minor = out:match 'version "(%d+)%.?(%d*)'
  local version = tonumber(major == '1' and minor or major)
  if version and version < 11 then
    return version, ("`%s` is Java %d; the server needs Java 11 or later. Set vim.g.grails_ls.java or the project's JDK."):format(java, version)
  end
  return version
end

--- Binaries whose `java -version` passed (=> true), or are being checked (=> callbacks waiting for the result).
--- @type table<string, true|fun(ok: boolean)[]>
local checked = {}

--- Runs `java -version` once per binary, asynchronously, and calls `done(ok)`. Not ok, and warned once, when
--- `java_version` names a problem. A version it cannot read passes. Only a pass is remembered, so a JDK installed
--- later is picked up.
--- @param java string
--- @param done fun(ok: boolean)
function M.check_java(java, done)
  local state = checked[java]
  if state == true then
    return done(true)
  elseif state then
    state[#state + 1] = done
    return
  end
  local waiting = { done }
  checked[java] = waiting
  local function finish(ok)
    checked[java] = ok or nil
    for _, cb in ipairs(waiting) do
      cb(ok)
    end
  end
  local started, err = pcall(vim.system, { java, '-version' }, { text = true }, function(res)
    vim.schedule(function()
      local _, problem = M.java_version(java, res)
      if problem then
        warn('%s', problem)
      end
      finish(not problem)
    end)
  end)
  if not started then
    warn('`%s` could not be run: %s', java, err)
    finish(false)
  end
end

--- The Gradle root of `bufnr` when it is a Grails build: the nearest directory with `settings.gradle(.kts)` or
--- `gradlew` that has a module with `grails-app/`. Nil otherwise (no Gradle build, `buildSrc`, a plain Gradle build).
--- @param bufnr integer
--- @return string?
function M.project_root(bufnr)
  local root = vim.fs.root(bufnr, { 'settings.gradle', 'settings.gradle.kts', 'gradlew' })
  if root and #require('grails.project').modules(root) > 0 then
    return root
  end
end

--- Source files the server serves. Not `*.gradle` or `Jenkinsfile` (filetype `groovy` too): for those the server
--- can do nothing but run Gradle.
local SOURCE = { groovy = true, gsp = true }

--- `root_dir` of the client: the Grails root of a Groovy or GSP source file, once the root is trusted
--- (`:GrailsTrust`) and, unless the user overrides `cmd`, the jar exists and the root's `java` runs Java 11 or later
--- (checked asynchronously). Each missing condition is notified once.
--- @param bufnr integer
--- @param on_dir fun(root: string)
function M.root_dir(bufnr, on_dir)
  if not SOURCE[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':e')] then
    return
  end
  local root = M.project_root(bufnr)
  if not root then
    return
  end
  if not require('grails.trust').is_trusted(root) then
    local text = 'grails_ls: not started for %s, which is not trusted: the server runs its Gradle build. Run :GrailsTrust to trust it.'
    vim.notify_once(text:format(root), vim.log.levels.INFO)
    return
  end
  if vim.lsp.config[M.name].cmd ~= M.rpc then
    -- The user's own command: Neovim reports a list `cmd` whose program is not executable.
    return on_dir(root)
  end
  if not vim.uv.fs_stat(M.jar()) then
    warn('no server jar at %s. Run :GrailsInstallServer, or set vim.g.grails_ls.jar.', M.jar())
    return
  end
  local java = M.java(root)
  if vim.fn.executable(java) ~= 1 then
    warn("`%s` is not executable. Set JAVA_HOME, the project's JDK or vim.g.grails_ls.java.", java)
    return
  end
  M.check_java(java, function(ok)
    if ok then
      on_dir(root)
    end
  end)
end

--- `before_init` of the client: `initializationOptions.trusted` is whether the allowlist has the root the server
--- uses (the first workspace folder, else `rootUri`), whatever started the client.
--- @param params lsp.InitializeParams
function M.before_init(params)
  local folder = params.workspaceFolders and params.workspaceFolders ~= vim.NIL and params.workspaceFolders[1]
  local uri = folder and folder.uri or params.rootUri
  local trusted = type(uri) == 'string' and require('grails.trust').is_trusted(vim.uri_to_fname(uri))
  local options = type(params.initializationOptions) == 'table' and params.initializationOptions or {}
  params.initializationOptions = vim.tbl_extend('force', options, { trusted = trusted })
end

--- `:GrailsTrust`: trusts the current buffer's Grails root and starts the client for that root's open buffers
--- (when `grails_ls` is enabled).
function M.trust()
  local root = M.project_root(vim.api.nvim_get_current_buf())
  if not root then
    vim.notify('GrailsTrust: this buffer is not in a Grails project', vim.log.levels.WARN)
    return
  end
  local trust = require 'grails.trust'
  trust.trust(root)
  vim.notify(('GrailsTrust: trusted %s'):format(trust.real(root)))
  if not vim.lsp.is_enabled(M.name) then
    return
  end
  local config = vim.lsp.config[M.name]
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and vim.list_contains(config.filetypes or {}, vim.bo[buf].filetype) then
      local copy = vim.deepcopy(config)
      copy.root_dir(buf, function(dir)
        if trust.real(dir) == trust.real(root) then
          copy.root_dir = dir
          vim.lsp.start(copy, { bufnr = buf })
        end
      end)
    end
  end
end

--- `:GrailsUntrust`: removes the current buffer's Grails root from the allowlist and stops its clients.
function M.untrust()
  local root = M.project_root(vim.api.nvim_get_current_buf())
  local trust = require 'grails.trust'
  if not root or not trust.revoke(root) then
    vim.notify('GrailsUntrust: this buffer is not in a trusted Grails project', vim.log.levels.WARN)
    return
  end
  for _, client in ipairs(vim.lsp.get_clients { name = M.name }) do
    if client.root_dir and trust.real(client.root_dir) == trust.real(root) then
      client:stop()
    end
  end
  vim.notify(('GrailsUntrust: %s is no longer trusted'):format(trust.real(root)))
end

--- Last `grails/status` state per client id.
--- @type table<integer, string>
M.states = {}

local TOKEN = 'grails/status'
local BUSY = { resolving = 'resolving the project', indexing = 'indexing' }

--- `grails/status` handler. Fed to Neovim's `$/progress` handler, so `vim.lsp.status()` and progress UIs show it;
--- a failure is also notified.
--- @param params { state: string, message?: string }
--- @param ctx lsp.HandlerContext
function M.on_status(_, params, ctx)
  local state, previous = params.state, M.states[ctx.client_id]
  M.states[ctx.client_id] = state
  local progress = vim.lsp.handlers['$/progress']
  if BUSY[state] then
    local kind = BUSY[previous] and 'report' or 'begin'
    progress(nil, { token = TOKEN, value = { kind = kind, title = 'Grails', message = BUSY[state] } }, ctx)
  elseif BUSY[previous] then
    progress(nil, { token = TOKEN, value = { kind = 'end', message = state } }, ctx)
  end
  if state == 'failed' then
    vim.notify('grails_ls: ' .. (params.message or 'the project could not be resolved'), vim.log.levels.ERROR)
  end
end

--- Whether a `grails_ls` client attached to `bufnr` has the project ready.
function M.ready(bufnr)
  for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr, name = M.name }) do
    if M.states[client.id] == 'ready' then
      return true
    end
  end
  return false
end

--- Sends a `grails/*` request to the current buffer's `grails_ls` client, notifying `doing` once it is sent;
--- `done(result)` on success. Without a client it only warns.
--- @param method string
--- @param doing string
--- @param done fun(result: any)
function M.request(method, doing, done)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = M.name })[1]
  if not client then
    vim.notify('grails_ls is not attached to this buffer', vim.log.levels.WARN)
    return
  end
  vim.notify('grails_ls: ' .. doing)
  client:request(method, nil, function(err, result)
    if err then
      vim.notify(('grails_ls: %s failed: %s'):format(method, err.message), vim.log.levels.ERROR)
    else
      done(result)
    end
  end, bufnr)
end

--- `:GrailsReindex`: asks the current buffer's `grails_ls` to read the source roots again (`grails/reindex`, which
--- never runs Gradle). The Lua server keeps no index, so without a client there is nothing to do.
function M.reindex()
  M.request('grails/reindex', 'rescanning the source files', function()
    vim.notify 'grails_ls: source files rescanned'
  end)
end

function M.reload_project()
  M.request('grails/reloadProject', 'reloading the project', function()
    vim.notify 'grails_ls: project reloaded'
  end)
end

function M.download_sources()
  M.request('grails/downloadSources', 'downloading sources jars', function(r)
    if type(r) ~= 'table' then
      vim.notify('grails_ls: grails/downloadSources returned no report', vim.log.levels.WARN)
      return
    end
    local text = ('grails_ls: sources jars: %d available, %d published by no library, %d failed'):format(r.available, r.unavailable, r.failed)
    vim.notify(r.message and text .. '\n' .. r.message or text, (r.failed > 0 or r.message) and vim.log.levels.WARN or vim.log.levels.INFO)
  end)
end

--- The release to install from the GitHub API's release list (newest first), among the non-draft releases that have
--- the jar: the one tagged `tag` when given; else the newest stable release, and only when there is none the newest
--- pre-release.
--- @param releases table[]
--- @param tag? string
--- @return { tag: string, url: string, digest?: string, prerelease: boolean }?
function M.pick_release(releases, tag)
  local newest_pre
  for _, release in ipairs(releases) do
    if not release.draft and (not tag or release.tag_name == tag) then
      for _, asset in ipairs(release.assets or {}) do
        if asset.name == M.asset then
          local digest = type(asset.digest) == 'string' and asset.digest or nil
          local pick = { tag = release.tag_name, url = asset.browser_download_url, digest = digest, prerelease = release.prerelease == true }
          if tag or not pick.prerelease then
            return pick
          end
          newest_pre = newest_pre or pick
        end
      end
    end
  end
  return newest_pre
end

--- Seconds curl may take to list the releases, and to download the jar.
M.list_timeout, M.download_timeout = 30, 300

--- Runs curl with `args` and calls `done(result)` on the main loop, or `fail(message)` when curl cannot be run.
local function curl(args, fail, done)
  local cmd = vim.list_extend({ 'curl', '--silent', '--show-error', '--location', '--retry', '2' }, args)
  local ok, err = pcall(vim.system, cmd, { text = true }, vim.schedule_wrap(done))
  if not ok then
    fail(('curl could not be run (%s). Install curl, or download the jar yourself and set vim.g.grails_ls.jar.'):format(err))
  end
end

--- Why curl failed, readably: a timeout, GitHub's rate limit, or curl's own message.
--- @param res vim.SystemCompleted
--- @param timeout integer the `--max-time` it ran with
local function curl_error(res, timeout)
  if res.code == 28 then
    return ('it timed out after %d seconds'):format(timeout)
  end
  local ok, body = pcall(vim.json.decode, res.stdout or '')
  local message = ok and type(body) == 'table' and type(body.message) == 'string' and body.message or nil
  if message and message:lower():find 'rate limit' then
    return "GitHub's API rate limit for this address is used up. Try again in an hour."
  end
  local err = vim.trim(res.stderr or '')
  err = err ~= '' and err or ('curl exited with %d'):format(res.code)
  return message and ('%s (%s)'):format(err, message) or err
end

--- SHA-256 of the file `path`, as `sha256:<hex>`, with `sha256sum` or `shasum` (Neovim's `sha256()` reads only
--- text before 0.12); `done(digest)`, or `done(nil, err)`.
--- @param path string
--- @param done fun(digest?: string, err?: string)
local function sha256(path, done)
  local cmd = vim.fn.executable 'sha256sum' == 1 and { 'sha256sum', path } or { 'shasum', '-a', '256', path }
  local ok, err = pcall(vim.system, cmd, { text = true }, function(res)
    local hex = res.code == 0 and res.stdout:match '^(%x+)%s'
    local problem = not hex and (vim.trim(res.stderr or '') ~= '' and vim.trim(res.stderr) or ('%s exited with %d'):format(cmd[1], res.code))
    vim.schedule(function()
      done(hex and 'sha256:' .. hex:lower(), problem or nil)
    end)
  end)
  if not ok then
    vim.schedule(function()
      done(nil, err)
    end)
  end
end

--- `:GrailsInstallServer[!] [tag]`: downloads the jar of release `tag`, else of the newest stable release (the newest
--- pre-release when there is none), into `install_dir()`, checked against the release's SHA-256 digest. `force`
--- downloads it even when that release is installed already.
--- @param force? boolean
--- @param tag? string
--- @param done? fun(ok: boolean) called when finished (tests)
function M.install(force, tag, done)
  done = done or function() end
  tag = tag ~= '' and tag or nil
  local dir = M.install_dir()
  local target = vim.fs.joinpath(dir, M.asset)
  local version_file = vim.fs.joinpath(dir, 'version')
  local function fail(msg)
    vim.notify('GrailsInstallServer: ' .. msg, vim.log.levels.ERROR)
    done(false)
  end
  vim.notify(tag and ('GrailsInstallServer: looking up release %s'):format(tag) or 'GrailsInstallServer: looking up the newest release')
  local list_args = { '--fail-with-body', '--max-time', tostring(M.list_timeout), '-H', 'Accept: application/vnd.github+json', M.releases_url }
  curl(list_args, fail, function(res)
    if res.code ~= 0 then
      return fail('listing the releases failed: ' .. curl_error(res, M.list_timeout))
    end
    local ok, releases = pcall(vim.json.decode, res.stdout)
    local release = ok and type(releases) == 'table' and M.pick_release(releases, tag)
    if not release then
      return fail(tag and ('no release %s has %s'):format(tag, M.asset) or ('no release has ' .. M.asset))
    end
    local installed = vim.uv.fs_stat(target) and lines(version_file)[1]
    if installed == release.tag and not force then
      vim.notify(('GrailsInstallServer: %s is installed already (:GrailsInstallServer! downloads it again)'):format(release.tag))
      return done(true)
    end
    local expected = release.digest and release.digest:match '^sha256:(%x+)$'
    if release.digest and not expected then
      return fail(('%s has a digest this client cannot check: %s'):format(release.tag, release.digest))
    end
    vim.fn.mkdir(dir, 'p')
    -- A name of its own, so concurrent runs never write one file; renamed into place, so the jar is never partial.
    local fd, partial = vim.uv.fs_mkstemp(target .. '.XXXXXX')
    if not fd then
      return fail(('cannot write to %s: %s'):format(dir, partial))
    end
    vim.uv.fs_close(fd)
    vim.uv.fs_chmod(partial, tonumber('644', 8)) -- mkstemp makes it 600
    local function discard(msg)
      os.remove(partial)
      fail(msg)
    end
    local function finish()
      local renamed, err = os.rename(partial, target)
      if not renamed then
        return discard(err)
      end
      vim.fn.writefile({ release.tag }, version_file)
      local kind = release.prerelease and (tag and ' (a pre-release)' or ' (a pre-release: no stable release has the jar)') or ''
      local note = settings().jar and ' (unused while vim.g.grails_ls.jar is set)' or ''
      local text = 'GrailsInstallServer: installed %s%s at %s%s. Reopen a Groovy or GSP file to start it; restart a running client.'
      vim.notify(text:format(release.tag, kind, target, note))
      done(true)
    end
    curl({ '--fail', '--max-time', tostring(M.download_timeout), '-o', partial, release.url }, discard, function(get)
      if get.code ~= 0 then
        return discard(('downloading %s failed: %s'):format(release.url, curl_error(get, M.download_timeout)))
      end
      if not expected then
        local text = 'GrailsInstallServer: release %s publishes no digest for %s, so the download is not verified'
        vim.notify(text:format(release.tag, M.asset), vim.log.levels.WARN)
        return finish()
      end
      sha256(partial, function(actual, err)
        if not actual then
          return discard('checking the download failed: ' .. err)
        elseif actual ~= 'sha256:' .. expected:lower() then
          return discard(('the download of %s does not match its digest (%s, got %s); nothing was installed'):format(release.tag, release.digest, actual))
        end
        finish()
      end)
    end)
  end)
end

--- The oldest server this client is made for: the first that reports `serverInfo.version`.
M.min_server_version = '0.1.3-m6'

--- `on_init` of the client: warns once when the server is older than `min_server_version`. A server that reports no
--- version predates the field, so it is older too; a version that is not semver is no reason to warn.
--- @param result lsp.InitializeResult
function M.on_init(_, result)
  local info = type(result) == 'table' and result.serverInfo
  local version = type(info) == 'table' and type(info.version) == 'string' and info.version or nil
  local parsed = version and vim.version.parse(version)
  if version and (not parsed or not vim.version.lt(parsed, M.min_server_version)) then
    return
  end
  local update = settings().jar and 'Update the jar at vim.g.grails_ls.jar' or 'Run :GrailsInstallServer to update it'
  local what = version and ('is %s'):format(version) or 'reports no version'
  warn('the server %s, older than the %s this grails.nvim needs, so some features may not work. %s.', what, M.min_server_version, update)
end

return M
