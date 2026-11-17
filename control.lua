local cni_relative_gui = require("cni_relative_gui")
require("gui")
require("accesses")

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
            wire_connector_id = network.wire_connector_id,
            network = network
          }
        end
      end
    end
  end

  return result
end

local function network_from_state(state)
  local source = unit_number_to_entity[ state.inspected_network.source_unit_number]
  if not source or not source.valid then return nil end
  return circuit_networks(source)[tostring(tostring(state.inspected_network.network_id) .. ":" .. tostring(state.inspected_network.wire_type))]
end

local function network_from_inspected_network(inspected_network)
  return network_from_state{inspected_network=inspected_network} -- TODO hacky inversion
end

local function entity_roles(entity, network)
  return Behavior_accesses(entity, entity.get_control_behavior(), network)
end

local function refs_match(refs, selected)
  if not selected then return true end
  return refs[signal_key(selected)] == true -- TODO unused, remove?
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

-- only used in gui.
local function network_to_text(network)
  if network.wire_connector_id == defines.wire_connector_id.circuit_red then
     return "[item=red-wire] " .. network.id
  elseif network.wire_connector_id == defines.wire_connector_id.circuit_green then
     return "[item=green-wire] " .. network.id
  elseif network.wire_connector_id == defines.wire_connector_id.combinator_input_red then
     return "[item=red-wire] input " .. network.id
  elseif network.wire_connector_id == defines.wire_connector_id.combinator_input_green then
     return "[item=green-wire] input " .. network.id
  elseif network.wire_connector_id == defines.wire_connector_id.combinator_output_red then
     return "[item=red-wire] out " .. network.id
  elseif network.wire_connector_id == defines.wire_connector_id.combinator_output_green then
     return "[item=green-wire] out " .. network.id
  end
end

local function add_entity_button(parent, entity, entity_roles, role, selected, accesses)
  unit_number_to_entity[entity.unit_number] = entity

  local entity_panel = parent.add{type="frame",direction="horizontal", style="cni_forward_frame"}
  entity_panel.style.horizontally_stretchable = true
  local other_in_flow = entity_panel.add{type="flow",direction="vertical"}
  other_in_flow.style.width = 60
  if entity_roles and entity_roles.other_in then
    for color, network in pairs(entity_roles.other_in) do
      unit_number_to_entity[entity.unit_number] = entity -- TODO again here? necessary or not?
      other_in_flow.add{ -- TODO duplication from add_relative_button
        type = "button",
        name = BUTTON .. "inFrame" .. network.id,
        caption = "[item=" .. color .. "-wire]",
        tooltip = "Inspect circuit network " .. network.id,
        style = "forward_button",
        tags = {
            cni_action = "open_from_entity",
            unit_number = entity.unit_number,
            network = network
        }
      }.style.width = 60
    end
  end

  local epf = entity_panel.add{
    type = "frame",
    style = "cni_button_like_frame"
  }
  local ep = epf.add{type="entity-preview"}
  ep.visible = true
  ep.entity=entity -- Rseding91: "Assignment on creation isn't supported and never will be." https://forums.factorio.com/viewtopic.php?p=346036#p346036
  ep.style.width = 64
  ep.style.height = 64
  ep.tags = {
    cni_action = "entity",
    unit_number = entity.unit_number
  }

  local access_panel = entity_panel.add{type="flow", direction="vertical"}
  access_panel.style.horizontally_stretchable = true
  local description = ""
  local description_full = entity.name
  if entity.type == "constant-combinator" or
     entity.type == "arithmetic-combinator" or
     entity.type == "decider-combinator" or
     entity.type == "selector-combinator" then
    description_full = entity.combinator_description
    description = description_full:match("^[^\r\n]*")
    if description_full and description_full ~= "" then
      access_panel.add({type="label", caption = description, tooltip=description_full})
    end
  end
  for _, access in pairs(accesses) do
    access_panel.add({
      type = "label",
      caption = access.text
    })
  end

  local other_out_flow = entity_panel.add{type="flow",direction="vertical"}
  other_out_flow.style.width = 60
  if entity_roles and entity_roles.other_out then
    for color, network in pairs(entity_roles.other_out) do
      unit_number_to_entity[entity.unit_number] = entity -- TODO again here? necessary or not?
      other_out_flow.add{ -- TODO duplication from add_relative_button
        type = "button",
        name = BUTTON .. "inFrame" .. network.id,
        caption = "[item=" .. color .. "-wire]",
        tooltip = "Inspect circuit network " .. network.id,
        style = "forward_button",
        tags = {
            cni_action = "open_from_entity",
            unit_number = entity.unit_number,
            network = network
        }
      }.style.width = 60
    end
  end

