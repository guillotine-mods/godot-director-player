# Whole-Game Movie Context

## Problem

The runtime resolves navigation per frame but has no model of where a movie sits
in the game. Hub membership, end-of-movie routing, transition redirects, and
meeting bookkeeping are all encoded as Day 1 special cases in
`director_runtime.gd` and `game_state.gd`. Movies reached outside that special
case land in states the original game never produces.

A scan of the exported nav graph across all 85 movies confirms the following
reachable defects.

`JOKE` is a hard softlock. It is reachable from `DAY1` (333 click navs),
`HOTEL1` (90) and `AIR1` (30). It declares no exit nav and carries no clickable
sprite near its end, so `_on_movie_end` falls through to
`enter_frame(loader.frames.size() - 1)` and the game stops responding.

`ARCADE2` is entered from `HOTEL1` and falls off its end. `is_minigame_movie`
routes it to `DAY1 @shore2`, moving the player from the hotel to the Day 1
shore. `SEA1` reaches the same branch and ignores its own exported return label
`shore2downdeck`.

`director_runtime.gd:357` marks a meeting complete only when the destination is
`day1`. `ALLIN`, `ISHDAY1` and `TOFIRCPT` return to `hotel1`, so those meetings
are never recorded and can retrigger.

`_try_day1_transition_redirect` returns early unless the current movie is
`day1`, but the dynamic redirect handler `frame_script 207` also appears in
`NIGHT1` (51 frames), `HOTEL1` (29) and `AIR1` (7). In those movies a completed
walk animation falls into the adjacent reverse animation and the player walks
back to where they started.

Fourteen exports contain zero frames. These are `.CST` cast libraries emitted by
the export pipeline as if they were movies, including `BOOK`, `ISLAND`, `NIGHT`,
`HOTEL` and `MOGUL`. Loading one leaves the runtime with an empty frame list and
a blank stage.

## Constraint

The original Lingo is not available on this machine. `assets/SOURCE.txt` points
at a Windows research tree, the sibling `decompiled_chunks` export no longer
exists, and `members.json` contains bitmap members only. The trigger layer that
decides which meeting fires in which room, when night falls, and when the ending
unlocks therefore cannot be ported faithfully. This design implements the
machinery and repairs the defects above. It does not author progression content.

Two derivations were tested and rejected. Return labels do not identify entry
rooms, because cutscenes relocate the player: `HATDAY1` triggers at `veranda`
and returns to `gate`, `PATDAY1` triggers at `field` and returns to `path4`.
Transition destinations are not derivable from the export either, because walk
navs carry only `target_label`, `walk_to` and `arrive_at`, the hosting room is
always the source, and name based rules contradict each other, with `swingup`
resolving to `swing` while `path3up` resolves to `path4` and `shore2up` to
`gate`.

`NIGHT1` is the same island at night and shares most of its transition labels
with `DAY1`. Promoting the existing verified Day 1 table to a shared table
therefore resolves 19 of `NIGHT1`'s 27 transitions without new data. Forty six
movie and label pairs remain unknown, forty distinct labels: two in `DAY1`,
eight in `NIGHT1`, twenty three in `HOTEL1`, six in `AIR1` and seven in `SEA1`.
The exact list is held in `data/movie_context.json` under
`unmapped_transitions` and was generated from the export rather than counted by
hand.

## Design

### End of movie routing

Remove the hardcoded minigame and meeting name lists from `_on_movie_end`.

The caller on `route_stack` must not be consulted first. `DAY1` frame 153 is
`movie sea1` and frame 729 is `movie air1`, so returning `SEA1` to its caller
re-enters the frame that launched it and the two movies ping pong forever.

Resolve in this order instead.

First, the movie's own declared hub return. Collect every cross movie nav the
movie exports, at frame level and at click level, and keep those targeting a hub
movie. Every non hub movie that falls off its end has exactly one distinct hub
target, so this is unambiguous: `SEA1` gives `day1 @shore2downdeck`, `AIR1` gives
`day1 @rachbalout`, and `ARCADE2` gives `hotel1 @arcade`. Where a movie exports
the same hub target more than once, take the label from the occurrence with the
highest frame index. Where it exports two distinct hub targets, treat the movie
as ambiguous and fall through.

