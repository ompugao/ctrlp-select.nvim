local M = {}

M.state = nil

local function setup_vim_callbacks()
  vim.cmd([[
    if !exists('*CtrlPSelectInit')
      function! CtrlPSelectInit()
        return v:lua.require('ctrlp_select').get_candidates()
      endfunction
    endif

    if !exists('*CtrlPSelectAccept')
      function! CtrlPSelectAccept(mode, str)
        call v:lua.require('ctrlp_select').accept(a:mode, a:str)
      endfunction
    endif
  ]])
end

local function format_item(item, opts)
  if opts and opts.format_item then
    local ok, res = pcall(opts.format_item, item)
    if ok then
      return tostring(res)
    end
  end
  return tostring(item)
end

function M.register()
  setup_vim_callbacks()

  local ext_vars = vim.g.ctrlp_ext_vars or {}
  local found_idx = nil
  for i, e in ipairs(ext_vars) do
    if e.sname == 'sel' then
      found_idx = i
      break
    end
  end

  if not found_idx then
    local ext = {
      init = 'CtrlPSelectInit()',
      accept = 'CtrlPSelectAccept',
      lname = 'select',
      sname = 'sel',
      type = 'line',
      sort = 0,
      nolim = 1,
    }
    table.insert(ext_vars, ext)
    vim.g.ctrlp_ext_vars = ext_vars
  end
end

function M.get_candidates()
  if not M.state then
    return {}
  end
  local candidates = {}
  for i, item in ipairs(M.state.items) do
    local formatted = format_item(item, M.state.opts)
    formatted = formatted:gsub("\n", " ")
    table.insert(candidates, string.format("%d: %s", i, formatted))
  end
  return candidates
end

function M.accept(mode, str)
  -- 1. Close the CtrlP window
  vim.fn['ctrlp#exit']()

  if not M.state then
    return
  end

  local idx_str = str:match("^(%d+):")
  local chosen_idx = tonumber(idx_str)
  local chosen_item = nil

  if chosen_idx and M.state.items[chosen_idx] then
    chosen_item = M.state.items[chosen_idx]
  else
    -- Fallback: exact string matching if the prefix wasn't matched
    for i, item in ipairs(M.state.items) do
      if format_item(item, M.state.opts) == str then
        chosen_item = item
        chosen_idx = i
        break
      end
    end
  end

  M.state.chosen = true
  local cb = M.state.on_choice
  M.state = nil

  vim.schedule(function()
    cb(chosen_item, chosen_idx)
  end)
end

function M.select(items, opts, on_choice)
  if not items or #items == 0 then
    on_choice(nil, nil)
    return
  end

  if vim.fn.exists('g:loaded_ctrlp') == 0 then
    local ok, lazy = pcall(require, 'lazy')
    if ok then
      lazy.load({ plugins = { 'ctrlp.vim' } })
    end
  end

  opts = opts or {}
  local prompt = opts.prompt or "Select:"

  M.state = {
    items = items,
    opts = opts,
    on_choice = on_choice,
    chosen = false,
  }

  M.register()

  local ext_vars = vim.g.ctrlp_ext_vars or {}
  local ext_idx = nil
  for i, e in ipairs(ext_vars) do
    if e.sname == 'sel' then
      ext_idx = i
      break
    end
  end

  if not ext_idx then
    M.state = nil
    on_choice(nil, nil)
    return
  end

  ext_vars[ext_idx].lname = prompt
  vim.g.ctrlp_ext_vars = ext_vars

  -- Setup autocmd to detect cancellation when the CtrlP buffer is closed
  local autocmd_id
  autocmd_id = vim.api.nvim_create_autocmd({"BufDelete", "BufWinLeave"}, {
    pattern = "__CtrlP__",
    once = true,
    callback = function()
      if M.state and not M.state.chosen then
        local cb = M.state.on_choice
        M.state = nil
        vim.schedule(function()
          cb(nil, nil)
        end)
      end
      if autocmd_id then
        pcall(vim.api.nvim_del_autocmd, autocmd_id)
      end
    end
  })

  local builtins = vim.g.ctrlp_builtins or 2
  local ctrlp_id = builtins + ext_idx

  vim.fn['ctrlp#init'](ctrlp_id)
end

return M
