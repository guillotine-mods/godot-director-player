---
name: director-qa-playthrough
description: Use when QA-testing a Director title this engine runs - playing it looking for stuck rooms, dead hotspots, wrong graphics or broken logic, driving it automatically, or judging whether a symptom found that way is a real bug. Version-independent; applies to any title under games/, not just Rating.
---

# QA-ing a Director port by playing it

Written after a pass over *Rating* in which **six** candidate findings were
produced by the instrument rather than by the game, two survived, and the deepest
part of the game could not be reached at all until the walker drove the keyboard.

## There are three ways to look, and they see different things

| tool | question | blind to |
|---|---|---|
| `tools/liveness_sweep.gd` | can the playhead leave every container? | anything that draws wrongly; anything only reachable by playing |
| `tools/qa_walk.gd` | can a player get through the first minutes, and what do they see? | whatever its budget does not reach |
| `tools/qa_walk.gd --sweep` | does every container draw, sound and run without error when opened? | anything needing state a real boot sets |
| `tools/click_trace.gd` | what did *this* click do? | everything else |

Run them in that order. The sweep is cheap per movie and covers the whole
corpus; the walk is the only one that produces **pictures**; the trace is the
drill-down once something looks wrong.

```bash
godot --headless --path . --script tools/liveness_sweep.gd -- --root <game> --click --strict --verbose
godot --headless --path . --script tools/qa_walk.gd -- --root <game> --sweep --ticks 150
godot --path . --script tools/qa_walk.gd -- --root <game> --steps 200 --out /tmp/shots   # NOT --headless
godot --headless --path . --script tools/click_trace.gd -- --root <game> --movie X.dir --frame N
```

Depth and breadth are different passes and you need both. Two hundred turns of
walking Rating reaches **25 of its rooms across 4 of its 81 containers** -- a
real player's path, and blind to the other seventy-seven. The sweep opens all of
them and found the three missing sounds the walk never got near.

The sweep takes about 12 s a movie with `--click`; a corpus of 81 is ~16 minutes.
Background it and read the shots from the walk meanwhile.

## Drive the keyboard, or the walk stops at the first cut scene

Director gave the movie the whole keyboard, and these titles gate scenes on it as
readily as on a click. A mouse-only walker prints "nothing answers the mouse" at
such a scene for turn after turn, which reads as a stuck movie and is not —
Rating's arrival scene is 335 frames the mouse cannot leave and one Enter does.

**Which keys is a question about the title, and the title answers it.**
`tools/lib/key_sites.gd` reads the Lingo out of a container's `CASt` records and
reports every literal `the key = "x"` character and `the keyCode = n` Mac code it
tests. Use that, never a hand-written list: the list in `director_keys.gd` was
swept out of `reference/lingo/`, which is Piposh 2 and nothing else, and it
called F10 free while Rating tests it at 48 sites.

Presses go in through `preview.call("_dispatch_key", event)` and a matching
`_dispatch_key_up`, the way `tools/key_chain.gd` and `tools/key_polling.gd` drive
them. Going in through `Input.parse_input_event` instead makes the walk press the
preview's own F-key bindings — SKIP, pause, restart — as it goes.

## "Waiting for input" is recurrence, not stillness

The obvious rule — act on a state only once it has stopped changing — fails on
the first screen of the corpus. Rating's main menu *animates*, cycling frames
504-521 for ever, so no two turns running ever see the same frame and a walker
gated on stillness watches the menu until its budget runs out.

What separates the two is that **a movie going somewhere visits new frames and a
movie waiting comes back round.** Act once a state recurs within this visit to
this movie. Keep a safety valve for the scene so long that nothing recurs.

## Spend a hotspot per marker region, not per frame

A room in these titles is a *marker*, and the frames under it are its animation.
A hotspot that sits on every frame of a room — Rating's inventory bag is on all
of `thehall**` — is a brand-new button on every frame under a per-frame key, and
the walk spends its entire budget opening and shutting the same bag. Key what has
been pressed by `(movie, marker, channel)`.

