require("tables")
require("gui")

local MOD = "circuit-network-inspector"
local GUI = "cni_frame"
local BUTTON = "cni_button"
local unit_number_to_entity = {}

local function destroy_relative(player)
  local e = player.gui.relative[BUTTON]
  if e and e.valid then e.destroy() end
end

local function circuit_networks(entity)
  local result = {}
  if not (entity and entity.valid) then return result end

  local connectors = entity.get_wire_connectors(false)
  for id, connector in pairs(connectors) do
    if connector.valid and connector.network_id and connector.network_id ~= 0 then
      local network = entity.get_circuit_network(id)
      if network and network.valid then
        local key = tostring(network.network_id) .. ":" .. tostring(network.wire_type)
        if not result[key] then
          result[key] = {
            id = network.network_id,
            wire_type = network.wire_type,
            network = network
          }
        end
      end
    end
  end

  return result
end

local function network_from_state(state)
  local source = unit_number_to_entity[ state.source_unit_number]
  if not source or not source.valid then return nil end
  return circuit_networks(source)[tostring(tostring(state.network_id) .. ":" .. tostring(state.wire_type))]
end

local function signal_key(signal)
  if not signal then return nil end
  return (signal.type or "item") .. ":" .. tostring(signal.name) .. " q=" .. tostring(signal.quality or "normal")
end

local function same_signal(a, b)
  return signal_key(a) == signal_key(b)
end

local function signal_text(signal)
  if not signal then return "?" end
  local t = signal.type or "item"
  local prefix
  if t == "item" then
    prefix = "[img=item/" .. signal.name .. "]"
  elseif t == "fluid" then
    prefix = "[img=fluid/" .. signal.name .. "]"
  elseif t == "virtual" then
    prefix = "[img=virtual-signal/" .. signal.name .. "]"
  else
    prefix = signal.name
  end
  return prefix .. " " .. signal.name
end

local function add_signal(refs, signal)
  if signal then refs[signal_key(signal)] = true end
end

local function add_condition_signals(refs, condition)
  if not condition then return end
  add_signal(refs, condition.first_signal)
  add_signal(refs, condition.second_signal)
end

local function network_selected(selection, wire_type)
  if not selection then return true end
  if wire_type == defines.wire_type.red then
    return selection.red ~= false
  end
  if wire_type == defines.wire_type.green then
    return selection.green ~= false
  end
  return true
end

--- Finds a LuaCircuitNetwork by ID when the surface is unknown
-- @param network_id number
-- @return LuaCircuitNetwork|nil
local function find_circuit_network_anywhere(network_id)
    for _, surface in pairs(game.surfaces) do
        local manager = surface.circuit_network_manager
        if manager then
            local network = manager.get_network(network_id)
            if network and network.valid then
                return network
            end
        end
    end
    return nil
end

local function signal_to_rich_text(signalID)
    if not signalID then
        return nil
    end
    local type = signalID.type
    if not type then type = "item"
    elseif type == "virtual" then type = "virtual-signal" end

    return string.format(
        "[%s=%s,quality=%s]",
        type,
        signalID.name,
        signalID.quality
    )
end

--[[
behavior_access = {
  currentWriteContribution :: table from SignalID to value
  dynamicPotentials :: {
     description:: text,
     directAccess :: array SignalID?,
     matches :: function (SignalID) to boolean
  }
  text :: rich text
  access :: enum { write, read } --
}
]]

