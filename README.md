# lf-simple.nvim

A lightweight Neovim plugin for the [lf](https://github.com/gokcehan/lf) file manager with automatic buffer cleanup.

<!-- TODO: add some sort of gif/image preview -->

## Installation

### Using neovim's built in package manager

```lua
vim.pack.add({
  "https://github.com/coldpatch/lf-simple.nvim",
})

require("lf-simple").setup({})
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "ashaibani/lf-simple.nvim",
    config = function()
        require("lf-simple").setup({
            -- Optional configuration
        })
    end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "ashaibani/lf-simple.nvim",
    config = function()
        require("lf-simple").setup()
    end
}
```

## Requirements

- Neovim >= 0.7.0
- [lf](https://github.com/gokcehan/lf) file manager

## Configuration

```lua
require("lf-simple").setup({
    -- Window configuration
    window = {
        width = 0.8,   -- 80% of screen width
        height = 0.8,  -- 80% of screen height
        border = "rounded", -- Border style: "single", "double", "rounded", "solid", "shadow"
    },

    -- Replace netrw with lf (default: true)
    replace_netrw = true,

    -- Custom selection file path (optional)
    selection_file = vim.fn.stdpath("cache") .. "/lf_selection",
})
```

## Usage

### Commands

- `:Lf` - Open lf in the current working directory
- `:Lf /path/to/directory` - Open lf in a specific directory

### Lua API

```lua
-- Open lf in current directory
require("lf-simple").open()

-- Open lf in specific directory
require("lf-simple").open("/path/to/directory")
```

### Key Mappings

You can create custom key mappings:

```lua
-- Basic mapping
vim.keymap.set("n", "<leader>lf", "<cmd>Lf<cr>", { desc = "Open lf" })

-- Open lf in current file's directory
vim.keymap.set("n", "<leader>ld", function()
    require("lf-simple").open(vim.fn.expand("%:p:h"))
end, { desc = "Open lf in current directory" })
```

### Inside lf

- `<Esc>` - Close lf and return to Neovim
- `q` - Quit lf (standard lf keybinding)
- Select files normally in lf - they will be opened in Neovim when you quit

## Buffer Management

This plugin automatically tracks file buffers before opening lf and cleans up any directory buffers that were created during the lf session. This prevents the common issue of having lingering directory buffers after using a file manager.

### How it works:

1. **Before opening lf**: Records all currently open file buffers
2. **During lf session**: lf can navigate and open files normally
3. **After closing lf**:
   - Opens any files selected in lf
   - Closes directory buffers that no longer point to existing files
   - Returns focus to the original window
