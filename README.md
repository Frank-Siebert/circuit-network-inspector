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
* top gui thing for  search_current_write vs search_potential_writes. And count forall/... as match.

### normal work
* handle combinators with their 2 connection points better
* some entities might be missing, e.g. labs
* the entity list should contain the actual accesses, like "enable if [V] < 150", more of it. do for everything or let AI do it.
* improve gui for list of entities
* actually show the current signals

### for publishing
* remove game.print, player.print (except one case as commented)
* rewrite top section above, chatGPT output is obsolete
* add screenshot
* better info.json
