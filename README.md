# ctrlp-select.nvim

A Neovim plugin that overrides Neovim's built-in `vim.ui.select` using `ctrlp.vim` as the selector interface.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'ompugao/ctrlp-select.nvim',
  dependencies = { 'ctrlpvim/ctrlp.vim' },
  config = function()
    vim.ui.select = require('ctrlp_select').select
  end,
}
```

## How it works

When a plugin or Lua script invokes `vim.ui.select(...)`, it dynamically registers a custom extension with `ctrlp.vim`, sets the prompt dynamically, and opens the CtrlP fuzzy finding window. Upon selection or cancellation, the proper callbacks are executed.
