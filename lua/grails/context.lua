-- "What is under the cursor", from the gsp or groovy syntax tree.
local util = require 'grails.util'

local M = {}

--- @class grails.Context
--- @field lang 'gsp'|'groovy'
--- @field value? string the path or name under the cursor; nil when it is computed (`${}`, GString)
--- @field value_range? Range4 0-based byte range of the value
--- GSP:
--- @field tag? { ns?: string, name: string } `ns` is nil for a plain HTML tag
--- @field attr? string attribute holding the value; nil on a `tmpl:` tag name
--- @field attrs? table<string, string> the tag's attributes with plain text values
--- Groovy:
--- @field call? string method called with the value as a named argument (`render`)
--- @field named_arg? string
--- @field args? table<string, string> the call's named arguments with plain string values
--- @field property? string static property assigned the value (`layout`)
--- @field enclosing_class? string
--- @field enclosing_method? string method, or property assigned a closure

--- Lowest named node at a 0-based byte position.
local function node_at(root, row, col)
  return root:named_descendant_for_range(row, col, row, col)
end

local function ancestor(node, types)
  while node do
    if types[node:type()] then
      return node
    end
    node = node:parent()
  end
end

-- GSP --------------------------------------------------------------------------

local TAGS = { gsp_tag_open = true, gsp_tag_self_closing = true, gsp_tag_close = true }

--- Plain value of an `attribute_value` node: its text when it holds one `text`
--- child (or nothing), nil when it holds `${}` or a `[...]` map.
local function plain_value(doc, value)
  local count = value:named_child_count()
  if count == 0 then
    return ''
  end
  local child = value:named_child(0)
  if count == 1 and child:type() == 'text' then
    return util.node_text(doc, child)
  end
end

local function tag_info(doc, tag)
  local ns, name = tag:field('namespace')[1], tag:field('name')[1]
  local attrs = {}
  for _, attr in ipairs(tag:named_children()) do
    if attr:type() == 'attribute' then
      local key, value = attr:field('name')[1], attr:field('value')[1]
      local text = value and plain_value(doc, value)
      if key and text then
        attrs[util.node_text(doc, key)] = text
      end
    end
  end
  return { ns = ns and util.node_text(doc, ns), name = name and util.node_text(doc, name) or '' }, attrs
end

