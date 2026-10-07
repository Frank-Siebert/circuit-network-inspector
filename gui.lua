-- taken from https://github.com/JasonLandbridge/CircuitHUD-V2/


-- NOTE: This should remain local as it causes desync and save/load issues if moved elsewhere
local signal_id_type = {     -- https://lua-api.factorio.com/latest/concepts/SignalIDType.html
    virtual = 'virtual_signal',
    ['space-location'] = 'space_location',
    ['asteroid-chunk'] = 'asteroid_chunk',
}

local signalid_to_elemid = {
    item = 'item-with-quality',
    entity = 'entity-with-quality',
    recipe = 'recipe-with-quality',
    equipment = 'equipment-with-quality',
    ['item-with-quality'] = 'item-with-quality',
    ['entity-with-quality'] = 'entity-with-quality',
    ['recipe-with-quality'] = 'recipe-with-quality',
    ['equipment-with-quality'] = 'equipment-with-quality',
    ['space-location'] = 'space-location',
    ['asteroid-chunk'] = 'asteroid-chunk',
}

local const = {
    SIGNAL_TYPE_MAP = {
        ["virtual"] = "virtual-signal",
    }
}

function Button_Signal(signal)
    local signal_id_type = { -- https://lua-api.factorio.com/latest/concepts/SignalIDType.html
        virtual = 'virtual_signal',
        ['space-location'] = 'space_location',
        ['asteroid-chunk'] = 'asteroid_chunk',
    }

    local signalid_to_elemid = {
        item = 'item-with-quality',
        entity = 'entity-with-quality',
        recipe = 'recipe-with-quality',
        equipment = 'equipment-with-quality',
        ['item-with-quality'] = 'item-with-quality',
        ['entity-with-quality'] = 'entity-with-quality',
        ['recipe-with-quality'] = 'recipe-with-quality',
        ['equipment-with-quality'] = 'equipment-with-quality',
        ['space-location'] = 'space-location',
        ['asteroid-chunk'] = 'asteroid-chunk',
    }

    local network_styles = { "green_circuit_network_content_slot", "red_circuit_network_content_slot" }
    local signal_type = signal.signal.type or 'item'
    local signal_name = signal.signal.name
    local type = const.SIGNAL_TYPE_MAP[signal_type] or signal_type

    local prototype_name = signal_id_type[signal_type] and signal_id_type[signal_type] or signal_type

    ---@type LuaGuiElement.add_param
    local button = {
        type = "sprite-button",
        sprite = type .. "/" .. signal_name,
        number = signal.count,
        style = network_styles[i],
        tooltip = prototypes[prototype_name][signal_name].localised_name,
        quality = signal.signal.quality,
    }

    local gui_quality
    if signalid_to_elemid[signal_type] then
        button.elem_tooltip = {
            type = signalid_to_elemid[signal_type],
            name = signal_name,
            quality = signal.signal.quality,
        }
    else
        button.elem_tooltip = {
            type = 'signal',
            signal_type = signal_type,
            name = signal_name,
        }
    end

    return button
end