local function behavior_accesses(entity, behavior, wire_type)
  local result = {}

  local function add_access(text, currentwrite, potentials)
    table.insert(result,
  {
    text = text,
    currentwrite = currentwrite, -- nil: it is a read. might be empty list or more for writes
    dynamic_potentials = potentials,
  })
  end

  local function add_set(text, signal, value)
    local write_contribution= {}
    write_contribution[signal] = value -- todo index
      add_access(text .. signal_to_rich_text(signal) .. " = " .. value,
         write_contribution,
        {
          description = "set a value",
          direct_access = { signal },
          matches = function (s) return same_signal(s, signal) end
        })
  end

  local function add_simple_read(text, signal)
    add_access(text, nil,
        {
          description = "read a value",
          direct_access = { signal },
          matches = function (s) return same_signal(s, signal) end
        })

  end

  local function add_comparison(text, circuit_condition)
      add_access(text .. signal_to_rich_text(circuit_condition.first_signal)
                              .. circuit_condition.comparator
                              .. (signal_to_rich_text(circuit_condition.second_signal) or circuit_condition.constant),
                              nil,
                      {
      description = "control comparison",
      direct_access = {circuit_condition.first_signal, circuit_condition.second_signal},
      matches = function (signal) return same_signal(signal, circuit_condition.first_signal) or (circuit_condition.second_signal and same_signal(circuit_condition.second_signal,signal)) end
                      })
  end

  if not behavior then return result end

  local input_ok = network_selected(behavior.input_networks, wire_type)
  local output_ok = network_selected(behavior.output_networks, wire_type)

  local has_circuit_enable_disable, value = pcall(function() return behavior["circuit_enable_disable"] end)
  if has_circuit_enable_disable and
     input_ok and behavior.circuit_enable_disable and behavior.circuit_condition then
      add_comparison("Enable if ", behavior.circuit_condition)
  end

  local t = behavior.type
  if t == defines.control_behavior.type.arithmetic_combinator then
    local p = behavior.parameters
    if p then
      add_access((signal_to_rich_text(p.first_signal) or p.first_constant)
               .. p.operation ..
                 (signal_to_rich_text(p.second_signal) or p.second_constant), nil,
                {
      description = "arithmetic operation",
      direct_access = { p.first_signal, p.second_signal},
      matches = function (signal) return (p.first_signal and same_signal(signal, p.first_signal)) or (p.second_signal and same_signal(p.second_signal,signal)) end
                      })

      -- if output_ok then add_write(p.output_signal) end
      add_set("result", p.output_signal, "behavior.signals_last_tick") -- TODO. add_set for single signal only, might be many?
--      add_set("result", p.output_signal, behavior.signals_last_tick) -- TODO. add_set for single signal only, might be many?
    end

  elseif t == defines.control_behavior.type.decider_combinator then
    local p = behavior.parameters
    if p then
      if input_ok then
        for i, c in pairs(p.conditions or {}) do
          add_access(((i > 1 and c.compare_type) or "first condition")
                  .. (signal_to_rich_text(c.first_signal))
                  .. c.comparator
                  .. (signal_to_rich_text(c.second_signal) or c.constant), nil,
                    {
            description = "comparation",
            direct_access = { c.first_signal, c.second_signal},
            matches = function (signal) return (same_signal(signal, c.first_signal)) or (c.second_signal and same_signal(c.second_signal,signal)) end
                          })

        end
      end
      if output_ok then
        for _, o in pairs(p.outputs      or {}) do add_set("output ", o.signal,(o.copy_count_from_input and "input") or o.constant or "1") end -- TODO it ain't 42
        for _, o in pairs(p.else_outputs or {}) do add_set("else "  , o.signal,(o.copy_count_from_input and "input") or o.constant or "1") end -- "defaults to 1"
      end
    end

  elseif t == defines.control_behavior.type.container
      or t == defines.control_behavior.type.logistic_container
      or t == defines.control_behavior.type.proxy_container then
    if output_ok and behavior.read_contents then
      -- Dynamic contents: actual signals are determined from the inventory.
      local inventory = entity.get_inventory(defines.inventory.chest)
      local write_contrib = {}
      if inventory then
        for _, item in pairs(inventory.get_contents()) do
          table.insert(write_contrib,{signalID = {type="item", name=item.name}, count = item.count})
        end
      end
      add_access("read contents " --[[ TODO items]], write_contrib, {
        description ="any item",
        direct_access = nil,
        matches = function (signal) return not signal.type or signal.type == "item" end
      })
    end
    if t == defines.control_behavior.type.logistic_container then
      if input_ok then
        --add_read("__dynamic")
      end
      -- TODO set requests
    end

  elseif t == defines.control_behavior.type.single_fluid_box then
    if (output_ok and behavior.read_temperature) then
      add_set("set temperature ", behavior.temperature_signal, entity.get_fluid(1).temperature)
    end
    if (output_ok and behavior.circuit_exclusive_mode_of_operation) then -- TODO operation is an enum
      add_access("read fluid, currently " .. string.format("[fluid=%s]",(entity.get_fluid(1).name)),{},
    {
      description = "any fluid",
      direct_access = {  }, -- TODO set to currently read
      matches = function (signal) return signal.type == "fluid" end
    })
    end
  elseif t == defines.control_behavior.type.inserter then
    if input_ok and behavior.circuit_set_stack_size then
      add_simple_read("set stack size ", behavior.circuit_stack_control_signal)
    end
    if output_ok and behavior.circuit_read_hand_contents then
      -- Dynamic: the hand contents are not represented by a fixed signal.
      -- We add the current hand item, when available.
      local hand = entity.held_stack
      local currentwrite = {}
      if hand and hand.valid_for_read then
        --add_write({type="item", name=hand.name})
        table.insert(currentwrite,{{type="item", name=hand.name},hand.count})
      end
      add_access("read hand contents ",currentwrite,
    {
      description = "any item",
      direct_access = nil,
      matches = function (signal) return not signal.type or signal.type == "item" end
    })
    end


  end
  return result
