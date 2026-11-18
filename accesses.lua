
local function signal_key(signal)
  if not signal then return nil end
  return (signal.type or "item") .. ":" .. tostring(signal.name) .. " q=" .. tostring(signal.quality or "normal")
end

local function same_signal(a, b)
  return signal_key(a) == signal_key(b)
end

function Same_signal(a, b) -- TODO only needed in one instance outside, re-check coupling
  return same_signal(a, b)
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

local function combinator_wires_selected(selection, is_out, entity, network)
  local red, green
  if is_out then
    red, green = defines.wire_connector_id.combinator_output_red,defines.wire_connector_id.combinator_output_green
  else
    red, green =  defines.wire_connector_id.combinator_input_red, defines.wire_connector_id.combinator_input_green
  end
  return
    entity.get_wire_connector(red  ) and entity.get_wire_connector(red  ).network_id == network.id and (not selection or selection.red) or
    entity.get_wire_connector(green) and entity.get_wire_connector(green).network_id == network.id and (not selection or selection.green)
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
  currentWriteContribution :: array of signal as seen in https://lua-api.factorio.com/latest/classes/LuaCombinatorControlBehavior.html#signals_last_tick
  dynamicPotentials :: {
     description:: text,
     directAccess :: array SignalID?,
     matches :: function (SignalID) to boolean
  }
  text :: rich text
  access :: enum { write, read } --
}
]]
Signal_access = {
  description = "",
  direct_access = {},
  matches = function (self ,s)
    for _,da in ipairs(self.direct_access) do
      if same_signal(da, s) then return true end
    end
    return false
  end
}

function Signal_access:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Signal_access:new_single(desc, signal)
  local o = {
    description = desc,
    direct_access = { signal },
    single_signal = signal,
    matches = function (self, s) return same_signal(s, self.single_signal) end
  }
  return Signal_access:new(o)
end

function Signal_access:new_type_match(desc, type)
  return Signal_access:new{description = desc, type = type,
    matches = function (self, s) return (s.type or "item") == self.type end
  }
end

function Signal_access:write_item_or_fluid(desc)
  return Signal_access:new{description = desc,
    matches = function (self, s) return (s.type == nil) or (s.type == "fluid") end
  }
end

local both_selected = { red = true, green = true }