Second, the caller recorded on `route_stack`. This covers `JOKE`, which exports
no cross movie nav at all.

Third, the current hub at its boot frame.

Hub movies are excluded from all three steps. `DAY1`, `HOTEL1` and `NIGHT1` all
fall off their own ends, and routing a hub to its caller would eject the player
from the room they are standing in. A hub holds on its final frame, which is the
existing behaviour and is correct for them.

This repairs `JOKE`, `ARCADE2` and `SEA1` without any hand authored data.

### Movie context

Add `director/movie_context.gd`, backed by `data/movie_context.json` at the
repository root. The data file must not live under `assets/`, which
`assets/SOURCE.txt` documents as mirrored with `robocopy /MIR` and therefore
subject to deletion.

The context answers three questions: which hub a movie belongs to, whether a
movie is playable at all, and what destination a transition label resolves to.
Playability is the zero frame guard; `goto_movie` refuses an unplayable movie,
logs it, and leaves the current movie running rather than blanking the stage.

### Transition redirects

Rename `_try_day1_transition_redirect` to `_try_transition_redirect` and drop
the movie name check. Destinations come from the shared table, seeded with the
twenty two verified Day 1 entries and consulted by every movie. A
`frame_script 207` frame whose transition label has no mapping emits a warning
naming the movie and the label, so the open entries surface during play instead
of silently reversing the walk.

The warning fires only when the player actually walked the transition, or when
the label is one of the known gaps. A redirect frame reached any other way
carries the room marker rather than a transition label, and warning on those
would bury the real gaps.

### Hub and phase

`GameState` gains an explicit hub and phase rather than the literal `"DAY1"` and
`"shore2"` repeated across five call sites. `MEETING_TRIGGERS` gains `hub` and
`phase` fields, and `_try_people_funk` runs on arrival in any hub instead of
`DAY1` only. Only the four already proven Day 1 entries stay populated. The
table is ready for day 2 and night content, and stays empty until that content
can be sourced.

`mark_meeting_done_by_movie` fires on arrival at any hub.

## Verification

Verification is manual, by request. No automated regressions are added for this
change. The nav event log and the F1 debug HUD carry the routing decisions, so
each case below is observable in play.

1. Click a joke hotspot in `DAY1`, then in `HOTEL1`. Play the joke out. The game
   returns to the room it was called from instead of freezing.
2. Enter the arcade from `HOTEL1` and finish `ARCADE2`. The return is to
   `HOTEL1`, not to the Day 1 shore.
3. Board the ship from `DAY1` and play `SEA1` to its end. The return is
   `DAY1 @shore2downdeck`, and the ship must not immediately re-enter. This is
   the livelock guard, and it is the case most worth checking, because it fails
   if the caller is ever consulted ahead of the movie's own hub return.
4. Complete `ALLIN` and return to `HOTEL1`. The meeting does not retrigger.
5. Walk a transition in `HOTEL1` or `AIR1`. Piposh completes the walk and stays
   in the destination room rather than turning around.
6. Watch the log for `unmapped transition` warnings. Each names a movie and a
   label and is one of the forty six open destinations, to be filled in as they
   are identified in play. A warning tagged `NEW` means the label was not in
   `unmapped_transitions`, so the generated list missed it.

Run the Godot editor parse check before handing over, and confirm the existing
suite in `tests/` still passes, since it was not written against this behaviour
and should be unaffected.

Run the full headless suite and the Godot editor parse check, not only the new
tests.

## Out of scope

Day 2, night and ending trigger content. After this change the game is state
correct everywhere it can currently reach, `NIGHT1` and `HOTEL1` transitions are
mechanically correct, and the remaining gaps are visible in the log. Reaching
day 2 still requires the original Lingo or deliberate playtesting to recover the
trigger conditions, and that is a separate change.