end

local function refresh_options(options_frame,state_options)
  options_frame.signal_filter_option.cni_signal_filter.elem_value = state_options.signal
  local enabled = state_options.signal ~= nil
  options_frame.cni_literal_matching.enabled = enabled
  options_frame.cni_current_writes.enabled = enabled
end

local function refresh_signals(player, network)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end

  if not network then network = network_from_state(state) end
  if not network then player.print("did you just load a game?"); return end

  local signal_gui  = player.gui.screen[GUI].scroll_pane.body.signal_gui_frame.signal_gui

  local signals = network.network.signals or {}
  --table.sort(signals, function(a,b)
  --  return signal_key(a.signal) < signal_key(b.signal)
  --end)
  clear_children(signal_gui)
  for _, s in pairs(signals) do
    local bs = signal_gui.add(Button_Signal(s, {
        cni_action = "filter_signal",
        signal_type = s.signal.type,
        signal_name = s.signal.name,
        signal_quality = s.signal.quality,
    }, (state.inspected_network.wire_type == defines.wire_type.green) and 1 or 2))
  end
end

local function is_access(a, options, filter_writes)
  local a_is_write = a.currentwrite ~= nil
  if a_is_write ~= filter_writes then return false end
  if options.signal == nil then return true
  else
    if a_is_write and options.current_writes then
      for _, s in ipairs(a.currentwrite) do
        if Same_signal(options.signal,s.signal) then return true end
      end
      return false
    end
    if not options.literal_matching and (
       a.dynamic_potentials:matches({type = "virtual", name="signal-all"}) or
       a.dynamic_potentials:matches({type = "virtual", name="signal-each"}) or
       a.dynamic_potentials:matches({type = "virtual", name="signal-any"}))
    then return true end

    return a.dynamic_potentials:matches(options.signal)
  end
end

local function refresh_accesses(player, network)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end
  if not network then network = network_from_state(state) end
  local source = unit_number_to_entity[ state.inspected_network.source_unit_number]
  local options = state.options

  local entities = collect_network(source, network)

  local writer_gui = player.gui.screen[GUI].scroll_pane.body.writer_gui
  clear_children(writer_gui)

  writer_gui.add{type="label", caption="WRITERS", tooltip="entities writing to the network (reading from entity)"}
  for _, entity in pairs(entities) do
    local write = false
    local writes = {}
    local er = entity_roles(entity, network)
    for _,a in ipairs(er.writes) do
      if is_access(a,options,true) then write = true; table.insert(writes,a) end
    end
    if write then
      add_entity_button(writer_gui, entity, er, "writer", options.signal, writes)
    end
  end

  local reader_gui = player.gui.screen[GUI].scroll_pane.body.reader_gui
  clear_children(reader_gui)

  reader_gui.add{type="label", caption="READERS", tooltip="entities reading from the network (writing to entity)"}
  for _, entity in pairs(entities) do
    local read = false
    local reads = {}
    local er = entity_roles(entity, network)
    for _,a in ipairs(er.reads) do
      if is_access(a,options,false) then read = true; table.insert(reads, a) end
    end
    if read then
      add_entity_button(reader_gui, entity, er, "reader", options.signal, reads)
    end
  end