function Behavior_accesses(entity, behavior, network)
  local wire_type = network.wire_type
  local result = { entity = entity, reads = {}, writes = {} }

  local function add_read(text, potentials)
    table.insert(result.reads,
    {
      text = text,
      currentwrite = nil,
      dynamic_potentials = potentials,
    })
  end

  local function add_write(text, currentwrite, potentials)
    table.insert(result.writes,
    {
      text = text,
      currentwrite = currentwrite, -- nil: read, {} or more: write
      dynamic_potentials = potentials,
    })
  end

  local function add_set(text, signal, value)
    local write_contribution = {}
    if signal then
      table.insert(write_contribution, {
        signal = signal,
        count = value
      })
    end

    add_write(
      text .. (signal_to_rich_text(signal) or "N/A")
        .. " = " .. (value or "(not set)"),
      write_contribution,
      Signal_access:new_single("set a value", signal)
    )
  end

  local function add_simple_read(text, signal)
    add_read(
      text,
      Signal_access:new_single("read a value", signal)
    )
  end

  local function add_type_read(text, type, currentwrite) -- TODO function name wrong, "read"
    if currentwrite then
      add_write(
        text,
        currentwrite,
        Signal_access:new_type_match("any " .. type, type)
      )
    else
      add_read(
        text,
        Signal_access:new_type_match("any " .. type, type)
      )
    end
  end

  local function add_comparison(text, circuit_condition)
    if not circuit_condition then return end

    add_read(
      text
        .. (signal_to_rich_text(circuit_condition.first_signal) or "N/A")
        .. (circuit_condition.comparator or "<")
        .. (signal_to_rich_text(circuit_condition.second_signal)
            or circuit_condition.constant
            or "N/A"),
      Signal_access:new{
        description = "comparison",
        direct_access = {
          circuit_condition.first_signal,
          circuit_condition.second_signal
        }
      }
    )
  end

  -- Copy an array of signals_last_tick into the format used by
  -- currentwrite.
  local function current_signals(signals)
    local result = {}

    for _, s in pairs(signals or {}) do
      table.insert(result, {
        signal = {
          type = s.signal.type,
          name = s.signal.name
        },
        count = s.count
      })
    end

    return result
  end

  -- For combinators: their actual output is directly exposed by
  -- signals_last_tick.
  local function add_combinator_output(text, signal, value)
    local current = current_signals(behavior.signals_last_tick)

    add_write(
      text .. (signal_to_rich_text(signal) or "N/A") .. (value or ""),
      current,
      Signal_access:new_single("output", signal)
    )
  end

  -- Read an inventory as dynamically selected item signals.
  local function add_inventory_contents(text, inventory)
    local current = {}

    if inventory then
      for _, item in pairs(inventory.get_contents()) do
        table.insert(current, {
          signal = {
            type = "item",
            name = item.name
          },
          count = item.count
        })
      end
    end

    add_write(
      text,
      current,
      Signal_access:new_type_match("any item", "item")
    )
  end

  -- Read several inventories as one circuit output.
  local function add_inventories(text, inventories)
    local current = {}

    for _, inventory in ipairs(inventories) do
      if inventory then
        for _, item in pairs(inventory.get_contents()) do
          table.insert(current, {
            signal = {
              type = "item",
              name = item.name
            },
            count = item.count
          })
        end
      end
    end

    add_write(
      text,
      current,
      Signal_access:new_type_match("any item", "item")
    )
  end

  local combinator_in  = {red = defines.wire_connector_id.combinator_input_red , green = defines.wire_connector_id.combinator_input_green }
  local combinator_out = {red = defines.wire_connector_id.combinator_output_red, green = defines.wire_connector_id.combinator_output_green}
  local function gather_neighbors(connectors)
    local result = {}
    local found = nil
    for color, value in pairs(connectors) do
        local network = entity.get_wire_connector(value)
        if network and network.network_id ~= 0 then
          result[color] = {
            id = network.network_id,
            wire_type = network.wire_type,
            wire_connector_id = network.wire_connector_id,
            network = network
          }
          found = true
        end
    end
    return found and result
  end

  -- Add all signals currently emitted by a combinator.
  local function add_combinator_all_outputs(text)
    add_write(
      text,
      current_signals(behavior.signals_last_tick),
      Signal_access:new_type_match("any signal", "virtual")
    )
  end

  if not behavior then
    return result
  end

  local input_ok = network_selected(behavior.input_networks, wire_type)
  local output_ok = network_selected(behavior.output_networks, wire_type)

  -- All LuaGenericOnOffControlBehavior descendants can have this.
  local has_circuit_enable_disable =
    pcall(function() return behavior.circuit_enable_disable end)

  if has_circuit_enable_disable
      and input_ok
      and behavior.circuit_enable_disable
      and behavior.circuit_condition then

    add_comparison("Enable if ", behavior.circuit_condition)
  end

  local t = behavior.type

  if t ~= defines.control_behavior.type.arithmetic_combinator and
     t ~= defines.control_behavior.type.decider_combinator    and
     t ~= defines.control_behavior.type.selector_combinator then
      if input_ok then
        result.other_out = {} -- TODO
      end
      if output_ok then
        result.other_in  = {} -- TODO
      end
  end

  --------------------------------------------------------------------------
  -- COMBINATORS
  --------------------------------------------------------------------------

  if t == defines.control_behavior.type.arithmetic_combinator then

    local p = behavior.parameters

    if p then
      if combinator_wires_selected(p.first_signal_networks , false, entity, network) or
         combinator_wires_selected(p.second_signal_networks, false, entity, network) then
        add_read(
          (signal_to_rich_text(p.first_signal) or p.first_constant)
            .. p.operation
            .. (signal_to_rich_text(p.second_signal) or p.second_constant),
          Signal_access:new{
            description = "arithmetic operation",
            direct_access = {
              combinator_wires_selected(p.first_signal_networks , false, entity, network)
                and p.first_signal,
              combinator_wires_selected(p.second_signal_networks, false, entity, network)
                and p.second_signal
            },
            matches = function(self, s)
              return
                (p.first_signal
                  and combinator_wires_selected(p.first_signal_networks , false, entity, network)

                  and same_signal(s, p.first_signal))
                or
                (p.second_signal
                  and combinator_wires_selected(p.second_signal_networks, false, entity, network)
                  and same_signal(s, p.second_signal))
            end
          }
        )
        result.other_out = gather_neighbors(combinator_out)
      end

      if combinator_wires_selected(behavior.output_networks, true, entity, network) then
        add_combinator_output("result ", p.output_signal)
        result.other_in = gather_neighbors(combinator_in)
      end
    end


  elseif t == defines.control_behavior.type.decider_combinator then

    local p = behavior.parameters

    if p then
      for i, c in pairs(p.conditions or {}) do
        if combinator_wires_selected(c.first_signal_networks , false, entity, network) or
           combinator_wires_selected(c.second_signal_networks, false, entity, network) then
          add_read(
            ((i > 1 and c.compare_type) or "first condition")
              .. (signal_to_rich_text(c.first_signal) or "N/A")
              .. c.comparator
              .. (signal_to_rich_text(c.second_signal)
                  or c.constant
                  or "N/A"),
            Signal_access:new{
              description = "comparison",
              direct_access = {
                combinator_wires_selected(c.first_signal_networks , false, entity, network)
                  and c.first_signal,
                combinator_wires_selected(c.second_signal_networks, false, entity, network)
                  and c.second_signal
              },
              matches = function(self, s)
                return
                  (c.first_signal
                    and combinator_wires_selected(c.first_signal_networks , false, entity, network)
                    and same_signal(s, c.first_signal))
                  or
                  (c.second_signal
                    and combinator_wires_selected(c.second_signal_networks, false, entity, network)
                    and same_signal(s, c.second_signal))
              end
            }
          )
        end
        result.other_out = gather_neighbors(combinator_out)
      end

      if combinator_wires_selected(behavior.output_networks, true, entity, network) then
        for _, o in pairs(p.outputs or {}) do
          add_combinator_output("output ", o.signal, not o.copy_count_from_input and (o.constant or "1"))
        end

        for _, o in pairs(p.else_outputs or {}) do
          add_combinator_output("else ",   o.signal, not o.copy_count_from_input and (o.constant or "1"))
        end
        result.other_in = gather_neighbors(combinator_in)
      end
    end


  elseif t == defines.control_behavior.type.selector_combinator then

    local p = behavior.parameters

    if p and input_ok then

      local operation = p.operation or "select"

      if operation == "select" then

        if p.index_signal then
          add_simple_read("index signal ", p.index_signal)
        end

        -- select operates on arbitrary signals on the input network.
        add_type_read("select ", "item")
        add_read(
          "select input signal",
          Signal_access:new{
            description = "select input signal",
            direct_access = nil,
            matches = function(self, s)
              return true
            end
          }
        )

      elseif operation == "count" then

        add_read(
          "count signals",
          Signal_access:new{
            description = "count input signals",
            direct_access = nil,
            matches = function(self, s)
              return true
            end
          }
        )

      elseif operation == "random" then

        add_read(
          "random input signal",
          Signal_access:new{
            description = "random input signal",
            direct_access = nil,
            matches = function(self, s)
              return true
            end
          }
        )

      elseif operation == "quality-filter" then

        add_read(
          "quality filter",
          Signal_access:new{
            description = "quality filter",
            direct_access = nil,
            matches = function(self, s)
              return true
            end
          }
        )

      elseif operation == "quality-transfer" then

        if p.quality_source_signal then
          add_simple_read(
            "quality source ",
            p.quality_source_signal
          )
        end

        if p.quality_destination_signal then
          add_combinator_output(
            "quality destination ",
            p.quality_destination_signal
          )
        end

      elseif operation == "time" then

        add_write(
          "game/day tick signals",
          {},
          Signal_access:new{
            description = "time signal",
            direct_access = {
              p.game_tick_signal,
              p.day_tick_signal,
              p.day_length_signal
            }
          }
        )

      end
      result.other_out = gather_neighbors(combinator_out)
    end

    if p and output_ok then
      -- The selector combinator has one output whose exact signal depends
      -- on the selected operation/input.
      add_write(
        "selector output",
        current_signals(behavior.signals_last_tick),
        Signal_access:new{
          description = "selector output",
          direct_access = nil,
          matches = function(self, s)
            return true
          end
        }
      )
      result.other_in = gather_neighbors(combinator_in)
    end


  --------------------------------------------------------------------------
  -- CONSTANT COMBINATOR
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.constant_combinator then

    if output_ok then
      local current = {}

      for _, section in pairs(behavior.sections or {}) do
        if section.active then
          for _, filter in pairs(section.filters or {}) do
            if filter.signal and filter.count then
              table.insert(current, {
                signal = filter.signal,
                count = filter.count * (section.multiplier or 1)
              })
            end
          end
        end
      end

      add_write(
        "constant signals",
        current,
        Signal_access:new{
          description = "constant signal",
          direct_access = nil,
          matches = function(self, s)
            for _, section in pairs(behavior.sections or {}) do
              if section.active then
                for _, filter in pairs(section.filters or {}) do
                  if filter.signal and same_signal(filter.signal, s) then
                    return true
                  end
                end
              end
            end
            return false
          end
        }
      )
    end


  --------------------------------------------------------------------------
  -- CONTAINERS
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.container
      or t == defines.control_behavior.type.logistic_container
      or t == defines.control_behavior.type.proxy_container then

    if output_ok and behavior.read_contents then
      local inventory = entity.get_inventory(defines.inventory.chest)
      add_inventory_contents("read contents ", inventory)
    end

    if output_ok and behavior.read_empty_slots then
      add_set(
        "read empty slots ",
        behavior.empty_slots_signal,
        "?"
      )
    end

    if t == defines.control_behavior.type.logistic_container then
      if input_ok and behavior.circuit_condition_enabled then
        add_comparison("enable if ", behavior.circuit_condition)
      end

      if input_ok and behavior.set_requests then
        add_read(
          "set requests",
          Signal_access:new_type_match("any item", "item")
        )
      end
    end


  --------------------------------------------------------------------------
  -- FLUID BOX
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.single_fluid_box then

    if output_ok and behavior.read_temperature then
      local fluid = entity.get_fluid(1)

      add_set(
        "set temperature ",
        behavior.temperature_signal,
        fluid and fluid.temperature or "?"
      )
    end

    if output_ok and behavior.circuit_exclusive_mode_of_operation then
      local fluid = entity.get_fluid(1)

      local current = {}

      if fluid then
        table.insert(current, {
          signal = {
            type = "fluid",
            name = fluid.name
          },
          count = fluid.amount
        })
      end

      add_write(
        fluid
          and ("read fluid, currently "
            .. string.format("%s [fluid=%s]",
              math.ceil(fluid.amount),
              fluid.name))
          or "read fluid, currently empty",
        current,
        Signal_access:new_type_match("any fluid", "fluid")
      )
    end


  --------------------------------------------------------------------------
  -- INSERTER
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.inserter then

    if input_ok and behavior.circuit_set_stack_size then
      add_simple_read(
        "set stack size ",
        behavior.circuit_stack_control_signal
      )
    end

    if input_ok and behavior.circuit_set_filters then
      add_read(
        "set filters",
        Signal_access:new_type_match("any item", "item")
      )
    end

    if output_ok and behavior.circuit_read_hand_contents then

      local hand = entity.held_stack
      local current = {}

      if hand and hand.valid_for_read then
        table.insert(current, {
          signal = {
            type = "item",
            name = hand.name
          },
          count = hand.count
        })
      end

      add_write(
        "read hand contents ",
        current,
        Signal_access:new_type_match("any item", "item")
      )
    end


  --------------------------------------------------------------------------
  -- ACCUMULATOR
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.accumulator then
    local charge= "?"
    if entity.electric_networks and entity.electric_networks[1] then
      charge = entity.electric_networks[1].get_accumulators_energy{}
      charge = charge.energy * 100 / charge.capacity
    end

    if output_ok and behavior.read_charge then
      add_set(
        "read charge ",
        behavior.output_signal,
        charge
      )
    end


  --------------------------------------------------------------------------
  -- BELT
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.transport_belt then

    if output_ok and behavior.read_contents then
      local current = {}

      for _, line in pairs(entity.get_transport_line(1) and {
        entity.get_transport_line(1),
        entity.get_transport_line(2)
      } or {}) do
        if line then
          for _, item in pairs(line.get_contents()) do
            table.insert(current, {
              signal = {
                type = "item",
                name = item.name
              },
              count = item.count
            })
          end
        end
      end

      add_write(
        "read belt contents ",
        current,
        Signal_access:new_type_match("any item", "item")
      )
    end


  --------------------------------------------------------------------------
  -- ASSEMBLING MACHINE
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.assembling_machine then

    if input_ok and behavior.circuit_set_recipe then
      add_read(
        "set recipe",
        Signal_access:new_type_match("any recipe item", "item")
      )
    end

    if output_ok and behavior.circuit_read_contents then
      local inventories = {}

      local input = entity.get_inventory(defines.inventory.crafter_input)
      local output = entity.get_inventory(defines.inventory.crafter_output)

      if input then table.insert(inventories, input) end
      if output then table.insert(inventories, output) end

      add_inventories(
        "read contents ",
        inventories
      )
    end

    if output_ok and behavior.read_fuel then
      local fuel = entity.get_inventory(defines.inventory.fuel)
      add_inventory_contents("read fuel ", fuel)
    end

    if output_ok and behavior.circuit_read_ingredients then
      add_read(
        "read recipe ingredients",
        Signal_access:write_item_or_fluid("recipe ingredients")
      )
    end

    if output_ok and behavior.circuit_read_recipe_finished then
      add_set(
        "recipe finished ",
        behavior.circuit_recipe_finished_signal,
        "?"
      )
    end

    if output_ok and behavior.circuit_read_working then
      add_set(
        "working ",
        behavior.circuit_working_signal,
        "?"
      )
    end


  --------------------------------------------------------------------------
  -- FURNACE
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.furnace then

    if output_ok and behavior.circuit_read_contents then
      local inventories = {}

      local input = entity.get_inventory(defines.inventory.crafter_input)
      local output = entity.get_inventory(defines.inventory.crafter_output)

      if input then table.insert(inventories, input) end
      if output then table.insert(inventories, output) end
      --if behavior.include_in_crafting and entity.get_inventory(defines.inventory.) then
      --  table.insert(inventories, entity.get_inventory(defines.inventory.))
      --end -- TODO, also for assembling_machine
      add_inventories("read contents ", inventories)
    end

    if output_ok and behavior.read_fuel then
      add_inventory_contents(
        "read fuel ",
        entity.get_inventory(defines.inventory.fuel)
      )
    end

    if output_ok and behavior.circuit_read_ingredients then
      add_read(
        "read recipe ingredients",
        Signal_access:new_type_match("recipe ingredients", "item")
      )
    end

    if output_ok and behavior.circuit_read_recipe_finished then
      add_set(
        "recipe finished ",
        behavior.circuit_recipe_finished_signal,
        "?"
      )
    end

    if output_ok and behavior.circuit_read_working then
      add_set(
        "working ",
        behavior.circuit_working_signal,
        "?"
      )
    end


  --------------------------------------------------------------------------
  -- MINING DRILL
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.mining_drill then

    if output_ok and behavior.circuit_read_resources then

      local current = {}

      for _, resource in pairs(behavior.resource_read_targets or {}) do
        if resource.valid then
          table.insert(current, {
            signal = {
              type = "item",
              name = resource.name
            },
            count = resource.amount
          })
        end
      end

      add_write(
        "read resources ",
        current,
        Signal_access:new_type_match("any resource", "item")
      )
    end


  --------------------------------------------------------------------------
  -- LAB
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.lab then

    if output_ok and behavior.read_contents then
      add_inventories(
        "read contents ",
        {
          entity.get_inventory(defines.inventory.lab_input)
        }
      )
    end

    if output_ok and behavior.read_fuel then
      add_inventory_contents(
        "read fuel ",
        entity.get_inventory(defines.inventory.fuel)
      )
    end

    if output_ok and behavior.read_technology_level then
      add_set(
        "technology level ",
        behavior.technology_level_signal,
        "?"
      )
    end

    if input_ok and behavior.set_research then
      for _, research_condition in ipairs(behavior.research_conditions or {}) do
        add_comparison("research " .. (research_condition.name or "N/A") .. " when", research_condition.condition)
      end
    end


  --------------------------------------------------------------------------
  -- ROBOport
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.roboport then

    if output_ok and behavior.read_robot_stats then
      add_set(
        "available logistic robots ",
        behavior.available_logistic_output_signal,
        "?"
      )

      add_set(
        "total logistic robots ",
        behavior.total_logistic_output_signal,
        "?"
      )

      add_set(
        "available construction robots ",
        behavior.available_construction_output_signal,
        "?"
      )

      add_set(
        "total construction robots ",
        behavior.total_construction_output_signal,
        "?"
      )

      add_set(
        "roboport count ",
        behavior.roboport_count_output_signal,
        "?"
      )
    end

    if output_ok and behavior.read_items_mode then
      -- TODO read real logistic network contents?
      add_type_read("read roboport contents ", "item", {})
    end


  --------------------------------------------------------------------------
  -- TRAIN STOP
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.train_stop then

    if input_ok and behavior.send_to_train then
      add_read(
        "send signals to train",
        Signal_access:new{
          description = "train schedule signals",
          direct_access = nil,
          matches = function(self, s)
            return true
          end
        }
      )
    end

    if output_ok and behavior.read_from_train then
      add_write(
        "read train contents",
        {},
        Signal_access:write_item_or_fluid("recipe ingredients")
      )
    end

    if output_ok and behavior.read_stopped_train then
      add_set(
        "stopped train ",
        behavior.stopped_train_signal,
        "?"
      )
    end

    if output_ok and behavior.read_trains_count then
      add_set(
        "trains count ",
        behavior.trains_count_signal,
        "?"
      )
    end

    if input_ok and behavior.set_trains_limit then
      add_simple_read(
        "set train limit ",
        behavior.trains_limit_signal
      )
    end

    if input_ok and behavior.set_priority then
      add_simple_read(
        "set priority ",
        behavior.priority_signal
      )
    end


  --------------------------------------------------------------------------
  -- RAIL SIGNAL
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.rail_signal
      or t == defines.control_behavior.type.rail_chain_signal then

    if input_ok and behavior.close_signal then
      add_comparison("close if ", behavior.circuit_condition)
    end

    if output_ok and behavior.read_signal then
      add_set("red signal ", behavior.red_signal, "?")
      add_set("orange signal ", behavior.orange_signal, "?")
      add_set("green signal ", behavior.green_signal, "?")
      if t == defines.control_behavior.type.rail_chain_signal then
        add_set("blue signal ", behavior.blue_signal, "?")
      end
    end


  --------------------------------------------------------------------------
  -- LAMP
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.lamp then

    if input_ok and behavior.use_colors then
      add_read(
        "set color",
        Signal_access:new{
          description = "lamp color signals",
          direct_access = {
            behavior.red_signal,
            behavior.green_signal,
            behavior.blue_signal,
            behavior.rgb_signal
          }
        }
      )
    end


  --------------------------------------------------------------------------
  -- RADAR
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.radar then

    if input_ok and behavior.universe_channel then
      add_simple_read(
        "universe channel ",
        behavior.universe_channel -- TODO wrong
      )
    end


  --------------------------------------------------------------------------
  -- ROCKET SILO
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.rocket_silo then

    if output_ok then
      if behavior.read_mode == defines.control_behavior.rocket_silo.read_mode.logistic_inventory then
        add_inventory_contents(
          "read logistic inventory ",
          entity.get_inventory(defines.inventory.rocket_silo_rocket)
        )
      elseif behavior.read_mode == defines.control_behavior.rocket_silo.read_mode.orbital_requests then
        add_write(
          "read orbital requests ",
          {},
          Signal_access:new_type_match("any item", "item")
        )
      end

      if output_ok and behavior.read_launched then
        add_set(
          "rocket launched ",
          behavior.launched_signal,
          "?"
        )
      end

    end


  --------------------------------------------------------------------------
  -- BOILER
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.boiler then

    if output_ok and behavior.read_fuel then
      add_inventory_contents(
        "read fuel ",
        entity.get_inventory(defines.inventory.fuel)
      )
    end


  --------------------------------------------------------------------------
  -- ASTEROID COLLECTOR
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.asteroid_collector then

    if output_ok and behavior.read_content then
      add_inventory_contents(
        "read contents ",
        entity.get_inventory(defines.inventory.asteroid_collector_output)
        -- TODO add defines.inventory.asteroid_collector_arm if arm included
      )
    end

    if output_ok and behavior.include_hands then
      add_write(
        "read captured asteroids ",
        {},
        Signal_access:new_type_match("any item", "item")
      )
    end

    if input_ok and behavior.set_filter then
      add_read(
        "set asteroid filter",
        Signal_access:new_type_match("any asteroid", "item")
      )
    end


  --------------------------------------------------------------------------
  -- CARGO LANDING PAD
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.cargo_landing_pad  then

    if output_ok and behavior.read_contents then
      add_inventory_contents(
        "read contents ",
        entity.get_inventory(defines.inventory.hub_main)
      )
    end

    if output_ok and behavior.read_empty_slots then
      add_set(
        "read empty slots ",
        behavior.empty_slots_signal,
        "?"
      )
    end

    if input_ok and behavior.set_requests then
      add_read(
        "set requests",
        Signal_access:new_type_match("any item", "item")
      )
    end


  --------------------------------------------------------------------------
  -- AGRICULTURAL TOWER
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.agricultural_tower then

    if output_ok and behavior.read_contents then
      add_inventories(
        "read contents ",
        { entity.get_inventory(defines.inventory.agricultural_tower_input),
          entity.get_inventory(defines.inventory.agricultural_tower_output) }
      )
    end

    if input_ok and behavior.enable_harvesting_condition then
      add_comparison(
        "harvest if ",
        behavior.harvesting_condition
      )
    end

    if input_ok and behavior.enable_planting_condition then
      add_comparison(
        "plant if ",
        behavior.planting_condition
      )
    end


  --------------------------------------------------------------------------
  -- LOADER
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.loader then

    if input_ok and behavior.circuit_set_filters then
      add_read(
        "set loader filters",
        Signal_access:new_type_match("any item", "item")
      )
    end

    if output_ok and behavior.circuit_read_transfers then
      add_write(
        "read transfers",
        {},
        Signal_access:new_type_match("any item", "item")
      )
    end


  --------------------------------------------------------------------------
  -- SPLITTER
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.splitter then

    if input_ok then
      if behavior.set_input_side then
        add_comparison(
          "set input side if ",
          behavior.input_left_condition
        )
        add_comparison(
          "set input side if ",
          behavior.input_right_condition
        )
      end

      if behavior.set_output_side then
        add_comparison(
          "set output side if ",
          behavior.output_left_condition
        )
        add_comparison(
          "set output side if ",
          behavior.output_right_condition
        )
      end

      if behavior.set_filter then
        add_read(
          "set splitter filter",
          Signal_access:new_type_match("any item", "item")
        )
      end
    end


  --------------------------------------------------------------------------
  -- PUMP
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.pump then

    if input_ok and behavior.set_filter then
      add_read(
        "set fluid filter",
        Signal_access:new_type_match("any fluid", "fluid")
      )
    end


  --------------------------------------------------------------------------
  -- ARTILLERY TURRET
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.artillery_turret then

    -- The artillery turret has only the generic enable/disable behavior.
    -- That was handled above.


  --------------------------------------------------------------------------
  -- TURRET
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.turret then
    if input_ok then
      if behavior.set_ignore_unlisted_targets then
        add_comparison(
          "ignore unlisted targets condition: ",
          behavior.ignore_unlisted_targets_condition
        )
      end

      if behavior.set_priority_list then
        add_read("target priority list: ",
          Signal_access:new{
            description = "enemy target signals",
            matches = function(self, s)
              return s.type == "entity" -- TODO heuristic for PvE, include biters and asteroids. In PvP, can be tank, player, turret etc.
            end
        })
      end
    end

    if output_ok and behavior.read_ammo then
      add_write("ammunition contents: ", {},
        Signal_access:new_type_match("item ammunition", "item")
        --,Signal_access:new_type_match("fluid ammunition", "fluid") -- TODO
      )
    end
  --------------------------------------------------------------------------
  -- LAND MINE
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.land_mine then

    -- Generic enable/disable behavior only.


  --------------------------------------------------------------------------
  -- WALL
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.wall then
    if input_ok and behavior.open_gate then
      add_comparison("open gate condition: ", behavior.circuit_condition)
    end

    if output_ok and behavior.read_sensor and behavior.output_signal then
      add_set("gate proximity sensor: ",behavior.output_signal,"?")
    end

  --------------------------------------------------------------------------
  -- REACTOR
  --------------------------------------------------------------------------

