local vim = vim
local api = vim.api
local uv = vim.loop

local dirpath = debug.getinfo(1, 'S').source:match("@(.*/)")
assert(dirpath, "Unable to get source path!")

local function is_loaded()
    return vim.lsp._no_wait_ ~= nil
end

local function check()
    if not is_loaded() then
        api.nvim_err_writeln("lsp-nowait.nvim: patched file is not loaded!") 
    end
end

local function clear()
    uv.fs_unlink(dirpath .. 'vim/lsp.lua')
end

local function readFileSync(path)
    local fd = assert(uv.fs_open(path, "r", 438))
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size, 0))
    assert(uv.fs_close(fd))
    return data
end

local function writeFileSync(path, data)
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, data))
    assert(uv.fs_close(fd))
end

local function patch()
    local patched = dirpath .. 'vim/lsp.lua'
    uv.fs_unlink(patched)

    local origfile = api.nvim_get_runtime_file('lua/vim/lsp.lua', false)[1]
    local data = readFileSync(origfile)
    local matches = 0
 
    -- patch: lsp._no_wait_ variable
    data, matches = data:gsub('(\nreturn.-\n)', '\nlsp._no_wait_ = true%1')
    assert(matches == 1, "patch failed!")

    -- patch: no_wait flag
    data, matches = data:gsub('(\n(%s+)before_init)',
        '\n%2no_wait         = { config.no_wait, "b", true };%1')
    assert(matches == 1, "patch failed!")

    -- patch: pid_list
    data, matches = data:gsub('(\n%s+if tbl_isempty%(active_clients%) then.-end\n)(.-client.stop%(%).-end\n)',
    '%1\n' .. [[
  local pid_list = {}
  for client_id, client in pairs(active_clients) do
    if client.config.no_wait then
      pid_list[#pid_list + 1] = client.rpc.handle:get_pid() 
      active_clients[client_id] = nil
    end
  end]] .. '\n\n%2' .. [[
  require'lspNW'._call_exit(pid_list)
]])
    assert(matches == 1, "patch failed!")

    writeFileSync(patched, data)
end

local function _call_exit(pid_list)
    if #pid_list > 0 then
        uv.spawn(vim.v.progpath, {
            args = {
                '--headless',
                '--clean',
                '+luafile bin/lspkill.lua',
                string.format('+lua lspkill(%s)', vim.inspect(pid_list)),
                '+q'
            },
            detached = true,
            cwd = dirpath .. '../'
        })
    end
end

return {
    is_loaded = is_loaded,
    check = check,
    clear = clear,
    patch = patch,
    _call_exit = _call_exit
}
