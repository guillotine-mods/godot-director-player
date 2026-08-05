## ADDED Requirements

### Requirement: Geometry and pointer queries read live channel state

All channel geometry and pointer queries SHALL compute against live channel state, including program-owned
location and member. They MUST NOT read the score's frame sprite data or any separate override store.

#### Scenario: A moved channel is hit where it now is

- **WHEN** a handler assigns a channel's location and a pointer query is then made at the new position
- **THEN** the query reports that channel

#### Scenario: A moved channel is not hit where the score placed it

- **WHEN** the same query is made at the channel's score position
- **THEN** the channel is not reported

#### Scenario: A member change changes the hit area

- **WHEN** a handler assigns a channel's member to one with different dimensions
- **THEN** subsequent queries use the new dimensions

### Requirement: Sprite intersection tests the drawn shape for matte inks

For channels drawn with a matte ink, `sprite <a> intersects <b>` SHALL report intersection only where the
two channels' drawn shapes overlap, not merely their bounding boxes. A bounding-box test SHALL be used as a
fast reject before the shape test.

#### Scenario: Overlapping boxes with non-overlapping shapes

- **WHEN** two matte-ink channels have overlapping bounding boxes but no overlapping opaque pixels
- **THEN** the intersection test reports false

#### Scenario: Overlapping shapes

- **WHEN** two matte-ink channels have overlapping opaque pixels
- **THEN** the intersection test reports true

#### Scenario: Disjoint boxes reject without a shape test

- **WHEN** two channels' bounding boxes do not overlap
- **THEN** the test reports false without computing shape overlap

#### Scenario: An empty channel never intersects

- **WHEN** either channel is empty
- **THEN** the test reports false

### Requirement: Per-member masks are available to the runtime

The render model loader SHALL expose, for each bitmap cast member, a mask describing which pixels are
opaque under the member's ink, for use by shape-level tests.

#### Scenario: A mask is available for a drawn member

- **WHEN** a channel displays a bitmap cast member
- **THEN** a mask for that member is obtainable without decoding the image again per query

#### Scenario: A member with no mask falls back explicitly

- **WHEN** a mask cannot be produced for a member
- **THEN** the runtime records the fallback to a bounding-box test as a diagnostic rather than reporting a
  shape result it did not compute

### Requirement: Rollover reports the channel under the pointer

`rollOver` SHALL report whether the pointer is currently within a given channel, and the runtime SHALL
provide the channel currently under the pointer. Both SHALL use live channel state.

#### Scenario: Pointer inside a channel

- **WHEN** the pointer is within a channel's drawn area and that channel is visible
- **THEN** `rollOver` for that channel reports true

#### Scenario: A hidden channel does not roll over

- **WHEN** the pointer is within a channel whose visibility is off
- **THEN** `rollOver` for that channel reports false

### Requirement: A blank channel retains its last non-empty bounds for rollover

Where the movie's Director version requires it, a channel that has become empty SHALL continue to report
rollover against the bounds it had when it last displayed a member.

#### Scenario: Rollover after a channel is blanked

- **WHEN** a channel displaying a member is blanked and the pointer is within its former bounds
- **THEN** rollover for that channel reports true, if the movie version requires this behaviour

#### Scenario: Version-gated behaviour is not applied where it does not hold

- **WHEN** the movie's version does not require the retained-bounds behaviour
- **THEN** an empty channel reports no rollover

### Requirement: The last clicked channel is reported

The runtime SHALL expose the channel most recently clicked. On mouse-down it SHALL record the channel under
the pointer. On mouse-up it SHALL record the channel under the pointer when one is present, and otherwise
leave the recorded value unchanged.

#### Scenario: A click over a channel records it

- **WHEN** a mouse-down occurs over a channel
- **THEN** the last clicked channel is that channel

#### Scenario: A release away from any channel does not clear the record

- **WHEN** a mouse-up occurs where no channel is hit
- **THEN** the previously recorded channel is retained

#### Scenario: A generic handler identifies its target

- **WHEN** a handler shared across many channels reads the last clicked channel to decide what was clicked
- **THEN** it reads the channel that received the current event

### Requirement: Per-channel cursor, constraint and draggability are honoured

The runtime SHALL support reading and writing a channel's cursor, its movement constraint, and whether it is
draggable, all as channel state.

#### Scenario: A channel cursor applies over that channel

- **WHEN** a channel's cursor is set and the pointer enters that channel
- **THEN** the displayed cursor is the channel's

#### Scenario: A constrained channel cannot leave its constraint

- **WHEN** a channel with a constraint set is moved beyond the constraining channel's bounds
- **THEN** its position is clamped to those bounds

#### Scenario: A draggable channel follows the pointer

- **WHEN** a mouse-down occurs over a channel marked draggable and the pointer moves
- **THEN** the channel's location follows the pointer
- **AND** the resulting location is program-owned as specified by `sprite-channel-state`
