-- Auto-setup for the plugin
if vim.g.loaded_lf then
    return
end
vim.g.loaded_lf = 1

-- Setup with default configuration if not already done
if not package.loaded['lf-simple'] then
    require('lf-simple').setup()
end
