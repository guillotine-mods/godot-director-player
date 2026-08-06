# A shared harness for the verification tools

The 18 `.gd` tools in `tools/` each hand-roll their boot, their stepping, their
clicking and their reporting. This gives them one driver, and draws the boundary
that lets that driver be carried to another Director port.

## Why, in order of what it is worth

**A false pass in five harnesses.** `wandering_characters.gd:58` carries a
`_complete()` guard because a GDScript runtime error aborts the handler and
returns the type's zero value, so `failures += _check(...)` scores a *dead* check
as a pass. That already made `verify_film_loops.gd` print "all 3 draw the expected
members" while every one of the three had aborted. `cliff_meeting.gd`,
`collectables.gd`, `cursors.gd`, `room_names.gd` and `puppet_visibility.gd` have
no such guard, so any runtime error inside them today reads as a pass. Hoisting
the guard into a shared harness fixes that once.

**A general probe for the next scene.** `_stuck.gd` is the throwaway that answered
bugs.md 22, hardcoded to `strtgame` and named to be ignored. Promoted, it becomes
the first command to reach for when a scene misbehaves.

**A boundary that survives the title.** `director-port-architecture` says the
loader, score runner, interpreter host and engine transfer between Director ports
and that game state does not. Every tool today boots through
`root.get_node("GameState").new_game()`, and `GameState` is thoroughly Piposh:
`DAY1_MEETINGS_INIT`, `HUB_MOVIES = ["DAY1", "HOTEL1", "NIGHT1"]`, `people_funk`.
A lib that hoists that call as written is born non-portable.

**Deduplication is the least of it** and is listed last on purpose: the `_check`
reporter has 5 copies, the boot triple 14 sites in `smoke.gd` alone, and
`OS.get_cmdline_user_args()` 4 ad-hoc parsers.

## What is explicitly not generalised

The assertions. `cliff_meeting.gd` asserting *both prompts offer a choice, the
score reaches DAY1, the meeting marks itself done* is scene-specific on purpose:
that is what makes it pass/fail. A general "playthrough checker" printing statistics
for an arbitrary room would be a downgrade into exactly the number-that-is-not-
higher-is-better `AGENTS.md` warns about, and `porting-fidelity-verification`
exists because of those. **Hoist the driver, keep the scenario.**

## Shape

    tools/lib/harness.gd     title-agnostic   assertions and the dead-check guard
    tools/lib/driver.gd      title-agnostic   boot, real-time stepping, clicking, trace
    tools/lib/args.gd        title-agnostic   --key value parsing
    tools/lib/game_hooks.gd  PIPOSH ONLY      new_game, the settings flags, state accessor

`game_hooks.gd` is the one file rewritten when the lib is carried to another
title. A named seam, not `has_method` checks scattered through the driver: in a
language with no compile step an implicit seam fails at runtime, in a tool, months
later. It is rewritten per title, never parameterised — configuration for
differences between games we have not met would be invention, not design.

### harness.gd

    h.begin(case)              declares a case; unclosed at finish() is a FAIL
    h.check(name, ok, detail)
    h.complete(case)
    h.finish(summary) -> int   prints the verdict, returns the exit code

`begin`/`complete` is the `wandering_characters.gd` guard. Declaring the case
before running it is what makes an aborted case fail rather than vanish.

### driver.gd

    Driver.fresh(tree, {movie, label, ...}) -> Driver
    await d.run_for(ms, {click_prompts, dwell, until_movie_changes})
    d.clickable() / d.sprite_on(channel) / d.click(sprite)
    d.trace() -> {states, distinct, most_repeated, tail}

`run_for` awaits `process_frame` on the `SceneTree` handed to the driver at
construction. This is load-bearing and is the single thing that must not regress:
a synthetic `for i in N: tick()` loop advances the runtime's clock and not the
audio server's, so no sound ever finishes, every `if soundBusy(1) then go to the
frame` guard holds for ever, and the result is indistinguishable from an infinite
loop. That is bugs.md 22, twice.

### probe.gd

    godot --headless --script tools/probe.gd -- --movie X --label Y \
        --seconds N [--click-prompts] [--trace]

Boots a bare `DirectorRuntime`, not `scenes/main.tscn`: the runtime is what
stalls, and the scene adds startup cost without adding evidence. Reports the
playhead trace, the most-repeated state, the distinct state count and where the
score ended up. `_stuck.gd` is deleted in the same commit.

Probe is also the proof the seam is real. It takes its movie and label from the
command line and knows nothing about Piposh, so if it works, the boundary holds.

## Loading

`load("res://tools/lib/...")`, never `class_name`. Class resolution needs
`.godot/global_script_class_cache.cfg`, which is gitignored, so a `class_name` lib
would break all 18 tools on a fresh checkout or worktree in a file nobody touched.

## Acceptance

1. `tools/lib/` minus `game_hooks.gd` is droppable into another Director port
   unchanged. Checkable: no `DAY1`, no `meetings`, no channel number, no
   `get_node("GameState")` in `harness.gd`, `driver.gd`, `args.gd`.
2. `cliff_meeting.gd`, `collectables.gd` and `cursors.gd` print the same verdict
   lines after migration as before. Captured before the change, diffed after.
   `cliff_meeting.gd` runs in real time and takes minutes, so it migrates last.
3. `probe.gd --movie MURDER1` reproduces the bugs.md 22 observation: the score
   cycles a span and waits, and `--click-prompts` walks it out.
4. A deliberately broken check in a migrated tool reports FAIL, not silence. This
   is the false-pass fix and it is the one thing a before/after diff cannot show,
   because before the change the broken check passes.

## Scope

This pass: the lib, `probe.gd`, three migrations. The remaining 14 `.gd` tools
follow once the lib has three real users. The Python tools are untouched; they
already operate over the whole cast and score rather than one scene.

Documentation is part of the deliverable, not a follow-up: a `tools/lib/` pointer
in `AGENTS.md` and a `probe.gd` line in `README.md`. Without them the next session
writes another `_stuck.gd`.

## The counterargument

A shared lib in a dynamically-typed language with no test suite is a single point
of failure across every tool, and a lib change can break one silently. The
mitigations are that the lib holds assertions and driver only with zero scenario
logic, and that migration is incremental with a verdict-line diff per tool.
Designing for a second game that does not exist is speculative generality; what
makes it defensible is that the discipline costs one file and pays off for future
scenes in this game regardless.