end

local function refresh(player)
  local state = storage.cni and storage.cni[player.index]
  if not state then return end

  local network = network_from_state(state)

  if not network then if player.gui.screen[GUI] then player.gui.screen[GUI].destroy() end return end

  local frame = player.gui.screen[GUI]
  if not frame then player.print("no frame");return end

  refresh_options(frame.options, state.options)
  refresh_signals(player, network)
  refresh_accesses(player, network)
end

local function render_inspector(player, network)
  if player.gui.screen[GUI] then
    local titlebar = player.gui.screen[GUI].titlebar
    titlebar.label.caption = "Circuit Network Inspector " .. network_to_text(network)
    titlebar.cni_previous.enabled = #storage.history[player.index].back    > 0
    titlebar.cni_next    .enabled = #storage.history[player.index].forward > 0
    refresh(player)
    return
  end

  local frame = player.gui.screen.add{
    type="frame",
    name=GUI,
    direction="vertical"
  }
  player.opened = frame

  local titlebar = frame.add{
    name = "titlebar",
    type = "flow",
    direction = "horizontal"
  }

  titlebar.drag_target = frame

  titlebar.add{
    name = "label",
    type = "label",
    caption = "Circuit Network Inspector " .. network_to_text(network),
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
    name = "cni_previous",
    style = "frame_action_button",
    sprite = "utility/backward_arrow",
    --hovered_sprite = "utility/backward_arrow_black",
    --clicked_sprite = "utility/backward_arrow_black",
    enabled = false,
    tooltip = {"gui-tooltip.cni_previous"}
  }
  titlebar.add{
    type = "sprite-button",
    name = "cni_next",
    style = "frame_action_button",
    sprite = "utility/forward_arrow",
    --hovered_sprite = "utility/forward_arrow_black",
    --clicked_sprite = "utility/forward_arrow_black",
    enabled = false,
    tooltip = {"gui-tooltip.cni_next"}
  }
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
  local scale = player.display_scale
  local width        = math.floor(player.display_resolution.width  * 0.8 / scale)
  frame.style.width  = width
  frame.style.height = math.floor(player.display_resolution.height * 0.8 / scale)

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
  options.add{name="cni_literal_matching", type="checkbox", caption="literal signal matching", tooltip="Require an exact signal match. When disabled, dynamic signals such as [virtual-signal=signal-each] match any selected signal.", state=state.options.literal_matching}
  options.add{name="cni_current_writes", type="checkbox", caption="use current writes, not potential", tooltip="Match only if there is a signal output now, instead of could be output.", state=state.options.current_writes}
  refresh_options(options, state.options)

  local scroll_pane = frame.add{
    type = "scroll-pane",
    name = "scroll_pane",
    direction = "vertical",
    style = "train_schedule_scroll_pane",
  }
  width = width - 24
  scroll_pane.style.width = width
  --scroll_pane.style.horizontally_stretchable = true
  width = width - 16

  local body = scroll_pane.add{type="flow", name="body", direction="horizontal"}
  body.style.horizontally_stretchable = true
  body.style.vertically_stretchable = true

  local writer_gui = body.add{name="writer_gui", type = "flow", direction="vertical"}
  writer_gui.style.vertically_stretchable = true
  writer_gui.style.horizontally_stretchable = true

  local signal_gui_frame = body.add{name="signal_gui_frame", type="scroll-pane", direction="vertical", style="logistic_sections_scroll_pane",
     vertical_scroll_policy="never"
  }
  signal_gui_frame.style.vertically_stretchable = true
  local signal_gui = signal_gui_frame.add{name="signal_gui", type="table", column_count = 10, style = "compact_slot_table"  }
  signal_gui.style.cell_padding = 1

  local reader_gui = body.add{name="reader_gui", type = "flow", direction="vertical"}
  reader_gui.style.vertically_stretchable = true
  reader_gui.style.horizontally_stretchable = true

  refresh(player)
end

