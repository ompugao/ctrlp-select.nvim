local M = {}

M.state = nil

local function log(msg)
  local f = io.open('/home/sifi/ctrlp_debug.log', 'a')
  if f then
    f:write(os.date('%Y-%m-%d %H:%M:%S ') .. tostring(msg) .. '\n')
    f:close()
  end
end

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
  log("register() called")
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
    log("Extension registered in g:ctrlp_ext_vars")
  else
    log("Extension already registered in g:ctrlp_ext_vars")
  end
end

function M.get_candidates()
  log("get_candidates() called")
  if not M.state then
    log("get_candidates: state is nil!")
    return {}
  end
  local candidates = {}
  for i, item in ipairs(M.state.items) do
    local formatted = format_item(item, M.state.opts)
    formatted = formatted:gsub("\n", " ")
    table.insert(candidates, string.format("%d: %s", i, formatted))
  end
  log("get_candidates returned " .. #candidates .. " candidates")
  return candidates
end

function M.accept(mode, str)
  log("accept() called with mode=" .. tostring(mode) .. ", str=" .. tostring(str))
  vim.fn['ctrlp#exit']()

  if not M.state then
    log("accept: state is nil!")
    return
  end

  local idx_str = str:match("^(%d+):")
  local chosen_idx = tonumber(idx_str)
  local chosen_item = nil

  if chosen_idx and M.state.items[chosen_idx] then
    chosen_item = M.state.items[chosen_idx]
    log("accept: matched by index=" .. tostring(chosen_idx))
  else
    log("accept: index match failed, falling back to string match")
    for i, item in ipairs(M.state.items) do
      if format_item(item, M.state.opts) == str then
        chosen_item = item
        chosen_idx = i
        log("accept: matched by string index=" .. tostring(i))
        break
      end
    end
  end

  M.state.chosen = true
  local cb = M.state.on_choice
  M.state = nil

  vim.schedule(function()
    log("Invoking selection callback with item=" .. tostring(chosen_item) .. ", idx=" .. tostring(chosen_idx))
    cb(chosen_item, chosen_idx)
  end)
end

function M.select(items, opts, on_choice)
  log("select() called with " .. tostring(items and #items or 0) .. " items")
  if not items or #items == 0 then
    log("select: items is empty, calling callback with nil")
    on_choice(nil, nil)
    return
  end

  if vim.fn.exists('g:loaded_ctrlp') == 0 then
    log("select: loading ctrlp.vim via lazy")
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
    log("select: ext_idx not found, aborting")
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
      log("autocmd triggered: CtrlP buffer closed")
      if M.state and not M.state.chosen then
        log("autocmd: CtrlP was cancelled, calling callback with nil")
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
  log("select: launching ctrlp with id=" .. tostring(ctrlp_id))

  vim.fn['ctrlp#init'](ctrlp_id)
  log("select: ctrlp#init returned")
end

return M
