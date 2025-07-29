local M = {}
local api, fn = vim.api, vim.fn
local config = {
    -- Whether to replace netrw
    replace_netrw = true,
    -- Whether to create key mapping for ESC quitting lf
    escape_quit = true,
    -- Selection file path
    selection_file = fn.stdpath("cache") .. "/lf_selection"
}
local state = {
    buffers_before = {},
    original_win = nil,
    original_buf = nil,
    buf_id = nil
}
local get_file_buffers, cleanup_deleted_buffers, open_selected_files, close_lf, setup_mappings, setup_netrw_replacement
get_file_buffers = function()
    local bufs = {}
    for _, b in ipairs(api.nvim_list_bufs()) do
        if fn.buflisted(b) == 1 then
            local n = fn.bufname(b)
            if n ~= "" and fn.filereadable(n) == 1 then
                table.insert(bufs, n)
            end
        end
    end
    return bufs
end
cleanup_deleted_buffers = function(bufs)
    for _, n in ipairs(bufs) do
        if fn.filereadable(n) ~= 1 then
            local nr = fn.bufnr(n)
            if nr ~= -1 then
                pcall(api.nvim_buf_delete, nr, {
                    force = true
                })
            end
        end
    end
end
open_selected_files = function()
    if fn.filereadable(config.selection_file) ~= 1 then
        return
    end
    local files = fn.readfile(config.selection_file)
    for _, f in ipairs(files) do
        if fn.isdirectory(f) == 1 then
            M.open(f)
            break
        else
            vim.cmd("edit " .. fn.fnameescape(f))
        end
    end
    fn.delete(config.selection_file)
end
close_lf = function()
    if state.original_win and api.nvim_win_is_valid(state.original_win) and state.original_buf and
        api.nvim_buf_is_valid(state.original_buf) then
        api.nvim_win_set_buf(state.original_win, state.original_buf)
    end
    if state.buf_id and api.nvim_buf_is_valid(state.buf_id) then
        api.nvim_buf_delete(state.buf_id, {
            force = true
        })
    end
    open_selected_files()
    cleanup_deleted_buffers(state.buffers_before)
    state.original_win, state.original_buf, state.buf_id, state.buffers_before = nil, nil, nil, {}
end
setup_mappings = function(buf_id)
    local opts = {
        buffer = buf_id,
        noremap = true,
        silent = true
    }
    if config.escape_quit then
        vim.keymap.set("n", "<Esc>", close_lf, opts)
    end
    vim.keymap.set("t", "q", function()
        api.nvim_feedkeys("q", "t", false)
    end, opts)
end
function M.open(path)
    if fn.executable("lf") ~= 1 then
        vim.notify("lf command not found. Please install lf.", vim.log.levels.ERROR)
        return
    end
    fn.delete(config.selection_file)
    state.original_win = api.nvim_get_current_win()
    state.original_buf = api.nvim_win_get_buf(state.original_win)
    state.buffers_before = get_file_buffers()
    local start_dir = path or fn.getcwd()
    if fn.isdirectory(start_dir) ~= 1 then
        start_dir = fn.fnamemodify(start_dir, ":h")
    end
    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(state.original_win, buf_id)
    state.buf_id = buf_id
    api.nvim_set_option_value("filetype", "lf", {
        buf = buf_id
    })
    local cmd = string.format("lf -selection-path='%s' '%s'", config.selection_file, start_dir)
    local term_buf = fn.jobstart(cmd, {
        on_exit = function()
            vim.schedule(close_lf)
        end,
        term = true
    })
    if term_buf == 0 then
        vim.notify("Failed to start lf", vim.log.levels.ERROR)
        close_lf()
        return
    end
    setup_mappings(buf_id)
    vim.cmd("startinsert")
end
setup_netrw_replacement = function()
    if not config.replace_netrw then
        return
    end
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    local group = api.nvim_create_augroup("LfSimple", {
        clear = true
    })
    api.nvim_create_autocmd({"BufEnter", "BufNewFile"}, {
        group = group,
        callback = function()
            local buf_name = api.nvim_buf_get_name(0)
            if buf_name ~= "" and fn.isdirectory(buf_name) == 1 then
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
function M.setup(opts)
    if opts then
        config = vim.tbl_deep_extend("force", config, opts)
    end
    api.nvim_create_user_command("Lf", function(args)
        M.open(args.args ~= "" and args.args or nil)
    end, {
        nargs = "?",
        complete = "dir",
        desc = "Open lf file manager"
    })
    setup_netrw_replacement()
end
return M
