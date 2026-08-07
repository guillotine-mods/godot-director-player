---
name: director-port-architecture
description: Use when structuring a Godot port of a Director game, deciding how much original Lingo to interpret versus lift, migrating behaviour from hand-authored tables to the original scripts, or planning what to reuse from the Piposh 2 port for another title.
---

# Structuring a Director port

The shape Piposh 2 arrived at, and which parts of it to copy for another title.

## Reuse as code, do not rewrite

The single biggest head start. The Lingo language barely moved across Director
versions, so these transfer largely intact:

- `tools/lingo_compile.py` — lexer, parser, AST emitter. Parses 3349/3349 Piposh 2
  scripts. Assignment-versus-comparison is resolved by position, `tell` is parsed,
  chunk expressions (`item 2 of line 3 of field "x"`) are supported.
- `lingo/lingo_interpreter.gd` — AST walker, scopes, chunk assignment, repeat forms
- `scenes/preview_lingo_host.gd` — the Director-specific bindings
- `scenes/preview/scripts.gd` — the message hierarchy and script resolution

  (These were `lingo/lingo_host.gd` and `lingo/lingo_engine.gd`, both since
  deleted with the renderer they served. Do not go looking for them.)

Rewriting the parser would be the most expensive available mistake. What *will*
need work is the host: bindings are game-shaped, and each new title uses a
different subset.

## Module split

| module | owns |
|---|---|
| container reader | frames, members, cast libraries, bitmaps, textures — read from the shipped `.dir`/`.cst` at runtime, not from a pre-decoded export |
| score runner | tempo clock, frame entry, navigation, transitions |
| interpreter host | Director bindings: sprites, fields, sound, navigation |
| engine | message hierarchy, script resolution per cast and member |
| puppet controller | the walk state machine, natively |
| game state | inventory, day, progression, saves |

Two boundaries earned their keep:

**Native handlers beat original Lingo where the port already implements the
behaviour.** The walk state machine is native, so the original `walkonby` is
claimed by the host rather than interpreted, and the walk globals
(`egozh`, `egozv`, `whatodo`) *alias* the puppet controller instead of shadowing
it. Shadowing lets the two drift and the second click in a two-click pattern never
fires.

**Adventure state lives in one place.** Inventory, meetings and day alias the game
state object so the interpreter, the saves and the editor cannot disagree.

## Interpret one event class at a time, behind a flag

This is the migration pattern that worked. Do not switch the interpreter on
wholesale.

    use_lingo_frames  -> on: exitFrame, enterFrame
    use_lingo_clicks  -> on: mouseDown, mouseUp

For each class: implement, measure against the lifted export, read every
difference, then flip the default. Piposh 2 ran with frames interpreted and clicks
lifted for a while, which is a legitimate steady state.

Two warnings from doing it:

- **The engine is built when either flag is set**, so a guard on "is there an
  engine" is not a guard on "is this flag on". That mistake handed clicks to the
  interpreter when only frames were meant to be enabled, and broke every walk
  hotspot in the game.
- **Turning a class on makes a large amount of original code run for the first
  time.** Each new thing it reaches can break somewhere no existing harness looks.
  Flipping clicks on Piposh 2 produced four regressions in the first minute of
  play. Have a user-path smoke test first, not after.

## Hand-authored tables are scaffolding, not data

Behaviour the export could not lift gets reconstructed into tables: room
transitions, meeting triggers, sprite gates, inventory drop rules. That is the
right call to get a game completable, on two conditions:

1. **Mark confidence.** Say which rows are verified behaviour and which are
   inferred. Piposh 2's context file carries a `confidence` note per inferred row
   and a list of transitions known to be unmapped.
2. **Plan the retirement.** Every table is a guess that will eventually conflict
   with the real scripts once those run. A story gate reimplemented by hand and a
   story gate honoured by the original Lingo will disagree, and then you have two
   sources of truth for the same decision.

Retire in the order the tables become redundant, and delete rather than leave
both paths live.

## Single stage, and what follows

A Director game can float Movies-In-A-Window. A single-stage port can express that
as an overlay on a route stack — push the current movie, load the window's movie,
pop on close. The same stack serves save screens and minigame excursions.

Consequence worth remembering: **any host binding that changes movie must respect
record mode**, or harnesses and frame-replay both break. See
`director-lingo-semantics`.

## Keep the export loadable at runtime

Piposh 2 reads BMPs and WAVs from source files at runtime rather than importing
them, which keeps a 1.7 GB asset tree out of the engine's import pipeline and
makes regenerating exported data cheap. Generated data that the runtime reads
(the cast registry) is committed, with the tool that produces it and a checker
that gates on it.

## Measurement tools are part of the architecture

Piposh 2 has no unit tests. What it has instead, and what to reproduce:

- a compile check over every decompiled script
- a coverage check that every referenced cast member resolves, by category
- a differ that sweeps a behaviour class with the flag off and on
- a convergence checker comparing interpreted results against the lifted export
- a user-path smoke test

Read `porting-fidelity-verification` before trusting any number any of them
produces.