end

-- Returns the signals explicitly accessed by a behavior.
-- This is intentionally small: the first version covers the common
-- generic conditions, combinators, containers, accumulators, inserters,
-- rail signals, reactors and train stops.
local function behavior_signals(entity, behavior, wire_type)
  local reads = {}
  local writes = {}

  if not behavior then return reads, writes end

  local input_ok = network_selected(behavior.input_networks, wire_type)
  local output_ok = network_selected(behavior.output_networks, wire_type)

  local function add_read(signal, selection)
    if signal and network_selected(selection, wire_type) then
      add_signal(reads, signal)
    end
  end

  local function add_write(signal)
    if signal then add_signal(writes, signal) end
  end

  -- Generic on/off behavior.

  local has_circuit_enable_disable, value = pcall(function() return behavior["circuit_enable_disable"] end)
  if has_circuit_enable_disable and
     input_ok and behavior.circuit_enable_disable and behavior.circuit_condition then
    add_read(behavior.circuit_condition.first_signal)
    add_read(behavior.circuit_condition.second_signal)
  end

  local t = behavior.type

  if t == defines.control_behavior.type.arithmetic_combinator then
    local p = behavior.parameters
    if p then
      add_read(p.first_signal, p.first_signal_networks)
      add_read(p.second_signal, p.second_signal_networks)
      if output_ok then add_write(p.output_signal) end
    end

  elseif t == defines.control_behavior.type.decider_combinator then
    local p = behavior.parameters
    if p then
      if input_ok then
        for _, c in pairs(p.conditions or {}) do
          add_read(c.first_signal, c.first_signal_networks)
          add_read(c.second_signal, c.second_signal_networks)
        end
      end
      if output_ok then
        for _, o in pairs(p.outputs or {}) do add_write(o.signal) end
        for _, o in pairs(p.else_outputs or {}) do add_write(o.signal) end
      end
    end

  elseif t == defines.control_behavior.type.selector_combinator then
    local p = behavior.parameters
    if p and input_ok then
      add_read(p.index_signal)
      add_read(p.count_signal)
      add_read(p.select_quality_from_signal and p.quality_source_signal or nil)
      add_read(p.game_tick_signal)
      add_read(p.day_tick_signal)
      add_read(p.day_length_signal)
    end
    if p and output_ok then
      add_write(p.count_signal)
      add_write(p.quality_destination_signal)
      add_write(p.game_tick_signal)
      add_write(p.day_tick_signal)
      add_write(p.day_length_signal)
    end

  elseif t == defines.control_behavior.type.container
      or t == defines.control_behavior.type.logistic_container
      or t == defines.control_behavior.type.proxy_container then
    if output_ok and behavior.read_contents then
      -- Dynamic contents: actual signals are determined from the inventory.
      local inventory = entity.get_inventory(defines.inventory.chest)
      if inventory then
        for _, item in pairs(inventory.get_contents()) do
          add_write({type="item", name=item.name})
        end
      end
      writes.__dynamic = true
    end
    if t == defines.control_behavior.type.logistic_container then
      if input_ok then
        add_read("__dynamic")
      end
      -- TODO possibly incomplete
    end

  elseif t == defines.control_behavior.type.single_fluid_box then
    if (output_ok and behavior.read_temperature) then
      -- TODO
    end
    if (output_ok and behavior.circuit_exclusive_mode_of_operation) then -- TODO operation is an enum
      add_write("__dynamic") -- TODO bad, bad.
    end

  elseif t == defines.control_behavior.type.accumulator then
    if output_ok and behavior.read_charge then add_write(behavior.output_signal) end

  elseif t == defines.control_behavior.type.inserter then
    if input_ok and behavior.circuit_set_stack_size then
      add_read(behavior.circuit_stack_control_signal)
    end
    if output_ok and behavior.circuit_read_hand_contents then
      -- Dynamic: the hand contents are not represented by a fixed signal.
      -- We add the current hand item, when available.
      local hand = entity.held_stack
      if hand and hand.valid_for_read then
        add_write({type="item", name=hand.name})
      end
      writes.__dynamic = true
    end

  elseif t == defines.control_behavior.type.rail_signal
      or t == defines.control_behavior.type.rail_chain_signal then
    if input_ok and behavior.close_signal and behavior.circuit_condition then
      add_read(behavior.circuit_condition.first_signal)
      add_read(behavior.circuit_condition.second_signal)
    end
    if output_ok and behavior.read_signal then
      add_write(behavior.red_signal)
      add_write(behavior.orange_signal)
      add_write(behavior.green_signal)
      add_write(behavior.blue_signal)
    end

  elseif t == defines.control_behavior.type.reactor then
    if output_ok then
      if behavior.read_temperature then add_write(behavior.temperature_signal) end
      -- Fuel signal is dynamic; leave it represented by the generic writer entry.
    end

  elseif t == defines.control_behavior.type.train_stop then
    if input_ok and behavior.circuit_enable_disable and behavior.circuit_condition then
      add_read(behavior.circuit_condition.first_signal)
      add_read(behavior.circuit_condition.second_signal)
    end
    if input_ok then
      add_read(behavior.trains_limit_signal)
      add_read(behavior.priority_signal)
    end
    if output_ok then
      add_write(behavior.trains_count_signal)
    end

  elseif t == defines.control_behavior.type.wall then
    if input_ok then
      add_read(behavior.circuit_condition and behavior.circuit_condition.first_signal)
      add_read(behavior.circuit_condition and behavior.circuit_condition.second_signal)
    end
    if output_ok and behavior.read_sensor then add_write(behavior.output_signal) end

  elseif t == defines.control_behavior.type.assembling_machine then
    if input_ok then
      if behavior.circuit_set_recipe then
         reads.__dynamic = true
         game.print("set recipe")
      end
    end
    if output_ok then
      add_write(behavior.circuit_read_ingredients and "__dynamic") -- TODO fishy
      add_write(behavior.circuit_read_recipe_finished and behavior.circuit_recipe_finished_signal)
      if behavior.circuit_read_recipe_finished then game.print(signal_to_rich_text(behavior.circuit_recipe_finished_signal)) end
    end
    -- TODO assembling_machine might be incomplete
  end

  return reads, writes
