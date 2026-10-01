local MOD = "circuit-network-inspector"
local GUI = "cni_frame"
local BUTTON = "cni_button"

local function destroy_relative(player)
  local e = player.gui.relative[BUTTON]
  if e and e.valid then e.destroy() end
end

local function circuit_networks(entity)
  local result = {}
  if not (entity and entity.valid) then return result end

  local connectors = entity:get_wire_connectors(false)
  for id, connector in pairs(connectors) do
    if connector.valid and connector.network_id and connector.network_id ~= 0 then
      local network = entity:get_circuit_network(id)
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

local function first_network(entity)
  local networks = circuit_networks(entity)
  for _, n in pairs(networks) do return n end
  return nil
end

local function signal_key(signal)
  if not signal then return nil end
  return (signal.type or "item") .. ":" .. tostring(signal.name)
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
  if input_ok and behavior.circuit_enable_disable and behavior.circuit_condition then
    add_read(behavior.circuit_condition.first_signal)
    add_read(behavior.circuit_condition.second_signal)
  end

  local t = behavior.type

  if t == "arithmetic-combinator" then
    local p = behavior.parameters
    if p then
      add_read(p.first_signal, p.first_signal_networks)
      add_read(p.second_signal, p.second_signal_networks)
      if output_ok then add_write(p.output_signal) end
    end

  elseif t == "decider-combinator" then
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

  elseif t == "selector-combinator" then
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

  elseif t == "container"
      or t == "logistic-container"
      or t == "proxy-container" then
    if output_ok and behavior.read_contents then
      -- Dynamic contents: actual signals are determined from the inventory.
      local inventory = entity.get_inventory(defines.inventory.chest)
      if inventory then
        for _, item in pairs(inventory.get_contents()) do
          add_write({type="item", name=item.name})
        end
      end
    end

  elseif t == "accumulator" then
    if output_ok and behavior.read_charge then add_write(behavior.output_signal) end

  elseif t == "inserter" then
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
    end

  elseif t == "rail-signal"
      or t == "rail-chain-signal" then
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

  elseif t == "reactor" then
    if output_ok then
      if behavior.read_temperature then add_write(behavior.temperature_signal) end
      -- Fuel signal is dynamic; leave it represented by the generic writer entry.
    end

  elseif t == "train-stop" then
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

  elseif t == "wall" then
    if input_ok then
      add_read(behavior.circuit_condition and behavior.circuit_condition.first_signal)
      add_read(behavior.circuit_condition and behavior.circuit_condition.second_signal)
    end
    if output_ok and behavior.read_sensor then add_write(behavior.output_signal) end
  end

  return reads, writes
end

local function entity_roles(entity, network)
  local readers, writers = {}, {}
  local behavior = entity.get_control_behavior()

  if not behavior then return readers, writers end

  local input_ok = behavior.input_networks ~= nil
      and network_selected(behavior.input_networks, network.wire_type)
  local output_ok = behavior.output_networks ~= nil
      and network_selected(behavior.output_networks, network.wire_type)

  local reads, writes = behavior_signals(entity, behavior, network.wire_type)

  if input_ok then
    for _, _ in pairs(reads) do
      readers = reads
      break
    end
    -- A generic condition reader should count even if there is no signal
    -- reference we could extract.
    if behavior.circuit_enable_disable and behavior.circuit_condition then
      readers.__generic = true
    end
  end

  if output_ok then
    for _, _ in pairs(writes) do
      writers = writes
      break
    end

    -- Some behaviors output dynamic signals (inventory, fuel, etc.).
    if behavior.read_contents or behavior.circuit_read_hand_contents
        or behavior.read_fuel or behavior.read_temperature or behavior.read_signal then
      writers.__generic = true
    end
  end

  return readers, writers
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
    if owner and owner.valid and not owner.is_ghost then
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

  local connectors = source:get_wire_connectors(false)
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

local function add_entity_button(parent, entity, role, selected)
  local b = parent.add{
    type = "button",
    caption = entity.localised_name or entity.name,
    tags = {
      cni_action = "entity",
      unit_number = entity.unit_number
    }
  }
  b.tooltip = entity.name
end

