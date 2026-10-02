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

## TODOs:
* rewrite section above, chatGPT output is obsolete
* handle combinators with their 2 connection points better
* some entities might be missing, e.g. labs
* output the usage of the signals
* filter by signal

### conceptual
* clearer distinction between current signals, potential outputs (decider) and dynamic outputs
* the entity list should contain the actual accesses, like "enable if [V] < 150"
