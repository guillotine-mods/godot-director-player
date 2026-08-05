## ADDED Requirements

### Requirement: Live channel state backs every sprite property access

The runtime SHALL maintain a mutable per-channel record holding the current state of each sprite channel.
All sprite property reads and writes SHALL resolve against that record. The renderer SHALL draw from
channel records and MUST NOT read the score's frame sprite data directly.

#### Scenario: A property write reaches the screen

- **WHEN** a handler assigns `the memberNum of sprite 30`
- **THEN** the channel record for 30 holds the new member
- **AND** the next composite draws that member, without the score frame data being consulted

#### Scenario: A property write is readable back

- **WHEN** a handler assigns `the locH of sprite 30` and later reads `the locH of sprite 30`
- **THEN** the value read is the value written, not the score's value for the current frame

#### Scenario: No write is discarded

- **WHEN** any sprite property in the property table is assigned
- **THEN** the write lands in channel state
- **AND** no write path exists that stores a value nothing reads

### Requirement: Channel-only fields have no score counterpart

Channel records SHALL carry fields the score does not supply: visibility, cursor, movement constraint and
film loop position. These fields SHALL persist across frame changes and MUST NOT be reset by score data
application.

#### Scenario: Channel-only field survives a frame change

- **WHEN** a channel's cursor is set and the playhead then moves to another frame
- **THEN** the channel still carries that cursor

### Requirement: Score data is applied as a delta

On a frame change the runtime SHALL apply only those fields the incoming frame re-specifies, determined
from the score, and SHALL leave all other channel fields unchanged.

#### Scenario: Unspecified fields are preserved

- **WHEN** the playhead moves to a frame whose record re-specifies only the cast member for a channel
- **THEN** that channel's member is updated
- **AND** its location, width and height are unchanged

#### Scenario: A channel absent from the incoming frame is cleared

- **WHEN** the playhead moves to a frame that has no sprite record for a channel that previously held one
- **THEN** the channel becomes empty and draws nothing

### Requirement: Writing a sprite property acquires automatic puppet ownership

When Lingo assigns a sprite property, the runtime SHALL mark that property as owned by the program for
that channel. An owned property MUST NOT be overwritten by score data application.

#### Scenario: Owned location survives score reapplication

- **WHEN** a handler assigns `the locH of sprite 30` and the frame is then re-applied
- **THEN** the assigned location is retained and the score's location is not applied

#### Scenario: Ownership is per property, not per channel

- **WHEN** a handler assigns only `the memberNum of sprite 30`
- **THEN** subsequent score application may still update that channel's location
- **AND** MUST NOT update its member

### Requirement: puppetSprite acquires and releases whole-channel ownership

`puppetSprite <channel>, TRUE` SHALL mark the whole channel as program-owned. `puppetSprite <channel>,
FALSE` SHALL clear ownership and SHALL immediately re-apply the current frame's score data to that
channel.

#### Scenario: Clearing a puppet snaps the channel back

- **WHEN** a channel is puppeted, its member is changed, and `puppetSprite <channel>, FALSE` is then called
- **THEN** the channel's member returns to the current frame's score value
- **AND** the change is visible on the next composite without waiting for a frame change

#### Scenario: Puppeted channel ignores score application

- **WHEN** a channel is puppeted and the playhead moves to a frame specifying different values for it
- **THEN** none of those values are applied

### Requirement: Ownership releases only when the score re-specifies the field on a frame-number change

The runtime SHALL release automatic ownership of a property only when the score explicitly re-specifies
that property **and** the frame number changes. Re-applying the same frame number MUST NOT release
ownership.

#### Scenario: A parked playhead never releases ownership

- **WHEN** a handler assigns `the locH of sprite 30` and the frame handler parks the playhead by jumping to
  its own marker every tick
- **THEN** ownership is retained on every tick
- **AND** the assigned location is never replaced by the score's

#### Scenario: Moving to a frame that re-specifies the field releases it

- **WHEN** a channel's location is program-owned and the playhead moves to a different frame whose record
  re-specifies that channel's location
- **THEN** ownership is released and the score's location is applied

### Requirement: Visibility is program-owned channel state the score never restores

`the visible of sprite <n>` SHALL read and write a channel field that initialises to visible. The runtime
SHALL honour every write in both directions. Score data application MUST NOT alter visibility, and
visibility MUST NOT be filtered by event type or by whether the channel is puppeted.

#### Scenario: An entry script hides a collectable the player holds

- **WHEN** a room's frame handler sets `the visible of sprite 17` to 0 because the inventory contains the
  item
- **THEN** channel 17 draws nothing
- **AND** the hide persists while the playhead remains in that room

#### Scenario: A hidden channel is shown again when the condition reverses

- **WHEN** the same handler runs with the item absent from the inventory and sets visibility to 1
- **THEN** channel 17 draws again

#### Scenario: Visibility is readable by other scripts

- **WHEN** a handler tests `sprite(15).visible` before allowing an inventory drop
- **THEN** it reads the current channel visibility, including a value written by a different script

### Requirement: Location is a composite point with scalar views

The runtime SHALL represent a channel's location as a single point value assignable as a unit via
`the loc of sprite <n>`, with `the locH of sprite <n>` and `the locV of sprite <n>` reading and writing its
components.

#### Scenario: Assigning the whole location

- **WHEN** a handler assigns `the loc of sprite <n>` a point value
- **THEN** both components update and both scalar views read the new values

#### Scenario: Assigning one component leaves the other

- **WHEN** a handler assigns `the locV of sprite <n>`
- **THEN** the horizontal component is unchanged

### Requirement: The sprite property table is complete

The runtime SHALL bind every sprite property name the AST compiler recognises, not a subset selected by
observed usage. Access SHALL be table-driven.

#### Scenario: A recognised property is bound

- **WHEN** any sprite property name the compiler can produce is read or written
- **THEN** it resolves through the table rather than falling to a default

#### Scenario: An unrecognised property is reported, not defaulted

- **WHEN** a sprite property name absent from the table is accessed
- **THEN** the runtime raises a located diagnostic as specified by `surface-diagnostics`
- **AND** MUST NOT return 0
