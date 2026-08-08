# `scenes/preview/` — where the player lives

`scenes/director_preview.gd` was 4,135 lines. Every bug fix landed in it, so every
two people fixing two unrelated bugs collided — twice: once on the function
bodies, once on the `var _` declaration block that nearly every commit touched.

It is now a ~1,880-line node plus the modules below. The node owns the state and
the Godot lifecycle; the modules own the rules.

## Which file is your bug in?

| symptom | file |
|---|---|
| a sprite draws in the wrong place, or is clickable where it isn't drawn | `sprite_geometry.gd` |
| a script hid/moved/swapped a sprite and the screen disagrees | `sprite_state.gd` |
| a puppeted sprite vanishes, or a script's member swap never wears off | `sprite_state.gd` |
| wrong colours, a matte punching holes, a solid black rectangle | `sprite_art.gd` |
| a field shows the authored placeholder, or a HUD value never updates | `text_art.gd` |
| typing does nothing, the caret is in the wrong field or the wrong place | `text_focus.gd` |
| an animation plays in the wrong place, or with the wrong pictures | `film_loop_view.gd` |
| a click goes to the wrong sprite, or nothing answers it | `interaction.gd` |
| no hand cursor where there should be one, or a corrupt one | `cursor.gd` |
| a Movie-In-A-Window is the wrong size, won't close, or eats clicks | `windows.gd` |
| a trails sprite leaves no stroke, or leaves one it shouldn't | `trails.gd` |
| the whole stage paints wrong, or spills outside the letterbox | `stage_paint.gd` |
| the wrong colours after a palette change | `palette_view.gd` |
| a room runs too fast or too slow, a wait never releases | `frame_loop.gd` |
| a `pause`d room is on the wrong frame, or a click cannot lift the pause | `frame_loop.gd` |
| a sound doesn't play, or the room moves on before speech ends | `sound.gd` |
| a handler doesn't run, or the *wrong* handler runs | `scripts.gd` |
| `member("x")` resolves to something unrelated | `members.gd` |
| a `go to movie` loses state it should keep, or keeps state it should drop | `movie_session.gd` |
| a save does not survive a restart, or `saveMovie` writes the wrong file | `movie_save.gd` |
| a key goes to the wrong movie, or a debug binding eats a game key | `input_router.gd` |
| the movie doesn't start, or globals are empty at boot | `boot.gd` |
| the `L` report is missing something | `debug_report.gd` |
| a save state comes back missing something, or a field isn't carried | `save_state.gd` |
| a save goes to the wrong place, or a stale save loads silently | `save_files.gd` |
| a debug key, outline or overlay shows up in a build | `debug_keys.gd` (`enabled`) |

## The save state

`save_state.gd` writes the whole session to JSON and reads it back — the movie,
the frame, the Lingo globals, the puppets, the clock, the palette, the windows.
Two rules make it trustworthy rather than merely present:

**`ACCOUNTED` names every `_` field on the node**, as saved, rebuilt or
excluded-and-why, and `tools/save_state.gd` reads the node's own property list
and fails when the two disagree in either direction. A field added here and not
classified goes red the first time anybody runs the gate. That is the same
argument `preview_surface.gd` makes: the dangerous failure is the silent one.

**The gate is two processes.** One saves and exits, a second boots from
`--save <file>` alone, and a third compares the two records key by key. A
single-process test cannot tell "persisted" from "still in memory".

## The debug layer has one switch

`[debug] enabled` in `director_game.cfg` — `true`, `false` or `auto` (on from
source or a debug export, off in a release export; the default, and what the
tracked config carries). Everything that exists for us and not for the movie
asks `DebugKeys.enabled()`: every key binding, the hotspot outlines, the SKIP
button, the HUD, the toast, the container picker and the report at exit. Adding
another affordance means adding it to that list, and `tools/debug_bindings.gd`
asserts that with the switch off no keycode is claimed at all.

## Two conventions

**`host` is the preview node.** Modules that need the canvas, the caches or the
puppet state take it as a first argument rather than holding a reference. A call
through `host` is untyped, so `var x := host.something()` will not compile —
annotate: `var x: Rect2 = host.something()`.

**State stays on the node.** `tools/` is an undocumented reflective API into the
preview: fourteen harnesses reach in by name for 69 methods and 23 fields, and
`preview_lingo_host.gd` calls about forty `lingo_*` methods the same way. A field
moved off the node makes `get()` return `null`, and **a harness that reads null
reports zero rather than failing** — the safety net goes dark without going red.
So dictionaries are passed in (they are reference types, so this reads as owning
them) and `tools/preview_surface.gd` asserts the whole surface still resolves.

Run it before and after any move here:

```bash
godot --headless --path . --script tools/preview_surface.gd
```

## Gates

`check.sh` is the fast structural gate — parses, and the reflective surface
resolves. Seconds. `gate.sh` is the behavioural suite; it pins the corpus to
`games/piposh2` because a run against another title reads as five regressions
that are really five different movies.

**It pins with flags, and no longer touches `director_game.cfg`** — read
`gate.sh:24-45` rather than this paragraph's older claim that it rewrote and
restored the config. Mutating a file the whole repo shares meant two concurrent
runs swapped each other's corpus mid-run; `--root` and `--boot` are per process
and cannot. Both flags are needed and `--root` alone was the bug: the boot movie
still came from the config, so with the tracked config naming a `rating` container
every harness that does not pass its own `--file` loaded no score and asserted over
nothing. `bugs.md` 51 carries it.

The baseline is **49 pass, 2 fail** over a list that is **51 entries** since
`idle_clock` and `new_game_reset` joined it, and neither failure is a renderer
question:

- `debug_bindings` — `snapshot = "F10"` in the tracked config collides with a
  keyCode `rating` tests at 48 sites. Config, not code (`399feaaa`).
- `play_suspends` — the known flake, `bugs.md` 41. Roughly half its runs, on the
  cross-movie `suspendhop` assertion, not the dialogue one. Re-measured three
  times over: FAIL, PASS, FAIL.

`lingo_surface_audit` was the third and passes now. **This line is a measurement,
not a prediction** — the paragraph it replaces said 47/2 over 49, admitted that
48/2 was "a prediction until somebody replaces it with one", and asked for a
whole-suite run. That run happened: `bash gate.sh`, one process, 51 entries, no
TIMEOUT and no EMPTY, and the failing *set* is exactly the two above. Replace this
sum the same way — by running the thing — rather than by adding to it.

`boot_state`, which this file recorded as the single baseline failure, passes — and
**not because anything here fixed it.** Measured both ways: it passes with the
`bugs.md` 40 label fix reverted as well, and its `meetings` assertion is present
and green either way (8 items, not an empty list asserted over), so the recorded
failure had already gone stale before this session. The number in this paragraph
was describing a suite of 25 entries; the list is 51 now. Re-measure it here rather
than trusting it, which is the same instruction `bugs.md` opens with.