end

local function entity_roles(entity, network)
  local readers, writers = {}, {}
  local behavior = entity.get_control_behavior()

  if not behavior then return readers, writers end

  local input_ok = network_selected(behavior.input_networks, network.wire_type)
  local output_ok = network_selected(behavior.output_networks, network.wire_type)

  local accesses = behavior_accesses(entity, behavior, network.wire_type)
  return accesses
end

local function refs_match(refs, selected)
  if not selected then return true end
  return refs[signal_key(selected)] == true
end

local function collect_network(source, network)
  local entities = {}
  local visited = {}

  local function visit_connector(connector)
    if not connector or not connector.valid then return end

    local owner = connector.owner
    if owner and owner.valid and not connector.is_ghost then
      local id = owner.unit_number
      if id and not entities[id] then entities[id] = owner end
    end

    local key = tostring(connector.owner.unit_number or "nil")
      .. ":" .. tostring(connector.wire_connector_id)
    if visited[key] then return end
    visited[key] = true

    for _, connection in pairs(connector.real_connections) do
      local target = connection.target
      if target and target.valid then
        visit_connector(target)
      end
    end
  end

  local connectors = source.get_wire_connectors(false)
  for id, connector in pairs(connectors) do
    if connector.valid and connector.network_id == network.id
        and connector.wire_type == network.wire_type then
      visit_connector(connector)
    end
  end

  return entities
