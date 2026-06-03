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
    table.insert(candidates, format_item(item, M.state.opts))
  end
  return candidates
end

function M.accept(mode, str)
  -- 1. Close the CtrlP window
  vim.fn['ctrlp#exit']()

  if not M.state then
    return
  end

  -- 2. Find the selected item
  local chosen_item = nil
  local chosen_idx = nil
  for i, item in ipairs(M.state.items) do
    if format_item(item, M.state.opts) == str then
      chosen_item = item
      chosen_idx = i
      break
    end
  end

  M.state.chosen = true
  local cb = M.state.on_choice
  M.state = nil

  -- 3. Run callback asynchronously
  vim.schedule(function()
    cb(chosen_item, chosen_idx)
  end)
end

function M.select(items, opts, on_choice)
  if not items or #items == 0 then
    on_choice(nil, nil)
    return
  end

  -- Lazy-load CtrlP if not loaded yet
  if vim.fn.exists('g:loaded_ctrlp') == 0 then
    local ok, lazy = pcall(require, 'lazy')
    if ok then
      lazy.load({ plugins = { 'ctrlp.vim' } })
    end
  end

  opts = opts or {}
  local prompt = opts.prompt or "Select:"

  -- Initialize session state
  M.state = {
    items = items,
    opts = opts,
    on_choice = on_choice,
    chosen = false,
  }

  -- Register callbacks and the extension
  M.register()

  -- Find extension index in g:ctrlp_ext_vars
  local ext_vars = vim.g.ctrlp_ext_vars or {}
  local ext_idx = nil
  for i, e in ipairs(ext_vars) do
    if e.sname == 'sel' then
      ext_idx = i
      break
    end
  end

  if not ext_idx then
    -- Fallback in case registration failed
    M.state = nil
    on_choice(nil, nil)
    return
  end

  -- Dynamically update lname with the prompt
  ext_vars[ext_idx].lname = prompt
  vim.g.ctrlp_ext_vars = ext_vars

  -- Calculate ID and run CtrlP
  local builtins = vim.g.ctrlp_builtins or 2
  local ctrlp_id = builtins + ext_idx

  vim.fn['ctrlp#init'](ctrlp_id)

  -- If ctrlp#init returned and we haven't chosen, then CtrlP was cancelled
  if M.state and not M.state.chosen then
    local cb = M.state.on_choice
    M.state = nil
    vim.schedule(function()
      cb(nil, nil)
    end)
  end
end

return M
