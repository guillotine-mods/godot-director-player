---
name: director-lingo-semantics
description: Use when interpreting or debugging Macromedia Director Lingo inside a port - room entry gating, marker resolution, sprite visibility, cast script resolution, Movie-In-A-Window, or when an interpreted handler runs but appears to do nothing. Version-independent; applies to any Director game, not just Piposh 2.
---

# Director Lingo semantics for a port

Everything here was learned by getting it wrong first, on Piposh 2 (Director 7).
None of it is derivable from the port's own code. It applies to any Director
title, so it carries to Piposh 1 unchanged.

## The rule that matters most

**Read the original script. Do not reason from Director's documented semantics.**

Every time a visibility, walk or reveal behaviour was modelled from first
principles it was wrong, three times in a row on the same feature. The decompiled
Lingo is the specification. Open the handler before forming a theory.

## Message hierarchy

A mouse event resolves down four levels, first handler wins:

1. the sprite's behaviour, from the score's frame intervals
2. the script on the cast member the sprite displays
3. the frame script (the score's script channel)
4. any movie script

Frame events (`enterFrame`, `exitFrame`) skip 1 and 2 and start at the frame
script — except that Director also sends them to sprite behaviours, which is easy
to miss.

**A handler existing is not a handler acting.** Most walk hotspots carry no
behaviour of their own but sit on a cast member whose script defines `mouseUp`
generically, so "does a handler exist" answers yes for all of them. If the port
falls back to lifted export data only when no handler exists, that fallback never
fires. Decide by whether the dispatch *did* something.

## Room entry is where state gets set

Rooms announce themselves in an `enterFrame` handler:

    whereami = label(0)

and a large number of `mouseUp` handlers gate their real behaviour on `whereami`.
On Piposh 2 that was 138 handlers against 13 setters. With `whereami` unset every
gate is false and every hotspot silently takes a dead branch.

Two traps follow:

- **Jumping to a room's standing label skips the entry frames.** DAY1's dwarfs
  room is 1473 (blank sprites) → 1474 (conditional restore) → 1475 `dwarfsgo`.
  Arriving at `dwarfsgo` runs neither of the first two.
- **Replay both events, not just `enterFrame`.** The blanking is `enterFrame`;
  the conditional restore is `exitFrame`. Replaying one gave permanently
  invisible collectables.

Replay skipped frames under `record` (see below) so a `go` in one cannot hijack
the arrival.

## `marker()` resolves by position, never by name

Director names an unnamed marker `New Marker`. Piposh 2's title movie has 49 of
them against 32 distinct labels, so a name-keyed lookup collapses every marker in
a sequence onto the first. `go(marker(0) + 1)` then means "jump to the start" from
anywhere, and any frame that starts a sound unconditionally becomes an infinite
loop with the speech restarting.

`marker(0)` means the marker at or before the playhead. `label(n)` with a *number*
means the same thing, not a lookup of a marker literally named "0".

## Visibility is game state

`sprite(N).visible` is not decoration. A room's frame handler sets it from the
inventory on every step:

    -- DAY1 BehaviorScript 245
    if <objectsfield contains "masor"> then
      set the visible of sprite 17 to 0
    else
      set the visible of sprite 17 to 1
    end if

and other scripts read it back to make decisions (`MASTER BehaviorScript 111`
tests `sprite(15).visible` before allowing a drop). So:

- Honour every write, in both directions.
- Do **not** filter writes by event type or by whether the sprite is puppeted.
  Both were tried. Suppressing frame-handler hides made every collectable
  permanent; honouring only puppeted writes stopped picked-up items clearing.
- An entry script blanking sprites unconditionally is normal. The conditional
  handler on a later entry frame is what puts them back.

Some channels are reveal slots: hidden on entry, shown when the player earns
them. On Piposh 2, searching scenery reveals a shell or bottle on a channel named
in a data field, and the hide-on-entry is what makes that work.

## Cast script resolution

- ProjectorRays writes a linked cast's scripts twice: once under the movie that
  links it, once in the cast's own standalone export. **The movie-local copy is
  what the attachment data means, so it must win.**
- Bundles keyed on the ProjectorRays subdirectory collide. Eleven Piposh 2 casts
  are called `External` and eleven more `Internal`. Key by directory *and* cast,
  or a lookup for member N returns whichever cast loaded last. This produced
  wrong scripts that ran and did plausible-looking nothing.
- A sprite with an interpreted handler but no lifted `on_click` is still a
  hotspot. Filtering clickability on the export's data alone makes every
  script-only hotspot unreachable.

## Globals that must alias host state

Adventure state has to be the same object the saves and UI use, not a shadow
copy. On Piposh 2: `objectsfield` (inventory), `meetings`, `globalday`. Read as
plain interpreter globals they are empty, so every conditional against them takes
the wrong branch — corpses stay hidden, exits stay shut, meetings never fire.

Lingo reads `meetings` as an item list, so a host array has to present as one
comma-separated string.

## Record mode

Hosts usually want a mode that captures navigation and sound instead of
performing them, for harnesses and for replaying skipped frames. **Anything added
to the host that changes movie must honour it.** A Movie-In-A-Window `open` that
ignored `record` took a convergence sweep out of the movie it was measuring on the
first save button it dispatched, and reported 14 reached of 112 instead of 112 of
112.

## Movie-In-A-Window

`window("x.dxr")`, `open(...)`, `forget(...)`, `tell window(...) ... end tell`.
Director floats a real window; a single-stage port can treat it as an overlay on
a route stack, with `open` as goto-movie and `forget` as go-back. The handle can
just be the movie stem. Window trimmings (`windowType`, `centerStage`,
`drawRect`) are meaningless on one stage and can be accepted and ignored — but a
property write on a window handle must not fall into the interpreter's
assign-failure path.

### What the swap breaks

**In Director the parent movie never unloads.** Modelling the window as a movie
swap means every piece of state the port keeps *per movie* now crosses a boundary
it never crossed in the original. Each of these cost a play session on Piposh 2,
and they were found separately before the pattern was obvious:

- **Cast library 1 means "the current movie's own cast".** Any member reference
  held across the swap silently re-resolves. The port drew the player character
  into the window using `cast_lib 1` plus the member number its own controller
  held; JOKE's member 29 is the joke bitmap `joke33`, and the character's
  largest standing member is also 29. The result was a *second joke* on the page,
  at his stage position. Sizes 84, 110, 136 and 162 do not exist in JOKE, so it
  drew nothing at those and the fault looked room-dependent and random.
  Corollary: a sprite belongs to the movie whose channel it is. Ask whether the
  loaded movie's score uses that channel **anywhere** — per movie, not per frame,
  because a transition span can legitimately omit a channel for its whole length
  while the character walks through it.
- **Returning has to re-scope the interpreter.** The go-back path reloaded the
  movie without the "prepare movie" step its forward counterpart runs, so script
  resolution still pointed at the movie being *left*. Frame scripts resolved to
  nothing and the room's entry handlers silently did not run — which read as
  unrelated bugs: every collectable in the room on show, and stale room-identity
  globals sending hotspots down dead branches. One line, and nothing errored.
- **State the destination's own initialisation established is gone.** `init all`
  runs `puppetSprite` on a set of channels once, on the movie's first frame. The
  return lands mid-room and never re-runs it, so puppet ownership evaporates on
  the first round trip and the score reclaims channels Lingo is supposed to own.

The rule: for each piece of per-movie state, decide explicitly whether the swap
preserves it or resets it. The answers differ per item — channel contents should
reset, script scope must follow the movie, adventure state must survive, and
initialisation-established ownership needs re-establishing — so a blanket clear
and a blanket keep are both wrong.

## Other bindings worth knowing

- `go(1, "movie.dxr")` means *frame 1 of that movie*. The two-argument form is
  easy to miss, and dropping the second argument turns it into a jump to frame 1
  of the current movie. Used 64 times in Piposh 2, including every meeting jump
  and New Game.
- `set the keyDownScript to "handler"` is how key input reaches scripts. Piposh 2
  uses it once, to stop sound channel 1 so a keypress cuts speech.
- `member(n, "cast").name` is how generic handlers identify what was clicked, so
  member-name tables are load-bearing, not cosmetic.

## Reading an unhandled-builtin list

Treat it with suspicion. A read of an uninitialised local looks identical to a
missing builtin, so names like `x`, `y`, `x2` appearing there usually mean a
conditional branch was not taken, not that a binding is absent.
