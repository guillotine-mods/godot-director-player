## ADDED Requirements

### Requirement: Navigation suspends the running handler rather than relocating the playhead

A navigation command issued from inside a handler SHALL record the pending target and suspend execution of
that handler. It MUST NOT load a frame or alter the playhead while the handler is still running. After the
playback step advances, the runtime SHALL resume the handler at the statement following the navigation
command.

#### Scenario: A frame-exit handler resumes after its jump

- **WHEN** a frame-exit handler calls a navigation command and has further statements after it
- **THEN** the playhead does not move during that handler
- **AND** the frame cycle advances
- **AND** the handler then resumes at the statement after the navigation command

#### Scenario: Statements before the jump have already taken effect

- **WHEN** a handler writes channel state, navigates, and then writes more channel state
- **THEN** the first writes are in effect when the frame advances
- **AND** the later writes occur after the advance

#### Scenario: Entry scripts are not replayed to compensate

- **WHEN** navigation lands on a frame whose entry stages would otherwise have been skipped
- **THEN** those stages run as part of the normal cycle
- **AND** the runtime MUST NOT re-run previously executed entry scripts to compensate

### Requirement: A continuation captures the full execution state

A suspended handler's continuation SHALL capture, for every active call frame, the statement list and the
index of the next statement to execute, the frame's local variables, its owning script, and its `me`
reference. Resuming SHALL restore all of them.

#### Scenario: Locals survive suspension

- **WHEN** a handler sets a local variable, navigates, and reads that local after resuming
- **THEN** the value read is the value set before suspension

#### Scenario: The resume position is the next statement

- **WHEN** a handler suspends at a navigation command
- **THEN** resuming executes the statement immediately after it, and does not re-execute the navigation

### Requirement: Continuations span nested handler calls

When a navigation command is issued from a handler invoked by another handler, the continuation SHALL
capture every frame in the call chain and resuming SHALL restore the whole chain, continuing in the
innermost frame.

#### Scenario: Navigation inside a helper handler

- **WHEN** a frame-exit handler calls a helper handler which issues a navigation command
- **THEN** both frames are captured
- **AND** resuming continues inside the helper
- **AND** on the helper returning, execution continues in the caller after the call

### Requirement: Continuations preserve the tell target

When a navigation command is issued inside a `tell` block, the continuation SHALL record the tell target and
resuming SHALL restore it before executing further statements in that block.

#### Scenario: Navigation inside a tell block

- **WHEN** a `tell` block issues a navigation command and has further statements before `end tell`
- **THEN** those statements execute against the same tell target after resuming

### Requirement: Continuations preserve repeat loop state

When a navigation command is issued inside a `repeat` construct, the continuation SHALL capture the loop's
iteration state and resuming SHALL continue the loop from that state rather than restarting or exiting it.

#### Scenario: Navigation inside a repeat body

- **WHEN** a `repeat` body issues a navigation command on some iteration
- **THEN** resuming continues that same iteration after the navigation command
- **AND** the loop then proceeds to its next iteration normally

### Requirement: Suspension originates only at statement level

The runtime SHALL treat suspension as reachable only from statement execution. Expression evaluation MUST
NOT suspend. A build-time check SHALL assert that no AST node marked as a command call appears in a
value position.

#### Scenario: The invariant is checked at build time

- **WHEN** the script corpus is compiled
- **THEN** the check reports any command call appearing as a subexpression
- **AND** the build fails if any is found

### Requirement: An unsupported suspension context raises rather than mis-resuming

Where a suspension context is not yet implemented, the runtime SHALL raise a located diagnostic naming the
context. It MUST NOT silently resume at a wrong position or discard the continuation.

#### Scenario: Suspension in an unimplemented context

- **WHEN** a navigation command suspends in a context the current build does not support
- **THEN** a diagnostic naming the script, handler and context is raised
- **AND** no partial resume occurs

### Requirement: Resumption does not accumulate against runaway guards

The step budget SHALL be reset per playback step rather than accumulating across suspensions, and call
depth SHALL be restored from the continuation rather than re-incremented on resume.

#### Scenario: A parked room does not exhaust the step budget

- **WHEN** a frame handler suspends and resumes on every step for many steps
- **THEN** the step budget is not exhausted by the accumulation

#### Scenario: Depth is restored, not doubled

- **WHEN** a continuation with several nested frames is resumed
- **THEN** reported call depth equals the captured depth

### Requirement: Repeated suspension is bounded

The runtime SHALL bound the number of suspensions resolved within a single playback step and SHALL report
when the bound is reached rather than looping without limit.

#### Scenario: Runaway navigation is stopped and reported

- **WHEN** resuming a continuation immediately suspends again, repeatedly, past the bound
- **THEN** the runtime stops resolving suspensions for that step and raises a diagnostic
