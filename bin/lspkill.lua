local uv = vim.loop

function lspkill(pid_list) 
    uv.sleep(500)
    for _, pid in pairs(pid_list) do
        uv.kill(pid, 15)
    end
end
