-- string.lua: string-related tools
-- This file is a part of lua-nucleo library
-- Copyright (c) lua-nucleo authors (see file `COPYRIGHT` for the license)

local table_concat, table_insert = table.concat, table.insert
local string_find, string_sub = string.find, string.sub
local assert, pairs = assert, pairs

local tidentityset
      = import 'lua-nucleo/table-utils.lua'
      {
        'tidentityset'
      }

local make_concatter -- TODO: rename, is not factory
do
  make_concatter = function()
    local buf = {}

    local function cat(v)
      buf[#buf + 1] = v
      return cat
    end

    local concat = function(glue)
      return table_concat(buf, glue or "")
    end

    return cat, concat
  end
end

-- Remove trailing and leading whitespace from string.
-- From Programming in Lua 2 20.4
local trim = function(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local create_escape_subst = function(string_subst, ignore)
  ignore = ignore or { "\n", "\t" }
  local subst = setmetatable(
      tidentityset(ignore),
      {
        __metatable = "escape.char";
        __index = function(t, k)
          local v = (string_subst):format(k:byte())
          t[k] = v
          return v
        end;
      }
    )
  return subst
end

-- WARNING: This is not a suitable replacement for urlencode
local escape_string
do
  local escape_subst = create_escape_subst("%%%02X")
  escape_string = function(str)
    return (str:gsub("[%c%z\128-\255]", escape_subst))
  end
end

local url_encode
do
  local escape_subst = create_escape_subst("%%%02X")
  url_encode = function(str)
    return str:gsub("([^%w-_ ])", escape_subst):gsub(" ", "+")
  end
end

local htmlspecialchars = nil
do
  local subst =
  {
    ["&"] = "&amp;";
    ['"'] = "&quot;";
    ["'"] = "&apos;";
    ["<"] = "&lt;";
    [">"] = "&gt;";
  }

  htmlspecialchars = function(value)
    if type(value) == "number" then
      return value
    end
    value = tostring(value)
    return (value:gsub("[&\"'<>]", subst))
  end
end

local cdata_wrap = function(value)
  -- "]]>" is escaped as ("]]" + "]]><![CDATA[" + ">")
  return '<![CDATA[' .. value:gsub("]]>", ']]]]><![CDATA[>') .. ']]>'
end

local cdata_cat = function(cat, value)
  -- "]]>" is escaped as ("]]" + "]]><![CDATA[" + ">")
  cat '<![CDATA[' (value:gsub("]]>", ']]]]><![CDATA[>')) ']]>'
end

-- TODO: Looks ugly and slow. Rewrite.
-- Based on http://lua-users.org/wiki/MakingLuaLikePhp
local split_by_char = function(str, div)
  local result = false
  if div ~= "" then
    local pos = 0
    result = {}

    if str ~= "" then
      -- for each divider found
      for st, sp in function() return string_find(str, div, pos, true) end do
        -- Attach chars left of current divider
        table_insert(result, string_sub(str, pos, st - 1))
        pos = sp + 1 -- Jump past current divider
      end
      -- Attach chars right of last divider
      table_insert(result, string_sub(str, pos))
    end
  end
  return result
end

local count_substrings = function(str, substr)
  local count = 0

  local s, e = 0, 0
  while true do
    s, e = str:find(substr, e + 1, true)
    if s ~= nil then
      count = count + 1
    else
      break
    end
  end

  return count
end

local split_by_offset = function(str, offset, skip_right)
  assert(offset <= #str)
  return str:sub(1, offset), str:sub(offset + 1 + (skip_right or 0))
end

local fill_placeholders_ex = function(capture, str, dict)
  return (str:gsub(capture, dict))
end

local fill_placeholders = function(str, dict)
  return fill_placeholders_ex("%$%((.-)%)", str, dict)
end

local fill_curly_placeholders = function(str, dict)
  return fill_placeholders_ex("%${(.-)}", str, dict)
end

local kv_concat = function(t, kv_glue, pair_glue, pairs_fn)
  pair_glue = pair_glue or ""
  pairs_fn = pairs_fn or pairs

  local cat, concat = make_concatter()
  local glue = ""
  for k, v in pairs_fn(t) do
    cat (glue) (k) (kv_glue) (v)
    glue = pair_glue
  end
  return concat()
end

local escape_lua_pattern
do
  local matches =
  {
    ["^"] = "%^";
    ["$"] = "%$";
    ["("] = "%(";
    [")"] = "%)";
    ["%"] = "%%";
    ["."] = "%.";
    ["["] = "%[";
    ["]"] = "%]";
    ["*"] = "%*";
    ["+"] = "%+";
    ["-"] = "%-";
    ["?"] = "%?";
  }

  escape_lua_pattern = function(s)
    return (s:gsub(".", matches))
  end
end

local escape_for_json
do
  -- Based on luajson code (comments copied verbatim).
  -- https://github.com/harningt/luajson/blob/master/lua/json/encode/strings.lua

  local matches =
  {
    ['"'] = '\\"';
    ['\\'] = '\\\\';
--    ['/'] = '\\/'; -- TODO: ?! Do we really need to escape this?
    ['\b'] = '\\b';
    ['\f'] = '\\f';
    ['\n'] = '\\n';
    ['\r'] = '\\r';
    ['\t'] = '\\t';
    ['\v'] = '\\v'; -- not in official spec, on report, removing
  }

  -- Pre-encode the control characters to speed up encoding...
  -- NOTE: UTF-8 may not work out right w/ JavaScript
  -- JavaScript uses 2 bytes after a \u... yet UTF-8 is a
  -- byte-stream encoding, not pairs of bytes (it does encode
  -- some letters > 1 byte, but base case is 1)
  for i = 0, 255 do
    local c = string.char(i)
    if c:match('[%z\1-\031\128-\255]') and not matches[c] then
      -- WARN: UTF8 specializes values >= 0x80 as parts of sequences...
      --       without \x encoding, do not allow encoding > 7F
      matches[c] = ('\\u%.4X'):format(i)
    end
  end

  escape_for_json = function(s)
    return '"' .. s:gsub('[\\"/%z\1-\031]', matches) .. '"'
  end
end

local starts_with = function(str, prefix)
  if type(str) ~= 'string' or type(prefix) ~= 'string' then return false end
  local plen = #prefix
  return (#str >= plen) and (str:sub(1, plen) == prefix)
end

local ends_with = function(str, suffix)
  if type(str) ~= 'string' or type(suffix) ~= 'string' then return false end
  local slen = #suffix
  return slen == 0 or ((#str >= slen) and (str:sub(-slen, -1) == suffix))
end

local is_ipv4 = function (str)
  -- N.B. ipv6 contains no dots, so ipv4 pattern be checked
  local parts = split_by_char(str, '.')
  if not parts or #parts ~= 4 then return false end
  -- loose check on whether parts belong to [0..255]
  for _, x in ipairs(parts) do
    x = tonumber(x)
    if not x or x > 255 then return false end
  end
  return true
end

return
{
  escape_string = escape_string;
  make_concatter = make_concatter;
  trim = trim;
  create_escape_subst = create_escape_subst;
  htmlspecialchars = htmlspecialchars;
  fill_placeholders_ex = fill_placeholders_ex;
  fill_placeholders = fill_placeholders;
  fill_curly_placeholders = fill_curly_placeholders;
  cdata_wrap = cdata_wrap;
  cdata_cat = cdata_cat;
  split_by_char = split_by_char;
  split_by_offset = split_by_offset;
  count_substrings = count_substrings;
  kv_concat = kv_concat;
  escape_lua_pattern = escape_lua_pattern;
  escape_for_json = escape_for_json;
  starts_with = starts_with;
  ends_with = ends_with;
  url_encode = url_encode;
  is_ipv4 = is_ipv4;
}
