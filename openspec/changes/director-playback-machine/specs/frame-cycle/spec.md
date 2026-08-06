## ADDED Requirements

### Requirement: One playback step runs an ordered stage sequence

The runtime SHALL execute one playback step as an explicit ordered sequence of stages: wait gate, exit of
the outgoing frame, frame load and score delta application, tempo and wait-condition decode, render, entry
of the new frame, then resumption of parked handler continuations. The sequence SHALL be expressed as data
rather than as inline control flow.

#### Scenario: Stages run in order

- **WHEN** a playback step executes with no handler suspending
- **THEN** the stages run in the specified order
- **AND** the stage that renders occurs after score delta application and before frame entry

#### Scenario: A suspended handler yields the remainder of the step

- **WHEN** a handler suspends during any stage
- **THEN** the runtime returns from the step without running later stages
- **AND** the parked continuation is resumed on a subsequent step

### Requirement: Frame exit is suppressed when a jump is pending

The runtime SHALL send the frame-exit event for the outgoing frame only when no navigation is already
pending and the event has not already been sent for that frame.

#### Scenario: A jump suppresses exit on that cycle

- **WHEN** a handler navigates and the runtime begins the next step
- **THEN** the frame-exit event is not sent for the frame that was jumped from

#### Scenario: Exit is sent once per frame

- **WHEN** a frame is held across several steps without navigation
- **THEN** the frame-exit event is sent once, not once per step

### Requirement: Tempo and wait conditions gate the step

The runtime SHALL decode the frame's tempo channel into a frame interval or a wait condition, and SHALL
hold the step until that condition is satisfied. Supported wait conditions SHALL be: wait for mouse click,
wait for a sound channel to finish, and a fixed delay. The decoding SHALL be selected by the movie's
Director version.

#### Scenario: A frame rate sets the interval

- **WHEN** a frame's tempo specifies a frame rate
- **THEN** the next step occurs after the corresponding interval

#### Scenario: Waiting for a sound holds the step

- **WHEN** a frame's tempo specifies waiting for a sound channel and that channel is active
- **THEN** the step is held
- **AND** parked continuations are still resumed while held

#### Scenario: A pending jump cancels a wait

- **WHEN** the step is holding on a wait condition and a handler navigates
- **THEN** the wait is abandoned and the navigation takes effect

### Requirement: A parked playhead is a distinguishable state

The runtime SHALL distinguish a frame held by an explicit jump to its own position from a frame reached by
ordinary advance, and SHALL make that state available to film loop advance.

#### Scenario: Jumping to the current frame is recognised as parked

- **WHEN** a frame handler navigates to the marker at or before the playhead, resolving to the frame
  already loaded
- **THEN** the runtime records the frame as held by an explicit jump
- **AND** does not treat the step as an ordinary advance

#### Scenario: Score data is re-applied without releasing ownership

- **WHEN** the playhead is parked
- **THEN** score data application runs for non-owned fields only
- **AND** program-owned fields are retained, as specified by `sprite-channel-state`

### Requirement: updateStage composites without advancing the playhead

`updateStage()` SHALL synchronously composite current channel state to the screen and play any queued
puppet sounds. It MUST NOT advance the playhead, load a frame, or dispatch any script.

#### Scenario: An animation loop inside one handler animates

- **WHEN** a handler writes a channel's location and member and then calls `updateStage()`, repeatedly,
  inside a single frame-exit handler
- **THEN** each `updateStage()` call composites the current channel state
- **AND** no frame entry or exit event is dispatched by those calls

#### Scenario: updateStage does not re-enter the frame cycle

- **WHEN** `updateStage()` is called from inside a handler
- **THEN** no playback stage runs as a result
- **AND** the handler continues at the next statement

### Requirement: Reaching the end of the score returns to the caller or restarts

When the playhead passes the last frame, the runtime SHALL return to a pending caller position if one was
pushed by a subroutine jump, and otherwise SHALL return to the first frame.

#### Scenario: Returning from a pushed position

- **WHEN** the score ends and a caller position was pushed
- **THEN** the playhead resumes at that position

#### Scenario: Restarting with no caller

- **WHEN** the score ends and no caller position was pushed
- **THEN** the playhead moves to the first frame