elseif t == defines.control_behavior.type.reactor then
    if output_ok then
      if behavior.read_temperature and behavior.temperature_signal then
        add_set("reactor temperature: ", behavior.temperature_signal, entity.temperature)
      end

      if behavior.read_fuel then
        add_inventory_contents("reactor fuel", entity.get_fuel_inventory())
      end
    end
  --------------------------------------------------------------------------
  -- HEAT PIPE
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.heat_pipe then
    if output_ok then
      if behavior.read_temperature and behavior.temperature_signal then
        add_set("reactor temperature: ", behavior.temperature_signal, entity.temperature)
      end
    end

  --------------------------------------------------------------------------
  -- DISPLAY PANEL
  --------------------------------------------------------------------------

elseif t == defines.control_behavior.type.display_panel then
    if input_ok and behavior.records then
      for _, record in pairs(behavior.records) do
        if record.condition then
          add_comparison(
            (signal_to_rich_text(record.icon) or "no icon") .. " message: " .. (record.text or "not set") .. " condition: ",
            record.condition
          )
        end
      end
    end
  --------------------------------------------------------------------------
  -- PROGRAMMABLE SPEAKER
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.programmable_speaker then

    if input_ok then
      add_comparison(
        "play if ",
        behavior.circuit_condition
      )
    end


  --------------------------------------------------------------------------
  -- SPACE PLATFORM HUB
  --------------------------------------------------------------------------

  elseif t == defines.control_behavior.type.space_platform_hub then

    if output_ok and behavior.read_contents then
      add_inventory_contents(
        "read platform contents ",
        entity.get_inventory(defines.inventory.hub_main)
      )
    end

    if output_ok and behavior.read_empty_slots then
      add_set(
        "read empty slots ",
        behavior.empty_slots_signal,
        "?"
      )
    end

    if input_ok and behavior.set_requests then
      add_read(
        "set platform requests",
        nil,
        Signal_access:new_type_match("any item", "item")
      )
    end

    if input_ok and behavior.send_to_platform then
      add_read(
        "send signals to platform schedule",
        Signal_access:new{
          description = "platform schedule signals",
          direct_access = nil,
          matches = function(self, s)
            return true
          end
        }
      )
    end

    if output_ok and behavior.read_moving_from then
      add_write(
        "read moving-from connection",
        {},
        Signal_access:new_type_match("platform connection signal","space-location")
      )
    end

    if output_ok and behavior.read_moving_to then
      add_write(
        "read moving-to connection",
        {},
        Signal_access:new_type_match("platform connection signal","space-location")
      )
    end
  end

  return result
end
