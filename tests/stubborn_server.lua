-- nvim -l tests/stubborn_server.lua <log> <version>
-- A language server that answers `initialize` and nothing else: it ignores `shutdown` and `exit`, and keeps running
-- once its input is closed. Appends its pid, then each method it receives, to <log>.
local log, version = _G.arg[1], _G.arg[2]

local function append(line)
  vim.fn.writefile({ line }, log, 'a')
end

local function send(msg)
  local body = vim.json.encode(msg)
  io.stdout:write(('Content-Length: %d\r\n\r\n%s'):format(#body, body))
  io.stdout:flush()
end

append(tostring(vim.fn.getpid()))
while true do
  local length
  repeat
    local line = io.stdin:read '*l'
    if not line then
      -- the client is gone: stay, as a server stuck in a long `shutdown` would
      while true do
        vim.uv.sleep(1000)
      end
    end
    length = tonumber(line:match '^Content%-Length: (%d+)') or length
  until line:gsub('\r$', '') == ''
  local msg = vim.json.decode(io.stdin:read(length))
  append(msg.method or 'response')
  if msg.method == 'initialize' then
    send { jsonrpc = '2.0', id = msg.id, result = { capabilities = {}, serverInfo = { name = 'grails-language-server', version = version } } }
  end
end
