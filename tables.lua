
Entity_type_to_gui_type = {
    -- Produktions- & Verarbeitungsmaschinen
    ["assembling-machine"]       = defines.relative_gui_type.assembling_machine_gui,
    ["furnace"]                  = defines.relative_gui_type.furnace_gui,
    ["rocket-silo"]              = defines.relative_gui_type.rocket_silo_gui,
    ["mining-drill"]             = defines.relative_gui_type.mining_drill_gui,
    ["lab"]                      = defines.relative_gui_type.lab_gui,
    ["beacon"]                   = defines.relative_gui_type.beacon_gui,

    ["inserter"]                 = defines.relative_gui_type.inserter_gui,
    ["fast-inserter"]            = defines.relative_gui_type.inserter_gui,

    -- Lagerung, Logistik & Inventare
    ["container"]                = defines.relative_gui_type.item_with_inventory_gui,
    ["logistic-container"]       = defines.relative_gui_type.item_with_inventory_gui,
    ["car"]                      = defines.relative_gui_type.item_with_inventory_gui,
    ["cargo-wagon"]              = defines.relative_gui_type.item_with_inventory_gui,
    ["fluid-wagon"]              = defines.relative_gui_type.item_with_inventory_gui,
    ["artillery-wagon"]          = defines.relative_gui_type.item_with_inventory_gui,
    ["spidertron-remote"]        = defines.relative_gui_type.item_with_inventory_gui, -- Falls als Entity geöffnet
    ["spider-vehicle"]           = defines.relative_gui_type.item_with_inventory_gui,

    -- Strom & Energie
    ["accumulator"]              = defines.relative_gui_type.accumulator_gui,
    ["generator"]                = defines.relative_gui_type.generator_gui,
    ["solar-panel"]              = defines.relative_gui_type.solar_panel_gui,
    ["reactor"]                  = defines.relative_gui_type.reactor_gui,
    ["electric-energy-interface"] = defines.relative_gui_type.electric_energy_interface_gui,
    ["electric-pole"]            = defines.relative_gui_type.electric_energy_interface_gui,

    -- Schaltung & Logik (Combinators)
    ["constant-combinator"]      = defines.relative_gui_type.constant_combinator_gui,
    ["arithmetic-combinator"]    = defines.relative_gui_type.arithmetic_combinator_gui,
    ["decider-combinator"]       = defines.relative_gui_type.decider_combinator_gui,
    ["selector-combinator"]       = defines.relative_gui_type.selector_combinator_gui,
    ["programmable-speaker"]     = defines.relative_gui_type.programmable_speaker_gui,
    ["power-switch"]             = defines.relative_gui_type.power_switch_gui,
    ["lamp"]                     = defines.relative_gui_type.lamp_gui,

    -- Verteidigung & Kampf
    ["ammo-turret"]              = defines.relative_gui_type.turret_gui,
    ["electric-turret"]          = defines.relative_gui_type.turret_gui,
    ["fluid-turret"]             = defines.relative_gui_type.turret_gui,
    ["artillery-turret"]         = defines.relative_gui_type.artillery_turret_gui,
    ["radar"]                    = defines.relative_gui_type.radar_gui,

    -- Zuginfrastruktur
    ["train-stop"]               = defines.relative_gui_type.train_stop_gui,
    ["locomotive"]               = defines.relative_gui_type.locomotive_gui,
    ["rail-signal"]              = defines.relative_gui_type.rail_signal_gui,
    ["rail-chain-signal"]        = defines.relative_gui_type.rail_chain_signal_gui,

    -- Flüssigkeiten & Rohre
    ["storage-tank"]             = defines.relative_gui_type.pipe_gui,
    ["pump"]                     = defines.relative_gui_type.pump_gui,

    -- space
    ["space-platform-hub"]       = defines.relative_gui_type.space_platform_hub_gui,
    ["asteroid-collector"]       = defines.relative_gui_type.asteroid_collector_gui,

    -- Sonstiges & Spezielle GUIs
    ["roboport"]                 = defines.relative_gui_type.roboport_gui,
    ["splitter"]                 = defines.relative_gui_type.splitter_gui,
    ["transport-belt"]           = defines.relative_gui_type.transport_belt_gui,
    ["underground-belt"]         = defines.relative_gui_type.transport_belt_gui,
    ["loader"]                   = defines.relative_gui_type.loader_gui,
    ["loader-1x1"]               = defines.relative_gui_type.loader_gui,
    ["market"]                   = defines.relative_gui_type.market_gui,
    ["infinity-container"]       = defines.relative_gui_type.infinity_container_gui,
    ["infinity-pipe"]            = defines.relative_gui_type.infinity_pipe_gui,
    ["heat-interface"]           = defines.relative_gui_type.heat_interface_gui

}