## A detector that fires on one frame is noise

Every anomaly detector needs a persistence rule, and picking one is the whole
design. Flagging a stage with nothing on it *per frame* reported four movies
(`BADEND`, `BLASNAKE`, `NAVIGAT3`, `MAINMENU-old`) that `liveness_sweep` -- which
requires a window of consecutive unexplained ticks -- calls healthy, because a
movie may legitimately open on an empty frame and fill it a tick later. With a
30-inspection run required, one survived, and that one turned out to be an
unreferenced leftover container no script in the corpus mentions.

The same trap in a different shape: deciding a container "would not open" by
comparing `movie_name()` to the file asked for called **17 of Rating's 81**
unopenable. A movie that hands off to another on `startMovie` has opened
correctly -- the boot movie of every title does exactly that. Assert the score
loaded, which is what `liveness_sweep` settled on.

## Four things that will look like hard bugs and are yours

Every one of these produced a confident false finding in one session.

**A walker that presses the menu's Exit line.** `quit`/`halt` set the host's
`stopped` *and* call `lingo_quit`, which does `set_process(false)`
unconditionally and only takes the tree down when the preview is
`get_tree().current_scene` — which it is in a real game and is **not** under
`--script`. So the walk carries on clicking a player that has stopped processing,
and the next movie it opens sits on frame 0 for ever with its art on screen. That
is indistinguishable from a hard freeze. Stop the walk on `stopped`, and use
`--avoid <movie>:<channel>` to keep it off the button entirely.

**An argument name the engine already owns.** `--boot` is
`DirectorPaths.load_config`'s flag for which container to start. A tool that took
it for its own purpose booted nothing at all and still wrote 24 screenshots — of
an empty stage, captioned as if they were the game. Check `tools/lib/args.gd` and
the config readers before naming a flag.

**A detector wired before the autoloads exist.** `_init` on a `SceneTree` runs at
construction, earlier than autoloads are added to the tree, so
`root.get_node_or_null("GameState")` returns null there and a `log_message`
listener connects to nothing. The collector then reports clean while `Audio miss`
lines scroll past on stdout. `await process_frame` first.

**A harness default from another title.** `tools/window_renders.gd` defaults
`--window` to `joke.dxr`, which is Piposh 2's. Run it against Rating without
`--window` and it reports `joke.dxr -> not found`, which reads exactly like a
missing-asset bug in Rating. Pass the window the movie under test actually opens.

The general rule, which is `porting-fidelity-verification`'s: when something
looks broken, prove the instrument was pointed at the game before explaining what
the game did.

## Cold-open findings must be re-reached by playing

`liveness_sweep` opens every container cold, so it never arrives anywhere
carrying the globals a real boot sets. `bugs.md` 36 carries two corrections that
both come from exactly that — nine talk clips that looked like an inescapable
two-frame loop on a cold entry and were not. Before filing anything the sweep
found, reach it with `qa_walk` and confirm it survives.

The converse also happens and is worth more: a movie that is **healthy cold and
broken when played** is a real finding no existing harness can see, because the
difference is state the boot sets.

## Read the pictures, and get a name before calling art authentic

The walk's PNGs are the only view of the renderer anything here produces. Look
for the shapes this port has actually shipped: art stretched on one axis, a face
inside a rectangle of paper colour (Copy ink that never got its matte), a film
loop's children drawn out of the wrong cast, a character drawn in front of what
should hide him.

When something looks wrong, do **not** settle it by checking the port against the
data it was handed — that is circular, and the duplicated-guest report passed
three consistency checks that way before one member-name lookup reversed it. Read
the member name out of the container; it is the cheapest source from outside the
pipeline and the most underused.

## What to do with what you find

Anything found and not fixed goes in `bugs.md` with the evidence and a command
that reproduces it, per `AGENTS.md`. Check both `bugs.md` and
`docs/bugs-closed.md` first — resolved entries keep their number and move — and
`git log -S` on the identifier before believing either, because this repo's queue
is stale in both directions.
