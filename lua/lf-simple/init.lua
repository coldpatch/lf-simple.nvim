local M = {}

local api = vim.api
local fn = vim.fn

-- Plugin configuration
local config = {
  -- Window options for floating window
  window = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
  },
  -- Whether to replace netrw
  replace_netrw = false,
  -- Selection file path
  selection_file = vim.fn.stdpath("cache") .. "/lf_selection",
}

-- Internal state
local state = {
  buffers_before = {},
  win_id = nil,
  buf_id = nil,
  original_win = nil,
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
        pcall(api.nvim_buf_delete, buf_nr, { force = true })
      end
    end
  end
end

---Calculate window dimensions for floating window
---@return table
local function get_window_config()
  local width = math.floor(vim.o.columns * config.window.width)
  local height = math.floor(vim.o.lines * config.window.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = config.window.border,
    style = "minimal",
  }
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

---Close the lf window and handle cleanup
local function close_lf()
  if state.win_id and api.nvim_win_is_valid(state.win_id) then
    api.nvim_win_close(state.win_id, true)
  end

  if state.buf_id and api.nvim_buf_is_valid(state.buf_id) then
    api.nvim_buf_delete(state.buf_id, { force = true })
  end

  -- Return to original window
  if state.original_win and api.nvim_win_is_valid(state.original_win) then
    api.nvim_set_current_win(state.original_win)
  end

  -- Process selected files
  open_selected_files()

  -- Clean up deleted file buffers
  cleanup_deleted_buffers(state.buffers_before)

  -- Reset state
  state.win_id = nil
  state.buf_id = nil
  state.original_win = nil
  state.buffers_before = {}
end

---Setup key mappings for the lf buffer
---@param buf_id number
local function setup_mappings(buf_id)
  local opts = { buffer = buf_id, noremap = true, silent = true }

  -- Quit lf
  vim.keymap.set("t", "<Esc>", close_lf, opts)
  vim.keymap.set("t", "q", function()
    -- Send 'q' to lf to quit
    vim.api.nvim_feedkeys("q", "t", false)
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

  -- Store current state
  state.original_win = api.nvim_get_current_win()
  state.buffers_before = get_file_buffers()

  -- Determine starting directory
  local start_dir = path or fn.getcwd()
  if fn.isdirectory(start_dir) ~= 1 then
    start_dir = fn.fnamemodify(start_dir, ":h")
  end

  -- Create floating window
  local buf_id = api.nvim_create_buf(false, true)
  local win_config = get_window_config()
  local win_id = api.nvim_open_win(buf_id, true, win_config)

  -- Store window and buffer IDs
  state.win_id = win_id
  state.buf_id = buf_id

  -- Set buffer options
  api.set_option_value("filetype", "lf", { buf = buf_id })
  api.set_option_value("winhl", "Normal:Normal", { win = win_id })

  -- Build lf command
  local cmd = string.format(
    "lf -selection-path='%s' '%s'",
    config.selection_file,
    start_dir
  )

  -- Setup terminal job
  local job_id = fn.startjob(cmd, {
    on_exit = function(_, _, _)
      vim.schedule(function()
        close_lf()
      end)
    end,
    term = true,
  })

  -- local job_id = fn.termopen(cmd, {
  --   on_exit = function(_, exit_code, _)
  --     vim.schedule(function()
  --       close_lf()
  --     end)
  --   end,
  -- })

  if job_id <= 0 then
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

  local group = api.nvim_create_augroup("LfSimple", { clear = true })

  -- Replace netrw when opening directories
  api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
    group = group,
    callback = function()
      local buf_name = api.nvim_buf_get_name(0)
      if buf_name ~= "" and fn.isdirectory(buf_name) == 1 then
        -- Delete the directory buffer and open lf
        vim.schedule(function()
          api.nvim_buf_delete(0, { force = true })
          M.open(buf_name)
        end)
      end
    end,
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
    desc = "Open lf file manager",
  })

  -- Setup netrw replacement if enabled
  setup_netrw_replacement()
end

return M