local function refresh(player)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end

  local source = game.get_entity_by_unit_number(state.source_unit_number)
  if not source or not source.valid then
    if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end
    return
  end

  local network = nil
  local connectors = source:get_wire_connectors(false)
  for id, connector in pairs(connectors) do
    if connector.valid
        and connector.network_id == state.network_id
        and connector.wire_type == state.wire_type then
      network = source:get_circuit_network(id)
      if network then break end
    end
  end

  if not network then return end

  local frame = player.gui.screen[GUI]
  if not frame then return end

  frame.caption = "Circuit Network " .. network.network_id
  local body = frame.body
  clear_children(body)

  local left = body.add{type="frame", direction="vertical", style="inside_shallow_frame"}
  left.style.width = 260
  local right = body.add{type="frame", direction="vertical", style="inside_shallow_frame"}
  right.style.width = 520

  local all = left.add{
    type="button",
    caption = "∀  All signals",
    tags = {cni_action="filter_all"}
  }
  all.style.horizontally_stretchable = true

  local signals = network.signals or {}
  table.sort(signals, function(a,b)
    return signal_key(a.signal) < signal_key(b.signal)
  end)

  for _, s in pairs(signals) do
    local button = left.add{
      type="button",
      caption = signal_text(s.signal) .. "  " .. tostring(s.count),
      tags = {
        cni_action="filter_signal",
        signal_type=s.signal.type or "item",
        signal_name=s.signal.name
      }
    }
    button.style.horizontally_stretchable = true
  end

  local selected = state.signal

  local entities = collect_network(source, network)
  local readers, writers = {}, {}

  for _, entity in pairs(entities) do
    local r, w = entity_roles(entity, network)
    local reader_match = selected == nil or r[signal_key(selected)] or r.__generic
    local writer_match = selected == nil or w[signal_key(selected)] or w.__generic

    if reader_match then table.insert(readers, entity) end
    if writer_match then table.insert(writers, entity) end
  end

  local function sort_entities(list)
    table.sort(list, function(a,b)
      return tostring(a.localised_name or a.name) < tostring(b.localised_name or b.name)
    end)
  end
  sort_entities(writers)
  sort_entities(readers)

  right.add{type="label", caption="WRITERS"}
  for _, entity in pairs(writers) do
    add_entity_button(right, entity, "writer", selected)
  end

  right.add{type="line"}
  right.add{type="label", caption="READERS"}
  for _, entity in pairs(readers) do
    add_entity_button(right, entity, "reader", selected)
  end

  if #writers == 0 and #readers == 0 then
    right.add{type="label", caption="No matching entities."}
  end
end

local function open_inspector(player, source, network)
  storage.cni = storage.cni or {}
  storage.cni[player.index] = {
    source_unit_number = source.unit_number,
    network_id = network.id,
    wire_type = network.wire_type,
    signal = nil
  }

  if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end

  local frame = player.gui.screen.add{
    type="frame",
    name=GUI,
    direction="vertical",
    caption="Circuit Network " .. network.id
  }
  frame.auto_center = true
  frame.style.width = 800
  frame.style.height = 600

  local body = frame.add{type="flow", name="body", direction="horizontal"}
  body.style.horizontally_stretchable = true
  body.style.vertically_stretchable = true

  refresh(player)
end

-- Add a small button next to Factorio's additional-entity-info GUI.
local function add_relative_button(player, entity)
  destroy_relative(player)
  if not entity or not entity.valid then return end
  if not first_network(entity) then return end

  player.gui.relative.add{
    type = "button",
    name = BUTTON,
    caption = "ⓘ",
    tooltip = "Inspect circuit network",
    anchor = {
      gui = defines.relative_gui_type.additional_entity_info_gui,
      position = defines.relative_gui_position.right,
      type = entity.type,
      name = entity.name
    },
    tags = {cni_action="open_from_entity", unit_number=entity.unit_number}
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

  local action = element.tags and element.tags.cni_action
  if not action then return end

  if action == "open_from_entity" then
    local entity = game.get_entity_by_unit_number(element.tags.unit_number)
    if not entity then return end
    local network = first_network(entity)
    if network then
      open_inspector(player, entity, network)
    else
      player.print("No circuit network found.")
    end

  elseif action == "filter_all" then
    local state = storage.cni and storage.cni[player.index]
    if state then
      state.signal = nil
      refresh(player)
    end

  elseif action == "filter_signal" then
    local state = storage.cni and storage.cni[player.index]
    if state then
      state.signal = {
        type = element.tags.signal_type,
        name = element.tags.signal_name
      }
      refresh(player)
    end

  elseif action == "entity" then
    local entity = game.get_entity_by_unit_number(element.tags.unit_number)
    if not entity or not entity.valid then return end

    player.selected = entity
    if entity.operable then
      player.opened = entity
    end

    if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end
    if storage.cni then storage.cni[player.index] = nil end
  end
end)

script.on_event(defines.events.on_tick, function(event)
  -- Keep the signal values reasonably live without rebuilding every tick.
  if event.tick % 15 ~= 0 or not storage.cni then return end
  for player_index, state in pairs(storage.cni) do
    local player = game.get_player(player_index)
    if player and player.gui.screen[GUI] and player.gui.screen[GUI].valid then
      refresh(player)
    end
  end
end)

script.on_init(function()
  storage.cni = {}
end)

script.on_configuration_changed(function()
  storage.cni = storage.cni or {}
end)