end

local function clear_children(element)
  for _, child in pairs(element.children) do
    child.destroy()
  end
end

local function entity_rich_text(entity)
    return string.format(
        "[entity=%s,unit_number=%d]",
        entity.name,
        entity.unit_number
    )
end

local function add_entity_button(parent, entity, network, role, selected, accesses)
  unit_number_to_entity[entity.unit_number] = entity

  local description = ""
  local description_full = entity.name
  if entity.type == "constant-combinator" or
     entity.type == "arithmetic-combinator" or
     entity.type == "decider-combinator" or
     entity.type == "selector-combinator" then
    description_full = entity.combinator_description
    description = description_full:match("^[^\r\n]*")
  end

  local b = parent.add{
    type = "button",
    caption =  entity_rich_text(entity) .. description,
    tooltip = description_full,
    --caption =  entity_rich_text(entity) .. (entity.localised_name or entity.name),
    -- entity.localised_name is a table and cannot be concatenated. So caption can either be a string or a LocalisedString
    tags = {
      cni_action = "entity",
      unit_number = entity.unit_number
    }
  }
  for _, access in pairs(accesses) do
    parent.add({
      type = "label",
      caption = access.text
    })
  end
end

local function refresh_options(options,enabled)
  options.cni_literal_matching.enabled = enabled
  options.cni_current_writes.enabled = enabled
end

local function refresh_signals(player, network)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end

  if not network then network = network_from_state(state) end

  local left  = player.gui.screen[GUI].body.left

  local signals = network.network.signals or {}
  --table.sort(signals, function(a,b)
  --  return signal_key(a.signal) < signal_key(b.signal)
  --end)
  clear_children(left)
  for _, s in pairs(signals) do
    left.add(Button_Signal(s))
  end
end

