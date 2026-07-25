# Godot Score Catch-Up Design

## Context

Piposh 2's New Game action correctly routes from `strtgame` to `EXODUS`, and
the final EXODUS frame correctly routes to `DAY1`. In practice, EXODUS can be
consumed immediately instead of playing as the opening cutscene.

`DirectorRuntime.tick` currently replays every accumulated score step in a
single Godot process tick. A slow frame caused by synchronous asset loading or
an operating-system stall can therefore advance through a large part of a
movie before Godot draws another frame.

The long-term product direction is a complete, Godot-native implementation of
the original game. This fix must improve the general Director-compatible
runtime rather than special-case EXODUS or depend on the former web player.

## Requirements

- A slow Godot process frame must not fast-forward a score movie.
- Normal score playback must continue to use the FPS declared by frame data.
- The fix must apply uniformly to every movie.
- New Game must enter EXODUS at its first frame.
- EXODUS must transition to DAY1 only through normal score navigation or an
  explicit user-requested skip.
- Existing delay, click-wait, audio guard, puppet-walk, and movie-navigation
  behavior must remain intact.
- The implementation and automated tests must run entirely in Godot.

## Approaches Considered

### Bound score catch-up per process tick

Limit the number of score steps that `DirectorRuntime.tick` may execute during
one Godot process tick. Discard accumulated time beyond that limit so the next
process tick resumes from real time rather than continuing a fast-forward
backlog.

This is the selected approach. It fixes the scheduler at the runtime boundary,
applies to all movies, and remains independent of asset-loading strategy.

### Reset timing only when changing movies

The runtime already clears its accumulator in `goto_movie`. Additional resets
would not protect playback from stalls that occur after a movie starts, so this
does not address the general failure.

### Preload or asynchronously load every movie asset

This could reduce stalls, but it is a larger asset-pipeline change and does not
make the score scheduler safe from unrelated stalls. Asset-loading improvements
may be pursued separately.

## Runtime Design

`DirectorRuntime` will define a small maximum number of score steps allowed per
call to `tick`. Three steps is enough to smooth an ordinary missed render frame
without visibly jumping through a cutscene.

For each `tick(delta)` call:

1. Add the elapsed time to the score accumulator.
2. Determine the current score step duration from `current_fps`.
3. Calculate how many score steps are due.
4. Execute no more than the configured maximum.
5. If more steps were due, discard the excess accumulated whole-step time while
   preserving only the sub-step remainder.

The cap belongs to the generic score clock. There will be no movie-name checks
and no EXODUS-specific delay.

## Error and Edge-Case Behavior

- A zero or invalid FPS remains clamped to at least one FPS.
- A small delta behaves exactly as before.
- A large delta advances a bounded number of score steps and cannot create a
  backlog that fast-forwards subsequent process ticks.
- If a score step changes the active movie, the movie transition's accumulator
  reset ends catch-up. The newly loaded movie starts timing from its first
  frame instead of consuming steps owed by the previous movie.
- Explicit intro or minigame skipping remains controlled by
  `AppSettings.allow_minigame_skip` and the existing skip input path.

## Testing

Godot headless tests will exercise production runtime code.

- A synthetic large delta advances no more than the catch-up limit.
- Excess accumulated time is discarded, so a following zero/small delta does
  not continue fast-forwarding.
- Ordinary deltas still advance at the configured FPS.
- The boot-chain test confirms `strtgame` loads EXODUS at frame index zero and
  that EXODUS reaches DAY1 only via its final navigation.

The implementation will follow test-first development: add the failing
regression test, verify its expected failure, implement the scheduler limit,
then run the focused and full available Godot test suites.

## Out of Scope

- Porting or changing the former web implementation.
- Hard-coding EXODUS playback duration.
- Redesigning the asset loader.
- Implementing other missing original-game features in this change.

Those features remain part of the broader goal of full original-game fidelity,
but they should be delivered as separate, testable runtime improvements.
