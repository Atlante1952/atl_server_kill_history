atl_server_kill_history = {}
atl_server_kill_history.modpath = minetest.get_modpath("atl_server_kill_history")
atl_server_kill_history.max_huds = 6
atl_server_kill_history.hud_ids = {}

function atl_server_kill_history.load_file(path)
    local status, err = pcall(dofile, path)
    if not status then
        minetest.log("error", "-!- Failed to load file: " .. path .. " - Error: " .. err)
    else
        minetest.log("action", "-!- Successfully loaded file: " .. path)
    end
end

if atl_server_kill_history.modpath then
    local files_to_load = {
        "script/api.lua",
    }

    for _, file in ipairs(files_to_load) do
        atl_server_kill_history.load_file(atl_server_kill_history.modpath .. "/" .. file)
    end
else
    minetest.log("error", "-!- Files in " .. atl_server_kill_history.modpath .. " mod are not set or valid.")
end