local function refresh_accesses(player, network)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end
  if not network then network = network_from_state(state) end
  local source = unit_number_to_entity[ state.source_unit_number]
  
  local selected = state.options.signal

  local entities = collect_network(source, network)

  local right = player.gui.screen[GUI].body.right_scroll_pane.accesses
  clear_children(right)

  right.add{type="label", caption="WRITERS"}
  for _, entity in pairs(entities) do
    local write = false
    local writes = {}
    for _,a in ipairs(entity_roles(entity, network)) do
      if a.currentwrite ~= nil and (selected == nil or a.dynamic_potentials.matches(selected)) then write = true; table.insert(writes,a) end
    end
    if write then add_entity_button(right, entity, nil, "writer", selected, writes) end
  end

  right.add{type="line"}
  right.add{type="label", caption="READERS"}
  for _, entity in pairs(entities) do
    local read = false
    local reads = {}
    for _,a in ipairs(entity_roles(entity, network)) do
      if a.currentwrite == nil and (selected == nil or a.dynamic_potentials.matches(selected)) then read = true; table.insert(reads, a) end
    end
    if read then add_entity_button(right, entity, nil, "reader", selected, reads) end
  end

  if false and (#writers == 0 and #readers == 0) then -- TODO fix.
    right.add{type="label", caption="No matching entities."}
  end
end

local function refresh(player)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end

  local network = network_from_state(state)

  if not network then if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end return end

  local frame = player.gui.screen[GUI]
  if not frame then player.print("no frame");return end

  refresh_signals(player, network)
  refresh_accesses(player, network)
end

local function open_inspector(player, source, network)
  storage.cni = storage.cni or {}
  storage.cni[player.index] = {
    source_unit_number = source.unit_number,
    network_id = network.id,
    wire_type = network.wire_type,
    options = {
      signal = nil,
      literal_matching = false,
      current_writes = false
    }
  }

  if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end

  local frame = player.gui.screen.add{
    type="frame",
    name=GUI,
    direction="vertical"
  }

  local titlebar = frame.add{
    type = "flow",
    direction = "horizontal"
  }

  titlebar.add{
    type = "label",
    caption = "Circuit Network Inspector " .. network.id,
    style = "frame_title"
  }

  titlebar.drag_target = frame

  titlebar.add{
    type = "label",
    caption = "Circuit Network Inspector",
    style = "frame_title",
    ignored_by_interaction = true
  }

  local filler = titlebar.add{
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  }

  filler.style.horizontally_stretchable = true
  filler.style.height = 24

  titlebar.add{
    type = "sprite-button",
    name = "cni_close",
    style = "frame_action_button",
    sprite = "utility/close",
    --hovered_sprite = "utility/close_black",
    --clicked_sprite = "utility/close_black",
    tooltip = {"gui.close-instruction"}
  }
  frame.auto_center = true
  frame.style.width = 800
  frame.style.height = 600

  local state = storage.cni and storage.cni[player.index]
  if not state then return end

  local options = frame.add{type="frame", name="options", direction="vertical" }
  options.style.horizontally_stretchable = true

  local signal_filter_option = options.add{ name = "signal_filter_option", type = "flow", direction="horizontal" }
  signal_filter_option.style.vertical_align = "center"
  signal_filter_option.add{type = "label", caption="only show access to signal: ",
                           tooltip="filters the list of accessing entities to those using the selected signal. Empty for no filter."}

  signal_filter_option.add{
    type = "choose-elem-button",
    name = "cni_signal_filter",
    elem_type = "signal",
    signal = state.options.signal
  }
  options.add{name="cni_literal_matching", type="checkbox", caption="literal matching caption", tooltip="literal matching tooltip", state=state.options.literal_matching}
  options.add{name="cni_current_writes", type="checkbox", caption="current writes caption", tooltip="current writes tooltip", state=state.options.current_writes}
  refresh_options(options, state.options.signal ~= nil)

  local body = frame.add{type="flow", name="body", direction="horizontal"}
  body.style.horizontally_stretchable = true
  body.style.vertically_stretchable = true

  local body = frame.body

  --local left = body.add{type="frame", direction="vertical", style="inside_shallow_frame"}
  --left.style.width = 260
  local left = body.add{name="left", type="table", column_count = 10  }

  local right_scroll_pane = body.add{
    type = "scroll-pane",
    name = "right_scroll_pane",
    direction = "vertical"
  }

  right_scroll_pane.style.vertically_stretchable = true
  right_scroll_pane.style.horizontally_stretchable = true

  right_scroll_pane.add{
    type = "flow",
    name = "accesses",
    direction = "vertical"
  }

  refresh(player)
end

local function empty(x)
  for _, _ in pairs(x) do return false end
  return true
end

local function focus_entity(player, entity)
    if not entity or not entity.valid then
        return
    end

    player.centered_on = entity
    player.zoom = player.zoom_limits.closest.zoom
    player.print(entity.gps_tag) -- this is the only `player.print` that should remain after removing debugging
end

-- only used in gui.
local function network_to_text(network)
  if network.network.wire_connector_id == defines.wire_connector_id.circuit_red then
     return "[item=red-wire] " .. network.id
  elseif network.network.wire_connector_id == defines.wire_connector_id.circuit_green then
     return "[item=green-wire] " .. network.id
  elseif network.network.wire_connector_id == defines.wire_connector_id.combinator_input_red then
     return "[item=red-wire] input " .. network.id
  elseif network.network.wire_connector_id == defines.wire_connector_id.combinator_input_green then
     return "[item=green-wire] input " .. network.id
  elseif network.network.wire_connector_id == defines.wire_connector_id.combinator_output_red then
     return "[item=red-wire] out " .. network.id
  elseif network.network.wire_connector_id == defines.wire_connector_id.combinator_output_green then
     return "[item=green-wire] out " .. network.id
  end
end

-- Add a small button next to Factorio's additional-entity-info GUI.
local function add_relative_button(player, entity)
  destroy_relative(player)
  if not entity or not entity.valid then return end

  local networks = circuit_networks(entity)
  if empty(networks) then return end
  if not Entity_type_to_gui_type[entity.type] then player.print("Missing " .. entity.type .. " in table") ; return end
  player.gui.relative.add{
    type = "frame",
    name = BUTTON,
    caption = "Inspect circuit networks",
	direction = "vertical",
	anchor = {
		gui = Entity_type_to_gui_type[entity.type],
		position = defines.relative_gui_position.right
	},
	style = "frame"
  }
  for _, network in pairs(networks) do
    unit_number_to_entity[entity.unit_number] = entity
    player.gui.relative[BUTTON].add{
      type = "button",
      name = BUTTON .. "inFrame" .. network.id,
      caption = "ⓘ " .. network_to_text(network),
      tooltip = "Inspect circuit network",
      tags = {
          cni_action = "open_from_entity",
          unit_number = entity.unit_number,
          network = network
      }
    }
  end
  player.gui.relative[BUTTON].add{type="line"}
  player.gui.relative[BUTTON].add{
    type = "button",
    name = BUTTON .. "focus",
    caption = "focus entity",
    tooltip = "this is useful if you opened this entity from the network inspector and don't know where it is",
    tags = {
      cni_action = "focus_entity",
      unit_number = entity.unit_number
    }
  }
end

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.gui_type == defines.gui_type.entity and event.entity then
    add_relative_button(player, event.entity)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.element and event.element.valid and event.element.name == GUI then
    if storage.cni then storage.cni[player.index] = nil end
  end

  if event.gui_type == defines.gui_type.entity then
    destroy_relative(player)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if not (player and element and element.valid) then return end

  if event.element.name == "cni_close" then
    player.gui.screen[GUI].destroy()
    return
  end

  local action = element.tags and element.tags.cni_action
  if not action then return end

  if action == "open_from_entity" then
    local network = element.tags.network
    --local entity = game.get_entity_by_unit_number(element.tags.unit_number)
    local entity = unit_number_to_entity[element.tags.unit_number]
	if not entity then player.print("NOT entity") end
    if not entity then return end
    if network then
      open_inspector(player, entity, network)
    else
      player.print("No circuit network found.")
    end

  elseif action == "filter_signal" then -- currently dead, no such action
    local state = storage.cni and storage.cni[player.index]
    if state then
      state.options.signal = {
        type = element.tags.signal_type,
        name = element.tags.signal_name,
        quality = element.tags.signal_quality
      }
      refresh(player)
    end

  elseif action == "entity" then
    local entity = unit_number_to_entity[element.tags.unit_number]
    if not entity or not entity.valid then return end

    player.selected = entity
    if entity.operable then
      player.opened = entity
    end

    if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end
    if storage.cni then storage.cni[player.index] = nil end
  elseif action == "focus_entity" then
    local entity = unit_number_to_entity[element.tags.unit_number]
    focus_entity(player,entity)
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)

  if event.element.name == "cni_signal_filter" then

    local signal = event.element.elem_value
    storage.cni[event.player_index].options.signal = signal
    if signal then
        game.print(
            "Selected: "
            .. (signal.type or "item")
            .. "="
            .. signal.name
        )
    else
        game.print("No signal selected")
    end
    refresh_options(event.element.parent.parent, signal ~= nil)
    refresh_accesses(game.get_player(event.player_index))

  elseif event.element.name == "cni_literal_matching" then
    storage.cni[event.player_index].options.literal_matching = event.element.state
    refresh_accesses(game.get_player(event.player_index))
  elseif event.element.name == "cni_current_writes" then
    storage.cni[event.player_index].options.current_writes = event.element.state
    refresh_accesses(game.get_player(event.player_index))
  end
end)

script.on_event(defines.events.on_tick, function(event)
  -- Keep the signal values reasonably live without rebuilding every tick.
  if event.tick % 15 ~= 0 or not storage.cni then return end
  for player_index, state in pairs(storage.cni) do
    local player = game.get_player(player_index)
    if player and player.gui.screen[GUI] and player.gui.screen[GUI].valid then
      refresh_signals(player)
    end
  end
end)

script.on_init(function()
  storage.cni = {}
end)

script.on_configuration_changed(function()
  storage.cni = storage.cni or {}
end)
