# graft-git.nvim

An extension to [graft.nvim](https://github.com/tlj/graft.nvim) to handle automatic installation, removal and updates of plugins through git submodules.

## Installation

Add graft-git.nvim as a git submodule in your Neovim configuration:

```bash
:execute '!git -C ' .. stdpath('config') .. ' submodule add https://github.com/tlj/graft-git.nvim pack/vendor/start/graft-git.nvim'
```

## Usage

Basic setup in your init.lua:

```lua
-- Use graft tools to automatically 
require("graft-git").setup({ install_plugins = true, remove_plugins = true })

-- The defined plugin will be automatically added as a submodule by graft-git.nvim
require("graft").setup({ 
  now = {
    "catppuccin/nvim", 
    { name = "catppuccin", setup = function() vim.cmd("colorscheme catppuccin-mocha") end } }
  },
})
```
