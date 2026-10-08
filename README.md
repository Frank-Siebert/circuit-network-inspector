# Circuit Network Inspector

Minimal Factorio 2.1 mod.

Open an entity GUI that has circuit connections. The mod adds a small `ⓘ`
button next to Factorio's additional-entity-info area. Clicking it opens a
circuit-network inspector.

The inspector has:

* left panel: current network signals and `∀ All signals`
* right panel: writers and readers
* clicking a signal filters the entity list
* clicking an entity selects it and opens its normal entity GUI

This is intentionally a first/minimal implementation. The signal-access
recognition is based on the public Factorio 2.1 control-behavior API and
covers the common vanilla behaviors; dynamic signal producers are represented
conservatively.

The mod currently inspects the first circuit network found on the source
entity. If an entity is connected to several independent red/green networks,
a later version should expose network selection explicitly.

## Acknowledgements:

Display of the current circuit network taken from https://github.com/JasonLandbridge/CircuitHUD-V2/, mostly https://github.com/JasonLandbridge/CircuitHUD-V2/blob/master/gui/hud-gui.lua


## TODOs:

### conceptual TODOs
* how to handle mods with new entities or new control behavior?

### normal work
* if a decider output (write) says "input count", that also qualifies as read!
* some entities might be missing, e.g. labs
* the entity list should contain the actual accesses, like "enable if [V] < 150", more of it. do for everything or let AI do it.
* improve gui for list of entities
* actually show the current signals in access list (done for left panel)
* click into list of current values for filter?

### for publishing
* remove game.print, player.print (except one case as commented)
* rewrite top section above, chatGPT output is obsolete
* add screenshot
* better info.json


Yes. Looking back at the implementation I gave you, there are several shortcomings beyond the rocket silo. The biggest problem is that I presented it as a comprehensive implementation without verifying every behavior against the Factorio 2.1.21 API.

I would distinguish three kinds of problems:

* Incorrect API assumptions: fields, enum values, or inventory identifiers may not exist as written.

* Incorrect access semantics: the code may identify a signal as readable or writable when the behavior actually works differently.

* Incomplete current-write tracking: the code reports a configured or potential output as though it were the actual contribution, or uses `"?"` instead of determining the current value.

Here are the concrete issues I can identify from the code itself. This is a code review, not a claim that I have verified every item against the current API documentation.

## Shortcomings by behavior

| Behavior                                                      | Problem in the implementation                                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Selector combinator                                           | The operation handling is speculative and incomplete. It incorrectly treats arbitrary inputs as `item` signals in one branch, and the `time`, quality and other operation semantics are not properly modelled.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio<br>+1                     |
| Constant combinator                                           | The code assumes every section has `active`, `filters` and `multiplier` fields. The documented API uses `LuaLogisticSection`; those fields and the current contribution calculation need verification.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                   |
| Arithmetic combinator                                         | The output helper adds the entire `signals_last_tick` list for each configured output, potentially duplicating contributions. It also assumes the configured output signal fully describes the potential output, which is not true for every operation.                                                                                    |
| Decider combinator                                            | Similar duplication of the actual output list. The potential output model also needs to account for special output signals and the relationship between conditions and outputs.                                                                                                                                                            |
| Accumulator                                                   | `entity.energy / entity.electric_buffer_size` is a plausible charge percentage calculation, but I did not verify that it exactly matches the game's reported signal semantics.                                                                                                                                                             |
| Container / logistic container / proxy container              | `defines.inventory.chest` is assumed to apply to all three. Logistic requests are treated as generic item reads, but their actual filtering semantics aren't modelled.                                                                                                                                                                     |
| Fluid box                                                     | The `nil` fluid case is fixed, but the current contribution for fluid contents and temperature needs verification against actual signal behavior and units.                                                                                                                                                                                |
| Inserter                                                      | `circuit_hand_read_mode` is ignored, so pulse and hold behavior are not distinguished. The implementation also needs to verify how circuit-controlled filters are represented.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                           |
| Transport belt                                                | `read_contents_mode` is ignored. In particular, pulse mode and hold modes cannot be represented as the same current-write contribution.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                                                                  |
| Mining drill                                                  | `resource_read_mode` is ignored, so the implementation does not distinguish resources in the drill's area from resources in the entire field.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                                                            |
| Roboport                                                      | `read_items_mode` is ignored. The code treats the output as generic items rather than distinguishing logistics contents from missing requests; robot-stat signals also need their actual current values.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                 |
| Rocket silo                                                   | The previous implementation guessed the inventory identifier and did not implement orbital requests correctly. The separate `read_launched` setting is also represented as a current write of `"?"`, which is not an actual value.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio<br>+1 |
| Train stop                                                    | `read_from_train` uses `{}` as its current contribution, so it doesn't report actual train contents. The send-to-train behavior is treated as matching every signal without explaining the relevant schedule semantics.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                  |
| Splitter                                                      | The filter configuration is treated as a generic item access. The conditions for input/output side selection need to be associated with the corresponding settings, and filter behavior needs more precise modelling.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                    |
| Agricultural tower                                            | The inventory identifier is clearly wrong: it reuses `defines.inventory.asteroid_collector`. Also, the code needs to check the tower's actual contents and the conditions it uses.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                       |
| Asteroid collector                                            | `include_hands` is nested under the wrong conceptual check: it affects what gets included in `read_content`, rather than being an independent output mode.                                                                                                                                                                                 |
| Assembling machine / furnace / lab                            | Several fields and inventory identifiers were guessed rather than verified. The code also omits or approximates important outputs, including recipe state and working state.                                                                                                                                                               |
| Cargo landing pad                                             | The behavior was omitted entirely, despite having `read_contents`, `read_empty_slots`, `empty_slots_signal`, and `set_requests`.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                                                                         |
| Reactor                                                       | The behavior was omitted entirely. It appears in the official behavior hierarchy and needs its own review.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                                                                                               |
| Pump                                                          | The code assumes a generic fluid filter access but does not verify the filter's exact signal matching behavior.<br>![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)<br>Factorio                                                                                                                          |
| Rail signals / programmable speaker / radar / loader / boiler | The branches contain guessed or incomplete fields, or fail to distinguish the configured input signals from the actual resulting behavior. They need API-by-API verification.                                                                                                                                                              |

## The more fundamental problem

Your model distinguishes three things:

1. Potential access: which signals a behavior can read or write.

2. Current contribution: what that particular entity is actually contributing to the circuit network right now.

3. Configured behavior: what its settings tell it to do, regardless of whether that produces a signal at this moment.

My implementation repeatedly conflated these. For example, a configured output signal is not necessarily an actual write, and a `read_contents` setting does not tell us the contents without inspecting the entity's state.

The API's behavior hierarchy also includes additional behavior classes beyond those I implemented.

![](https://www.google.com/s2/favicons?domain=https://lua-api.factorio.com\&sz=32)

Factorio

+1

My recommendation: don't patch these one at a time on top of the previous implementation. Keep your `Signal_access` abstraction, but redo the behavior branches against the exact 2.1.21 API, checking each field and its semantics. Mark any access whose current contribution cannot be determined reliably as unknown rather than inventing a value.