--- A layout `<meta name="layout" content="x">` on the cursor line, when the cursor is on it.
local function meta_layout(line, row, col)
  for s, tag, e in line:gmatch '()(<meta%s[^>]*>)()' do
    if col >= s - 1 and col < e - 1 and tag:match '%sname%s*=%s*["\']layout["\']' then
      local at, value = tag:match '%scontent%s*=%s*["\']()([^"\']*)'
      if value then
        local vs = s - 1 + at - 1
        return {
          lang = 'gsp',
          tag = { name = 'meta' },
          attr = 'content',
          attrs = { name = 'layout', content = value },
          value = value,
          value_range = { row, vs, row, vs + #value },
        }
      end
    end
  end
end

local function gsp_context(doc, root, row, col)
  local node = node_at(root, row, col)
  if not node then
    return nil
  end
  if node:type() == 'content' then
    return meta_layout(doc.lines[row + 1], row, col)
  end
  -- Inside `${}` the cursor is on Groovy code, not on a path.
  if ancestor(node, { expression = true, groovy_value = true }) then
    return nil
  end
  local tag_node = ancestor(node, TAGS)
  if not tag_node then
    return nil
  end
  local tag, attrs = tag_info(doc, tag_node)
  local value_node = ancestor(node, { attribute_value = true })
  if value_node then
    local attr = value_node:parent()
    local key = attr and attr:field('name')[1]
    local value = plain_value(doc, value_node)
    local sr, sc, er, ec = value_node:range()
    if value_node:child_count() >= 2 then -- inside the quotes
      sc, ec = sc + 1, ec - 1
    end
    return {
      lang = 'gsp',
      tag = tag,
      attr = key and util.node_text(doc, key),
      attrs = attrs,
      value = value,
      value_range = { sr, sc, er, ec },
    }
  end
  -- The name of a `tmpl:` tag is a template path.
  if tag.ns == 'tmpl' and ancestor(node, { tag_name = true, namespace = true }) then
    local name = tag_node:field('name')[1]
    return { lang = 'gsp', tag = tag, attrs = attrs, value = tag.name, value_range = name and { name:range() } }
  end
end

-- Groovy -----------------------------------------------------------------------

local CALLS = { function_call = true, juxt_function_call = true }

--- Text of a plain string literal; nil for a GString with `${}`.
local function string_value(doc, node)
  local parts = {}
  for _, child in ipairs(node:named_children()) do
    if child:type() ~= 'string_content' then
      return nil
    end
    parts[#parts + 1] = util.node_text(doc, child)
  end
  return table.concat(parts)
end

--- Name of a call's method: `render` for `render(...)` and `g.link` gives `link`.
local function call_name(doc, call)
  local fn = call:field('function')[1]
  if not fn then
    return nil
  end
  if fn:type() == 'identifier' then
    return util.node_text(doc, fn)
  end
  if fn:type() == 'dotted_identifier' then
    local last = fn:named_child(fn:named_child_count() - 1)
    return last and util.node_text(doc, last)
  end
end

--- Name of the class, and of the method or closure property, around a node.
--- @return string? class, string? method
function M.enclosing(doc, node)
  local class, method
  while node do
    local type = node:type()
    if type == 'class_definition' then
      local name = node:field('name')[1]
      class = name and util.node_text(doc, name)
      break
    elseif not method and type == 'function_definition' then
      local name = node:field('function')[1]
      method = name and util.node_text(doc, name)
    elseif not method and type == 'declaration' then
      local name, value = node:field('name')[1], node:field('value')[1]
      if name and value and value:type() == 'closure' then
        method = util.node_text(doc, name)
      end
    end
    node = node:parent()
  end
  return class, method
end

--- Fallback for a cursor inside an ERROR node, where the tree has no call
--- structure: a quoted named argument of a call on the cursor line,
--- `name(key: 'value', ...)` or `name key: 'value', ...`.
--- @param line string
--- @param row integer
--- @param col integer
--- @return grails.Context?
function M.scan_line(line, row, col)
  for s, quote, value, e in line:gmatch '()(["\'])(.-)%2()' do
    if col >= s - 1 and col < e - 1 then
      local prefix = line:sub(1, s - 1)
      local key = prefix:match '([%a_][%w_]*)%s*:%s*$'
      local call = prefix:match '([%a_][%w_]*)%s*%([^()]*$' or prefix:match '^%s*[%w_.]-([%a_][%w_]*)%s+[%a_][%w_]*%s*:'
      if not (key and call) then
        return nil
      end
      local args = {}
      for k, q, v in line:gmatch '([%a_][%w_]*)%s*:%s*(["\'])(.-)%2' do
        args[k] = (q == "'" or not v:find('${', 1, true)) and v or nil
      end
      return {
        lang = 'groovy',
        call = call,
        named_arg = key,
        args = args,
        value = (quote == "'" or not value:find('${', 1, true)) and value or nil,
        value_range = { row, s, row, e - 2 },
      }
    end
  end
end

local function tree_context(doc, node)
  local str = ancestor(node, { string = true })
  if not str then
    return nil
  end
  local ctx = { lang = 'groovy', value = string_value(doc, str) }
  local sr, sc, er, ec = str:range()
  ctx.value_range = { sr, sc + 1, er, ec - 1 }
  ctx.enclosing_class, ctx.enclosing_method = M.enclosing(doc, str)

  local parent = str:parent()
  if parent and parent:type() == 'map_item' then
    local key, list = parent:field('key')[1], parent:parent()
    local call = list and list:type() == 'argument_list' and list:parent()
    if not (key and call and CALLS[call:type()]) then
      return nil
    end
    ctx.call = call_name(doc, call)
    ctx.named_arg = util.node_text(doc, key)
    ctx.args = {}
    for _, item in ipairs(list:named_children()) do
      local k, v = item:field('key')[1], item:field('value')[1]
      if item:type() == 'map_item' and k and v and v:type() == 'string' then
        ctx.args[util.node_text(doc, k)] = string_value(doc, v)
      end
    end
    return ctx
  end
  -- A static property of the class: `static layout = 'main'`.
  local body = parent and parent:type() == 'declaration' and parent:parent()
  if body and body:type() == 'closure' and body:parent():type() == 'class_definition' then
    local name, static = parent:field('name')[1], false
    for _, child in ipairs(parent:named_children()) do
      static = static or (child:type() == 'modifier' and util.node_text(doc, child) == 'static')
    end
    ctx.property = static and name and util.node_text(doc, name) or nil
    return ctx.property and ctx
  end
end

local function groovy_context(doc, root, row, col)
  local node = node_at(root, row, col)
  if not node then
    return nil
  end
  local ctx = tree_context(doc, node)
  if not ctx and ancestor(node, { ERROR = true }) then
    ctx = M.scan_line(doc.lines[row + 1], row, col)
  end
  return ctx
end

--- Context at a 0-based byte position of a document.
--- @param doc grails.Doc
--- @param lang 'gsp'|'groovy'
--- @param row integer
--- @param col integer
--- @return grails.Context?
function M.at(doc, lang, row, col)
  local root = util.parse(doc, lang)
  if not root then
    return nil
  end
  if lang == 'gsp' then
    return gsp_context(doc, root, row, col)
  end
  return groovy_context(doc, root, row, col)
end

return M
