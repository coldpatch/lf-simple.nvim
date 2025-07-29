local M = {}

local api = vim.api
local fn = vim.fn

-- Plugin configuration
local config = {
  -- Whether to replace netrw
  replace_netrw = true,
  -- Whether to create key mapping for ESC quitting lf
  escape_quit = true,
  -- Selection file path
  selection_file = fn.stdpath("cache") .. "/lf_selection"
}

-- Internal state
local state = {
  buffers_before = {},
  original_win = nil,
  original_buf = nil,
  buf_id = nil
}

---Get list of currently open file buffers
---@return table<string>
local function get_file_buffers()
  local buffers = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if fn.buflisted(buf) == 1 then
      local buf_name = fn.bufname(buf)
      if buf_name ~= "" and fn.filereadable(buf_name) == 1 then
        table.insert(buffers, buf_name)
      end
    end
  end
  return buffers
end

---Close buffers that no longer point to existing files
---@param buffers_before table<string>
local function cleanup_deleted_buffers(buffers_before)
  for _, buf_name in ipairs(buffers_before) do
    if fn.filereadable(buf_name) ~= 1 then
      local buf_nr = fn.bufnr(buf_name)
      if buf_nr ~= -1 then
        pcall(api.nvim_buf_delete, buf_nr, {
          force = true
        })
      end
    end
  end
end

---Open selected files from lf
local function open_selected_files()
  if fn.filereadable(config.selection_file) ~= 1 then
    return
  end

  local files = fn.readfile(config.selection_file)
  for _, file in ipairs(files) do
    if fn.isdirectory(file) == 1 then
      -- If it's a directory, open lf again in that directory
      M.open(file)
      break
    else
      -- Open the file
      vim.cmd("edit " .. fn.fnameescape(file))
    end
  end

  -- Clean up selection file
  fn.delete(config.selection_file)
end

---Close the lf buffer and handle cleanup
local function close_lf()
  -- Restore original buffer to window
  if state.original_win and api.nvim_win_is_valid(state.original_win) and state.original_buf and
      api.nvim_buf_is_valid(state.original_buf) then
    api.nvim_win_set_buf(state.original_win, state.original_buf)
  end

  -- Delete the lf buffer
  if state.buf_id and api.nvim_buf_is_valid(state.buf_id) then
    api.nvim_buf_delete(state.buf_id, {
      force = true
    })
  end

  -- Process selected files
  open_selected_files()

  -- Clean up deleted file buffers
  cleanup_deleted_buffers(state.buffers_before)

  -- Reset state
  state.original_win = nil
  state.original_buf = nil
  state.buf_id = nil
  state.buffers_before = {}
end

---Setup key mappings for the lf buffer
---@param buf_id number
local function setup_mappings(buf_id)
  local opts = {
    buffer = buf_id,
    noremap = true,
    silent = true
  }

  -- Quit lf
  if config.escape_quit then
    vim.keymap.set("n", "<Esc>", close_lf, opts)
  end
  vim.keymap.set("t", "q", function()
    -- Send 'q' to lf to quit
    api.nvim_feedkeys("q", "t", false)
  end, opts)
end

---Open lf file manager
---@param path? string Optional path to open lf in
function M.open(path)
  -- Check if lf is available
  if fn.executable("lf") ~= 1 then
    vim.notify("lf command not found. Please install lf.", vim.log.levels.ERROR)
    return
  end

  -- Clean up any existing selection file
  fn.delete(config.selection_file)

  -- Store current state
  state.original_win = api.nvim_get_current_win()
  state.original_buf = api.nvim_win_get_buf(state.original_win)
  state.buffers_before = get_file_buffers()

  -- Determine starting directory
  local start_dir = path or fn.getcwd()
  if fn.isdirectory(start_dir) ~= 1 then
    start_dir = fn.fnamemodify(start_dir, ":h")
  end

  -- Create new buffer for lf
  local buf_id = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(state.original_win, buf_id)
  state.buf_id = buf_id

  -- Set buffer options
  api.nvim_set_option_value("filetype", "lf", {
    buf = buf_id
  })

  -- Build lf command
  local cmd = string.format("lf -selection-path='%s' '%s'", config.selection_file, start_dir)

  -- Setup terminal
  local term_buf = fn.jobstart(cmd, {
    on_exit = function(_, _, _)
      vim.schedule(close_lf)
    end,
    term = true
  })

  if term_buf == 0 then
    vim.notify("Failed to start lf", vim.log.levels.ERROR)
    close_lf()
    return
  end

  -- Setup key mappings
  setup_mappings(buf_id)

  -- Enter insert mode to interact with lf
  vim.cmd("startinsert")
end

---Setup autocmd to replace netrw if configured
local function setup_netrw_replacement()
  if not config.replace_netrw then
    return
  end

  -- Disable netrw
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

  local group = api.nvim_create_augroup("LfSimple", {
    clear = true
  })

  -- Replace netrw when opening directories
  api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
    group = group,
    callback = function()
      local buf_name = api.nvim_buf_get_name(0)
      if buf_name ~= "" and fn.isdirectory(buf_name) == 1 then
        -- Delete the directory buffer and open lf
        vim.schedule(function()
          api.nvim_buf_delete(0, {
            force = true
          })
          M.open(buf_name)
        end)
      end
    end
  })
end

---Setup the plugin
---@param opts? table Configuration options
function M.setup(opts)
  -- Merge user config
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end

  -- Create user command
  api.nvim_create_user_command("Lf", function(args)
    M.open(args.args ~= "" and args.args or nil)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Open lf file manager"
  })

  -- Setup netrw replacement if enabled
  setup_netrw_replacement()
end

return M