local function get_player_history(player_index)
  storage.history = storage.history or {}
  storage.history[player_index] = storage.history[player_index] or {
    back = {},
    forward = {},
    current = nil
  }
  return storage.history[player_index]
end

local function navigate_to(player, new_state, render_gui_callback)
  local hist = get_player_history(player.index)
  if hist.current then
    table.insert(hist.back, hist.current)
  end
  hist.current = new_state
  hist.forward = {} -- Clear forward stack on new navigation
end

local function open_inspector(player, source, network)
  storage.cni = storage.cni or {}
  local inspected_network = {
      source_unit_number = source.unit_number,
      network_id = network.id,
      wire_type = network.wire_type
  }
  navigate_to(player, inspected_network)
  local options = storage.cni[player.index] and storage.cni[player.index].options
  storage.cni[player.index] = {
    inspected_network = inspected_network,
    options = options or {
      signal = nil,
      literal_matching = false,
      current_writes = false
    }
  }
  render_inspector(player, network)
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

-- Add a small button next to Factorio's additional-entity-info GUI.
local function add_relative_button(player, entity)
  destroy_relative(player)
  if not entity or not entity.valid then return end

  local networks = circuit_networks(entity)
  if empty(networks) then return end
  if not cni_relative_gui.gui_type_from_entity(entity) then player.print("Missing " .. entity.type .. " in table") ; return end
  player.gui.relative.add{
    type = "frame",
    name = BUTTON,
    caption = "Inspect circuit networks",
	direction = "vertical",
	anchor = {
		gui = cni_relative_gui.gui_type_from_entity(entity),
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

-- Helper to verify your mod's main frame is the active opened GUI
local function is_my_gui_open(player)
  return player and player.gui.screen[GUI]
end

local function cni_previous(event)
  local player = game.get_player(event.player_index)
  if not (player and is_my_gui_open(player)) then return end

  local hist = get_player_history(player.index)
  if #hist.back == 0 then return end

  if hist.current then
    table.insert(hist.forward, hist.current)
  end
  hist.current = table.remove(hist.back)
  storage.cni[player.index].inspected_network = hist.current

  render_inspector(player, network_from_inspected_network(hist.current))
end

local function cni_next(event)
  local player = game.get_player(event.player_index)
  if not (player and is_my_gui_open(player)) then return end

  local hist = get_player_history(player.index)
  if #hist.forward == 0 then return end

  if hist.current then
    table.insert(hist.back, hist.current)
  end
  hist.current = table.remove(hist.forward)
  storage.cni[player.index].inspected_network = hist.current

  render_inspector(player, network_from_inspected_network(hist.current))
end

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.gui_type == defines.gui_type.entity and event.entity then
    add_relative_button(player, event.entity)
  end
end)

local function delete_storage(player)
  if storage.cni then
    storage.cni[player.index] = nil
  end
  if storage.history then
    storage.history[player.index] = nil
  end
end

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.element and event.element.valid and event.element.name == GUI then
    delete_storage(player)
    event.element.destroy()
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
    delete_storage(player)
    return
  elseif event.element.name == "cni_previous" then
    cni_previous(event)
    return
  elseif event.element.name == "cni_next" then
    cni_next(event)
    return
  end

  local action = element.tags and element.tags.cni_action
  if not action then return end

  if action == "open_from_entity" then
    local network = element.tags.network
    local entity = unit_number_to_entity[element.tags.unit_number]
    if not entity then return end
    if network then
      open_inspector(player, entity, network)
    else
      player.print("No circuit network found.")
    end

  elseif action == "filter_signal" then
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
    local options = storage.cni[event.player_index].options
    options.signal = signal
    refresh_options(event.element.parent.parent, options)
    refresh_accesses(game.get_player(event.player_index))
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  if event.element.name == "cni_literal_matching" then
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

-- Listen for ALT + LEFT
script.on_event("cni_previous", cni_previous)

-- Listen for ALT + RIGHT
script.on_event("cni_next", cni_next)
