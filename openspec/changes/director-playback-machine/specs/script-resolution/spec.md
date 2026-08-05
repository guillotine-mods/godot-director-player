## ADDED Requirements

### Requirement: Handler tables are scoped to the movie that owns them

The runtime SHALL maintain movie-script handler tables per loaded movie, built from that movie's own cast
libraries. Resolution of a handler SHALL consider only the current movie's table, then a single shared
archive. A handler defined in another movie MUST NOT be reachable.

#### Scenario: A duplicated handler name resolves within its own movie

- **WHEN** two movies each define a movie-script handler with the same name and the second movie is current
- **THEN** the second movie's definition is invoked

#### Scenario: The shared archive is consulted after the movie's own casts

- **WHEN** a handler name exists in both the current movie's casts and the shared archive
- **THEN** the current movie's definition is invoked

#### Scenario: An unreachable handler is reported

- **WHEN** a handler name exists in no loaded table
- **THEN** the runtime raises a located diagnostic rather than silently doing nothing

### Requirement: Handler tables are rebuilt on movie change

On loading a movie the runtime SHALL discard the previous movie's handler table and build the new movie's
table before dispatching any event in it.

#### Scenario: The previous movie's handlers do not persist

- **WHEN** a movie is loaded after another movie whose table contained a handler name absent from the new one
- **THEN** that name does not resolve in the new movie

#### Scenario: Order of loading does not affect resolution

- **WHEN** the same movie is entered from two different predecessors
- **THEN** handler resolution within it is identical in both cases

### Requirement: Mouse events resolve through an ordered source-type chain

A mouse event SHALL be queued as one entry per source type, in the order: sprite behaviour, cast member
script, frame script, movie script. Each entry's target script SHALL be resolved when the entry is
dispatched, not when it is queued.

#### Scenario: Resolution order is honoured

- **WHEN** a channel carries a behaviour that handles the event and its cast member also defines a handler
- **THEN** the behaviour runs first

#### Scenario: Late resolution reflects state changed mid-chain

- **WHEN** an earlier entry in the chain changes which cast member a channel displays
- **THEN** a later entry resolving against the channel sees the change

#### Scenario: A click with no channel beneath it skips sprite and cast levels

- **WHEN** a mouse event occurs where no channel is hit
- **THEN** the chain begins at the frame script

### Requirement: Event propagation stops unless the handler passes

After a handler in the chain runs, the runtime SHALL discard remaining entries for the same event unless the
handler explicitly passed the event. A handler calling the pass command SHALL allow the chain to continue,
and a handler calling the do-not-pass command SHALL stop it.

#### Scenario: A handler that does not pass ends the chain

- **WHEN** the cast member script handles a click and does not pass
- **THEN** the frame script and movie script entries for that event do not run

#### Scenario: A handler that passes continues the chain

- **WHEN** a handler calls the pass command
- **THEN** the next source-type entry for that event runs

### Requirement: Frame events resolve to the frame script then the movie script

Frame entry and frame exit events SHALL be queued for the frame script named by the score's script channel
and then for movie scripts. They MUST NOT be queued per sprite behaviour.

#### Scenario: A frame handler on the score's script channel runs

- **WHEN** the current frame's script channel names a script defining a frame-exit handler
- **THEN** that handler runs on frame exit

#### Scenario: With no frame script the movie script receives the event

- **WHEN** the current frame's script channel names no script
- **THEN** the frame event is dispatched to movie scripts

#### Scenario: Sprite behaviours do not receive frame events

- **WHEN** a channel's behaviour defines a frame-exit handler and the frame's script channel names a
  different script
- **THEN** only the frame script's handler runs

### Requirement: A dispatch that resolves to no handler is distinguishable from one that did nothing

The runtime SHALL report whether a dispatch invoked a handler. Callers deciding whether to fall back to
other behaviour SHALL use that result rather than testing whether a handler exists.

#### Scenario: A generic handler that takes a dead branch still counts as dispatched

- **WHEN** a channel's cast member defines a handler that runs but takes no effective action
- **THEN** the dispatch is reported as having invoked a handler
- **AND** no fallback path is taken on the grounds that no handler existed

### Requirement: Key input dispatches through the key-down script indirection

The runtime SHALL support setting and reading a property naming a handler to receive key input, and on a key
event SHALL invoke the named handler if one is set.

#### Scenario: Setting and invoking

- **WHEN** a script sets the key-down script property to a handler name and a key event occurs
- **THEN** that handler is invoked

#### Scenario: The property is readable

- **WHEN** a script compares the key-down script property against a name
- **THEN** the comparison reflects the value currently set

#### Scenario: No handler set

- **WHEN** a key event occurs with the property unset
- **THEN** no handler is invoked and no diagnostic is raised
