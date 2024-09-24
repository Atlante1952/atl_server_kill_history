local HUD_BASE_Y = 0.65
local HUD_SPACING = 0.04
local MAX_HUDS = 6

local IMAGE_SUICIDE = "suicide.png"
local IMAGE_WIELDHAND = "wieldhand.png"
local IMAGE_SPI = "spi.png"

local function add_hud(player, type, position, text, scale, alignment, direction, offset)
    if not player or not player:is_player() then
        minetest.log("error", "Invalid player for HUD.")
        return nil
    end

    if not type or not position or not text then
        minetest.log("error", "Missing parameters for HUD creation.")
        return nil
    end

    return player:hud_add({
        hud_elem_type = type,
        position = position,
        offset = offset or { x = 0, y = 0 },
        text = text,
        alignment = alignment or { x = 1, y = 1 },
        scale = scale or { x = 100, y = 100 },
        number = 0xffffff,
        direction = direction or 0,
    })
end

local function update_hud_positions(player)
    local hud_ids = atl_server_kill_history.hud_ids[player] or {}
    for i, hud in ipairs(hud_ids) do
        local pos_y = HUD_BASE_Y + (i - 1) * HUD_SPACING

        local function change_position_and_offset(hud_element, pos_x, offset_x, pos_y_adjust)
            if hud_element then
                player:hud_change(hud_element, "position", { x = pos_x, y = pos_y + (pos_y_adjust or 0) })
                player:hud_change(hud_element, "offset", { x = offset_x, y = 0 })
            end
        end

        change_position_and_offset(hud.killer, 0.125, 10)
        change_position_and_offset(hud.item, 0.14, 0, -0.0075)
        change_position_and_offset(hud.killed, 0.17, -10)
    end
end

local function add_hud_entry(player_connected, killer, item_image, killed_text)
    if not player_connected or not player_connected:is_player() then
        return
    end

    local hud_entry = {
        killer = killer and add_hud(player_connected, "text", { x = 0.10, y = 0 }, killer, nil, { x = -1, y = 1 }, 0, { x = 10, y = 0 }),
        item = item_image and add_hud(player_connected, "image", { x = 0.14, y = 0 }, item_image, { x = 2, y = 2 }),
        killed = add_hud(player_connected, "text", { x = 0.18, y = 0 }, killed_text, nil, { x = 1, y = 1 }, 1, { x = -10, y = 0 })
    }

    table.insert(atl_server_kill_history.hud_ids[player_connected], 1, hud_entry)
    update_hud_positions(player_connected)
end

local function remove_oldest_hud(player_connected)
    if not player_connected or not player_connected:is_player() then
        return
    end

    local oldest_hud = table.remove(atl_server_kill_history.hud_ids[player_connected])
    if oldest_hud then
        for _, hud_element in pairs(oldest_hud) do
            if hud_element then
                player_connected:hud_remove(hud_element)
            end
        end
    end
end

local function broadcast_hud_entry(killer, item_image, killed_text)
    for _, player_connected in ipairs(minetest.get_connected_players()) do
        atl_server_kill_history.hud_ids[player_connected] = atl_server_kill_history.hud_ids[player_connected] or {}
        while #atl_server_kill_history.hud_ids[player_connected] >= MAX_HUDS do
            remove_oldest_hud(player_connected)
        end
        add_hud_entry(player_connected, killer, item_image, killed_text)
    end
end

local function get_kill_details(player, reason)
    local player_name = player:get_player_name()

    if reason and reason.type == "punch" then
        local attacker = reason.object
        if attacker and attacker:is_player() then
            local attacker_name = attacker:get_player_name()
            local wielded_item_name = attacker:get_wielded_item():get_name()

            local item_image = wielded_item_name == "" and IMAGE_WIELDHAND or IMAGE_SUICIDE
            if wielded_item_name ~= "" then
                local item_def = minetest.registered_items[wielded_item_name]
                if item_def then
                    item_image = item_def.tiles and type(item_def.tiles) == "table" and item_def.tiles[1] or item_def.inventory_image or item_image
                end
            end

            return attacker_name, item_image, player_name
        elseif attacker and attacker:get_luaentity() and attacker:get_luaentity().name == "spiradilus:spiradilus" then
            return nil, IMAGE_SPI, player_name .. " (Killed by Spiradilus)"
        end
    elseif reason and reason.type == "combat_log" then
        return nil, IMAGE_SUICIDE, player_name .. " (Killed - combat_logger)"
    elseif reason and reason.type == "drown" then
        return nil, "bubble.png", player_name .. " (Drowned)"
    end
    return nil, IMAGE_SUICIDE, player_name .. " (Suicide)"
end

local function is_dangerous_node(node_name)
    local node_def = minetest.registered_nodes[node_name]
    return node_def and node_def.damage_per_second ~= nil
end
local function get_node_texture(node_name)
    local texture_mapping = {
        ["default:water_source"] = "default_water.png",
        ["default:river_water_source"] = "default_river_water.png",
        ["default:lava_source"] = "default_lava.png",
        ["fire:permanent_flame"] = "fire_basic_flame.png",
        ["fire:basic_flame"] = "fire_basic_flame.png"
    }

    local texture = texture_mapping[node_name]
    if texture then
        return texture
    end

    local node_def = minetest.registered_nodes[node_name]
    if node_def and node_def.tiles then
        texture = node_def.tiles[1]
        if type(texture) == "table" then
            texture = texture.name or ""
        end
        return texture
    end

    return ""
end

function atl_server_kill_history.handle_death(player, reason)
    if not player or not player:is_player() or player:get_hp() ~= 0 then
        return
    end

    local attacker_name, item_image, killed_text = get_kill_details(player, reason)

    if attacker_name then
        broadcast_hud_entry(attacker_name, item_image, killed_text or player:get_player_name())
    else
        local player_name = player:get_player_name()
        local pos = player:get_pos()
        local node = minetest.get_node(pos)
        local node_name = node.name

        if node_name == "air" then
            broadcast_hud_entry(nil, IMAGE_SUICIDE, player_name .. " (Suicide)")
        elseif is_dangerous_node(node_name) then
            local node_texture = get_node_texture(node_name)
            broadcast_hud_entry(nil, node_texture, player_name .. " (Suicide)")
        else
            broadcast_hud_entry(nil, IMAGE_SUICIDE, player_name .. " (Suicide)")
        end
    end
end

minetest.register_on_dieplayer(function(player, reason)
    atl_server_kill_history.handle_death(player, reason)
end)

