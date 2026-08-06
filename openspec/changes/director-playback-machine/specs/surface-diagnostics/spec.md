## ADDED Requirements

### Requirement: Bound surface is enumerated from a recorded vocabulary, not from observed usage

For each of sprite properties, movie properties, member properties and builtin calls, the runtime SHALL
bind every name in a recorded vocabulary of the language, and coverage SHALL be determined by comparing the
bound tables against that vocabulary rather than by surveying which names scripts happen to use. The
vocabulary SHALL be generated rather than hand-maintained, and SHALL record for each name the source it was
enumerated from.

The vocabulary cannot come from the AST compiler. `tools/lingo_compile.py` closes nothing: its
`SYSTEM_PROPS` table is referenced by no code, `parse_the` gates only on `RESERVED_AFTER_PROP` and
`THE_ADJECTIVES` so any word parses as a property name, and `sprite_prop`/`member_prop` accept any
identifier. Three of the four categories have no compiler-side closure at all. A requirement to "bind every
name the compiler can produce" would therefore be unsatisfiable, since the compiler can produce any
identifier.

#### Scenario: Coverage is reported against the recorded vocabulary

- **WHEN** the coverage check runs
- **THEN** it reports, per category, which names the vocabulary enumerates and which of those are bound
- **AND** a name in the vocabulary that is unbound is reported as a gap

#### Scenario: A gap is reported even when no script uses the name

- **WHEN** the vocabulary enumerates a name that no script in the corpus uses and the runtime does not bind
  it
- **THEN** the check still reports it as a gap

#### Scenario: Reads and writes are separate surfaces

- **WHEN** the coverage check compares bound tables against the vocabulary
- **THEN** it reports read binding and write binding independently, so a name writable but not readable is
  reported as a gap on the read side

#### Scenario: A bound name outside the vocabulary is reported

- **WHEN** the runtime binds a name the vocabulary does not enumerate
- **THEN** the check reports it, so a binding invented by the port cannot pass unnoticed

### Requirement: Unbound surface raises a located diagnostic and never returns a default

When a script accesses a property, calls a builtin, or dispatches an event that the runtime does not bind,
the runtime SHALL raise a diagnostic identifying the name, the category, and the script and handler in which
it occurred. It MUST NOT substitute a default value such as 0 or an empty string.

#### Scenario: An unbound property read is reported

- **WHEN** a handler reads a property the runtime does not bind
- **THEN** a diagnostic naming the property, the script and the handler is raised

#### Scenario: An unbound builtin call is reported

- **WHEN** a handler calls a builtin the runtime does not bind
- **THEN** a diagnostic naming it is raised
- **AND** the call does not silently return a value

#### Scenario: A bound property whose value is genuinely empty is not a diagnostic

- **WHEN** a handler reads a bound property whose current value is empty or zero
- **THEN** no diagnostic is raised

### Requirement: An unset variable is distinguishable from an unbound name

The runtime SHALL classify a read of an uninitialised local or global as an unset variable, not as an
unbound name, and SHALL keep the two categories separate in diagnostics.

#### Scenario: Reading an uninitialised local

- **WHEN** a handler reads a local variable it has not assigned, because a conditional branch was not taken
- **THEN** the read is reported as an unset variable if reported at all
- **AND** it does not appear in the unbound-name list

### Requirement: Diagnostics are deduplicated, counted and machine-readable

The runtime SHALL deduplicate diagnostics by name and location, SHALL count occurrences, and SHALL emit them
in a form a harness can compare between runs.

#### Scenario: A repeated diagnostic appears once with a count

- **WHEN** the same unbound name is accessed from the same location many times
- **THEN** the output contains one entry carrying the occurrence count

#### Scenario: Two runs are comparable

- **WHEN** the same session is replayed after a change
- **THEN** the diagnostic sets can be diffed to show which entries were added or removed

### Requirement: Deliberate divergences from the reference implementation are declared

Where the port intentionally behaves differently from the reference Director implementation, the divergence
SHALL be declared alongside the binding, with the evidence that motivated it. A declared divergence MUST NOT
be reported as a failure by comparison harnesses.

#### Scenario: A declared divergence is not a failure

- **WHEN** a comparison against the reference implementation finds a difference matching a declared
  divergence
- **THEN** the harness reports it as expected

#### Scenario: An undeclared difference is a failure

- **WHEN** a comparison finds a difference that is not declared
- **THEN** the harness reports it as a failure

### Requirement: The reference implementation is pinned, not tracked

The reference implementation used for citation SHALL be fetched at a pinned revision recorded in the
repository. Citations SHALL identify file and function.

#### Scenario: Fetching the reference

- **WHEN** the reference fetch is run
- **THEN** it retrieves the recorded revision, not the latest

#### Scenario: A citation identifies its target

- **WHEN** a binding cites the reference implementation
- **THEN** the citation names the file and function, and the pinned revision applies

### Requirement: Runtime state can be exported for comparison against the reference

The runtime SHALL be able to emit, per playback step, a machine-readable record of channel state, dispatch
decisions and property accesses, sufficient to compare against equivalent traces from the reference
implementation.

#### Scenario: Channel state export

- **WHEN** trace export is enabled and a playback step completes
- **THEN** the record contains, for each occupied channel, its member, location, dimensions, ink,
  visibility and ownership state

#### Scenario: Dispatch export

- **WHEN** trace export is enabled and an event is dispatched
- **THEN** the record contains the event, the source type, the resolved script identity and the channel

#### Scenario: Property access export

- **WHEN** trace export is enabled and a property is read or written
- **THEN** the record contains the property name, the target, the direction and the value

#### Scenario: Export is off by default

- **WHEN** trace export is not enabled
- **THEN** no trace records are produced and playback is unaffected
