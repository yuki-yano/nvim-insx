local kit = require('insx.kit')
local Async = require('insx.kit.Async')

local buf = vim.api.nvim_create_buf(false, true)

---@alias insx.kit.Vim.Keymap.Keys { keys: string, remap?: boolean }
---@alias insx.kit.Vim.Keymap.KeysSpecifier string|insx.kit.Vim.Keymap.Keys

---@param keys insx.kit.Vim.Keymap.KeysSpecifier
---@return insx.kit.Vim.Keymap.Keys
local function to_keys(keys)
  if type(keys) == 'table' then
    return keys
  end
  return { keys = keys, remap = false }
end

local Keymap = {}

Keymap._callbacks = {}

---Replace termcodes.
---@param keys string
---@return string
function Keymap.termcodes(keys)
  return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

---Normalize keycode.
function Keymap.normalize(s)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Plug>(insx.Vim.Keymap.normalize)', s, {})
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == '<Plug>(insx.Vim.Keymap.normalize)' then
      return map.rhs
    end
  end
end

---Set callback for consuming next typeahead.
---@param callback fun()
---@return insx.kit.Async.AsyncTask
function Keymap.next(callback)
  return Keymap.send(''):next(callback)
end

---Send keys.
---@param keys insx.kit.Vim.Keymap.KeysSpecifier|insx.kit.Vim.Keymap.KeysSpecifier[]
---@param no_insert? boolean
---@return insx.kit.Async.AsyncTask
function Keymap.send(keys, no_insert)
  local unique_id = kit.unique_id()
  return Async.new(function(resolve, _)
    Keymap._callbacks[unique_id] = resolve

    local callback = Keymap.termcodes(('<Cmd>lua require("insx.kit.Vim.Keymap")._resolve(%s)<CR>'):format(unique_id))
    if no_insert then
      for _, keys_ in ipairs(kit.to_array(keys)) do
        keys_ = to_keys(keys_)
        vim.api.nvim_feedkeys(keys_.keys, keys_.remap and 'm' or 'n', true)
      end
      vim.api.nvim_feedkeys(callback, 'n', true)
    else
      vim.api.nvim_feedkeys(callback, 'in', true)
      for _, keys_ in ipairs(kit.reverse(kit.to_array(keys))) do
        keys_ = to_keys(keys_)
        vim.api.nvim_feedkeys(keys_.keys, 'i' .. (keys_.remap and 'm' or 'n'), true)
      end
    end
  end):catch(function()
    Keymap._callbacks[unique_id] = nil
  end)
end

---Return sendabke keys with callback function.
---@param callback fun(...: any): any
---@return string
function Keymap.to_sendable(callback)
  local unique_id = kit.unique_id()
  Keymap._callbacks[unique_id] = Async.async(callback)
  return Keymap.termcodes(('<Cmd>lua require("insx.kit.Vim.Keymap")._resolve(%s)<CR>'):format(unique_id))
end

---Test spec helper.
---@param spec fun(): any
function Keymap.spec(spec)
  local task = Async.resolve():next(Async.async(spec))
  vim.api.nvim_feedkeys('', 'x', true)
  task:sync()
  collectgarbage('collect')
  vim.wait(200)
end

---Resolve running keys.
---@param unique_id integer
function Keymap._resolve(unique_id)
  Keymap._callbacks[unique_id]()
  Keymap._callbacks[unique_id] = nil
end

return Keymap
