local HUD_BASE_Y = 0.65
local HUD_SPACING = 0.04
local MAX_HUDS = 6

local IMAGE_SUICIDE = "suicide.png"
local IMAGE_WIELDHAND = "wieldhand.png"
local IMAGE_SPI = "spi.png"

local connected_players = minetest.get_connected_players

local function validate_player(player)
    if player and player:is_player() then
        return true
    end
    minetest.log("error", "Invalid player object.")
    return false
end

local function add_hud(player, type, position, text, scale, alignment, direction, offset)
    if not validate_player(player) or not type or not position or not text then
        minetest.log("error", "Missing essential HUD parameters.")
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
    local base_y = HUD_BASE_Y
    local spacing = HUD_SPACING

    for i, hud in ipairs(hud_ids) do
        local pos_y = base_y + (i - 1) * spacing

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

local function add_hud_entry(player, killer, item_image, killed_text)
    if not validate_player(player) then return end

    local hud_entry = {
        killer = killer and add_hud(player, "text", { x = 0.10, y = 0 }, killer, nil, { x = -1, y = 1 }, 0, { x = 10, y = 0 }),
        item = item_image and add_hud(player, "image", { x = 0.14, y = 0 }, item_image, { x = 2, y = 2 }),
        killed = add_hud(player, "text", { x = 0.18, y = 0 }, killed_text, nil, { x = 1, y = 1 }, 1, { x = -10, y = 0 })
    }

    table.insert(atl_server_kill_history.hud_ids[player], 1, hud_entry)
    update_hud_positions(player)
end

local function remove_oldest_hud(player)
    if not validate_player(player) then return end

    local oldest_hud = table.remove(atl_server_kill_history.hud_ids[player])
    if oldest_hud then
        for _, hud_element in pairs(oldest_hud) do
            if hud_element then
                player:hud_remove(hud_element)
            end
        end
    end
end

local function broadcast_hud_entry(killer, item_image, killed_text)
    local players = connected_players()
    for _, player in ipairs(players) do
        atl_server_kill_history.hud_ids[player] = atl_server_kill_history.hud_ids[player] or {}

        while #atl_server_kill_history.hud_ids[player] >= MAX_HUDS do
            remove_oldest_hud(player)
        end

        add_hud_entry(player, killer, item_image, killed_text)
    end
end

local texture_mapping = {
    ["default:water_source"] = "default_water.png",
    ["default:river_water_source"] = "default_river_water.png",
    ["default:lava_source"] = "default_lava.png",
    ["fire:permanent_flame"] = "fire_basic_flame.png",
    ["fire:basic_flame"] = "fire_basic_flame.png"
}

local function get_node_texture(node_name)
    return texture_mapping[node_name] or (minetest.registered_nodes[node_name] and minetest.registered_nodes[node_name].tiles and minetest.registered_nodes[node_name].tiles[1]) or ""
end

local function get_kill_details(player, reason)
    local player_name = player:get_player_name()

    if reason and reason.type == "punch" then
        local attacker = reason.object
        if attacker and attacker:is_player() then
            local attacker_name = attacker:get_player_name()
            local wielded_item = attacker:get_wielded_item():get_name()

            local item_image = texture_mapping[wielded_item]
                or (minetest.registered_items[wielded_item]
                    and minetest.registered_items[wielded_item].tiles
                    and minetest.registered_items[wielded_item].tiles[1]
                    or minetest.registered_items[wielded_item].inventory_image
                    or IMAGE_WIELDHAND)
                or IMAGE_WIELDHAND

            return attacker_name, item_image, player_name
        elseif attacker and attacker:get_luaentity() and attacker:get_luaentity().name == "spiradilus:spiradilus" then
            return nil, IMAGE_SPI, player_name .. " (Killed by Spiradilus)"
        end
    elseif reason and reason.type == "combat_log" then
        return nil, IMAGE_SUICIDE, player_name .. " (Killed - combat logger)"
    elseif reason and reason.type == "drown" then
        return nil, "bubble.png", player_name .. " (Drowned)"
    end

    return nil, IMAGE_SUICIDE, player_name .. " (Suicide)"
end

local function is_dangerous_node(node_name)
    local node_def = minetest.registered_nodes[node_name]
    return node_def and node_def.damage_per_second ~= nil
end

function atl_server_kill_history.handle_death(player, reason)
    if not validate_player(player) or player:get_hp() ~= 0 then
        return
    end

    local attacker_name, item_image, killed_text = get_kill_details(player, reason)

    if attacker_name then
        broadcast_hud_entry(attacker_name, item_image, killed_text)
    else
        local player_name = player:get_player_name()
        local pos = player:get_pos()
        local node_name = minetest.get_node(pos).name

        if node_name == "air" or not is_dangerous_node(node_name) then
            broadcast_hud_entry(nil, IMAGE_SUICIDE, player_name .. " (Suicide)")
        else
            broadcast_hud_entry(nil, get_node_texture(node_name), player_name .. " (Suicide)")
        end
    end
end

minetest.register_on_dieplayer(function(player, reason)
    atl_server_kill_history.handle_death(player, reason)
end)
