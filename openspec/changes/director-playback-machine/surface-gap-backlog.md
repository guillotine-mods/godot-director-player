# Surface gap backlog

The starting backlog for the bound Lingo surface, from task 3.9. Everything here
is output of `tools/check_surface_coverage.gd`, not judgement:

```
godot --headless --script tools/check_surface_coverage.gd          # the static check
godot --headless --script tools/check_surface_coverage.gd -- play  # and a played session
```

Counts marked `corpus r=N w=M` come from `data/lingo_vocabulary.json`, which
records how often the game's own scripts read and write each name. They are the
whole reason this list can be ordered: a missing binding nothing uses is not a
gap worth anyone's afternoon, and a bound name written 624 times into state
nothing reads is the most expensive item on the page.

## Headline

| category | vocabulary | bound | read | write | declared unsupported |
|---|---|---|---|---|---|
| sprite | 52 | 19 | 16 | 15 | 33 |
| movie | 156 | 25 | 24 | 5 | 131 |
| member | 80 | 5 | 4 | 2 | 75 |
| builtin | 206 | 29 | — | — | 0 |

The builtin row counts 243 vocabulary names less the 35 the game defines as its
own handlers and the 2 parser artefacts. Builtins have no declared-unsupported
table: every one of the 177 unbound names is a hole rather than a decision, and
that asymmetry is itself an item below (B5).

**These numbers are not the check's pass condition.** The check's category
comparison is a staleness guard — the four tables partition their vocabulary by
construction, so "unclassified: 0" stays 0 until the vocabulary is regenerated
and a new name lands in no table. The backlog is what follows.

## A. Bound, and does nothing (reachability) — **SUPERSEDED, see the note**

> **This section was measured before `SpriteChannel` landed on `main`, and it is
> now wrong.** It reported 806 corpus writes reaching state nothing draws, of
> which `memberNum` was 624. That was true of the code it was run against:
> `movie_player.draw_current_frame` built every sprite from the score frame.
>
> It no longer does. It reads `runtime.channel_sprites()` and its own comment
> names this exact defect: *"Reading the score frame here is what made `set the
> memberNum of sprite N` and every Lingo-driven move invisible: the score has no
> idea a script moved it."* `memberNum`, `castNum`, `member`, `castLibNum`,
> `locH`, `locV`, `width`, `height` and `ink` all now reach the draw through
> `SpriteChannel`, and the `puppet` override dictionary is gone.
>
> `tools/check_surface_coverage.gd` has been corrected and is the current answer;
> the figures below are kept only as the before-picture. Four properties —
> `cursor`, `constraint`, `moveableSprite`, `volume` — are now marked
> `unverified` there rather than reclassified, because their consumers have not
> been re-traced since the change.
>
> The lesson is the same one this backlog was built to enforce, turned on itself:
> a hand-maintained verdict about what the code does has a shelf life, and this
> one went silently wrong the moment the renderer changed underneath it. It was
> caught by rebasing, not by the check.



The largest item, and the one that would be invisible in a report that counted
bindings. `LingoHost.puppet` is a dictionary of per-channel property overrides
with no consumer outside `lingo/lingo_host.gd`. `director/movie_player.gd`
builds every sprite it draws from the score frame — `cast_lib`, `cast_id`, `ink`,
position and size at `director/movie_player.gd:409-443` — and asks the runtime
only `is_channel_hidden` at `:403`. `director/stage_canvas.gd` and
`director/render_model_loader.gd` never mention Lingo at all. The check asserts
that mechanically and will fail if it stops being true.

So of the 15 sprite properties the port accepts writes for, two reach the
renderer, two more reach hit-testing only, and the remaining eleven reach
nothing: **806 corpus writes land in state nothing outside the host reads**.

| property | corpus | state |
|---|---|---|
| `visible` | w=1283 | consumed — `set_channel_visible` → `_lingo_hidden` → the draw |
| `puppet` | unused | consumed — sets `puppeted`, which gates the entry blanking |
| `locH` / `locV` | w=347 / w=397 | partial — hit-testing only, via `sprite_rect` → `rollover`/`intersects`/`within`. The drawn position still comes from the score. |
| `memberNum` | **w=624** | INERT — the sprite-swap mechanism the game animates with |
| `cursor` | w=155 | INERT — no cursor is set from it |
| `moveableSprite` | w=15 | INERT — the port has no dragging |
| `constraint` | w=10 | INERT — nothing is constrained |
| `volume` | w=2 | INERT — no audio path reads it |
| `castNum`, `castLibNum`, `member`, `ink`, `width`, `height` | unused | INERT |

Movie writes are better, but only because there are five of them:
`soundLevel` drives the audio bus and `keyDownScript` is run by
`director_runtime.gd:554`. `searchPath`, `centerStage` and `exitLock` are stored
so a read agrees with the write, which two of them say in their own source
comments. The four `WINDOW_FIELDS` are accepted and dropped; `windowType` alone
is written 20 times.

- **A1** `memberNum`/`castNum`/`member` writes must reach the renderer. This is
  the sprite-swap mechanism: 624 writes currently change nothing on screen.
- **A2** `locH`/`locV` writes must move the drawn sprite, not only its hit box.
- **A3** `cursor` (155 writes) — decide it is a divergence and declare it, or
  implement it. Right now it is neither.
- **A4** `ink`, `width`, `height`, `castLibNum` writes: unused by this corpus, so
  the cheapest correct answer may be to declare them unsupported rather than to
  accept a write that does nothing.
- **A5** `moveableSprite`, `constraint`, `volume`: same decision, smaller stakes.

Phase 5 owns the fixing. What this file owns is that none of it counts as
covered until then.

## B. Unbound, and the game uses it

- **B1** movie `the stage` — **corpus r=135**, and in `MOVIE_UNSUPPORTED`. The
  most-used name the port declares it will not bind. Every read reports a
  diagnostic and answers VOID. Worth confirming the 135 uses are all
  `tell the stage`-shaped before leaving it declared.
- **B2** Builtins the corpus calls and nothing binds:
  `pause` (5), `castLib` (4), `printFrom` (4), `when` (4), `quit` (9),
  `dontPassEvent` (2), `dont` (2), `pass` (2), `saveMovie` (2), `stopEvent` (1),
  `setMoviePath` (1), `unloadMovie` (1), `www` (1).
  `pass`/`dontPassEvent`/`stopEvent` are event-propagation control and change
  what runs next, so they are the sharp end of this list; `quit` and `printFrom`
  are desktop Director and want a declared divergence instead.
- **B3** Builtins nothing in the corpus calls: 164 names, listed by the check.
  Not a backlog so much as the size of the language.
- **B4** member `editable` — bound to write (w=5), not to read.
- **B5** There is no `BUILTIN_UNSUPPORTED` table, so a builtin the port decides
  not to implement cannot be declared, and the runtime reports it bare — as
  "not done yet". Sprite, movie and member all have one. Until builtins do, the
  DECIDED/not-yet split below is structurally blind on this category.

## C. Bound in one direction only

The vocabulary records no read/write tags — see `not_taken` in its `sources` —
so this cannot say whether Director permits the other direction. It says the
port has no binding there. Ordered by whether the game cares:

- `the clickOn` (r=396), `the mouseH`/`mouseV` (r=85 each), `the movieName`
  (r=35), `the moviePath` (r=32), `the keyCode` (r=30), `the frame` (r=13),
  member `name` (r=181) and member `memberNum` (r=85): read-bound, not
  write-bound, and read-only in Director too. Informational.
- sprite `cursor` (w=155), `constraint` (w=10), `volume` (w=2) and member
  `editable` (w=5): write-bound, not read-bound. A script that sets one and
  reads it back gets the value out of the puppet override, so the missing read
  binding is invisible until a *different* handler asks.
- sprite `left`/`top`/`right`/`bottom`: read-bound only, deliberately. Director
  derives them from location and size, so a write has to move the sprite, and
  the override table has no way to say that. Corpus-unused, so this stays a
  note. It becomes real work if A2 lands.

## D. Bound, but not in the vocabulary

Five names the port dispatches that the recorded vocabulary does not enumerate
as builtins. None is invented, and the check says so rather than counting them:

- `intersects`, `within` — Lingo operators, routed through `call_builtin` from
  the binary-operator arm. ScummVM keeps them in the lexer, not in
  `lingo-builtins.cpp`.
- `close` — `close window`, a window verb.
- `updateLock` — `the updateLock`, a movie property the port binds as a no-op
  builtin. Also in `MOVIE_UNSUPPORTED`, so the port answers it in two places
  with two different stories. Worth one of them being deleted.
- `goto` — the port's own alias for `go`.

The property categories bind nothing outside their vocabulary. The four
`WINDOW_FIELDS` resolve through `other_entities.window`, which is the point of
the three-way test: real Lingo about an entity the port does not model is not
the same as a name the port made up.

## E. What the played session reached

Two runs, both against the working tree of this session:

- `godot --headless --script tools/smoke.gd` — 20 ok, **0 checks failed**, and the
  206 pre-existing ERROR/SCRIPT ERROR lines. Unchanged, so what follows was not
  measured over a broken tree. Smoke has no diagnostics sink of its own, which is
  why the sweep below lives in the coverage check.
- `godot --headless --script tools/check_surface_coverage.gd -- play` — smoke's
  opening path (the menu, New Game, the intro, DAY1) and then a sweep:
  **72 movies entered, 421 room labels entered, 452 hotspots activated, 144s**,
  capped at 10 labels and 6 hotspots per movie. The RNG is seeded, so two runs
  are comparable, which the spec asks of the diagnostic set.

Result: **150 distinct name+location entries, 0 dropped at the cap.**

`host.unhandled_names()` came back **non-empty** —
`castlib go "000" go "wlkcur1" objplc of pause peoplefunk quit sfl sfl2` — where
an earlier, narrower harness (a strtgame intro plus four DAY1 rooms) reported it
empty. The width was worth building.

**Not one `(unsupported)`-marked name was reported in the whole session.** All
239 declared divergences went untouched by 452 clicks, `the stage` (r=135)
included. The DECIDED bucket being empty is a fact about this sweep, not about
the port, and the check proves the mark works by exercising it deliberately:

```
blend      DECIDED   corpus unused              (in SPRITE_UNSUPPORTED, so marked)
zorble     not yet   in no vocabulary           (invented name, reported bare)
volume     not yet   entity soundentity, not modelled
```

That last line is the three-way test doing its job: `the volume of sound 1`
reaches `get_member_prop` and is real Lingo about an entity the port does not
model, not a missing member binding.

**No sprite, movie or member property diagnostic fired at all.** Every property
access those 421 rooms made was bound. That is a genuine result and a thin one:
see the honesty section.

- **E1** `go "000"` ×42 and `go "wlkcur1"` ×3 — navigation to a marker that
  resolves to nothing, from `BehaviorScript 207/exitFrame` and
  `BehaviorScript 42/exitFrame`. Not a vocabulary gap; a broken target.
- **E2** `castlib` ×120, `of` ×120 and unset `savenames` ×120, all from
  `BehaviorScript 24/exitFrame` and `BehaviorScript 38/exitFrame` — one
  expression producing three diagnostics in three categories. `of` is a keyword
  arriving as a bare identifier, and the manifest records only `then` and `to`
  as parser artefacts, so either that set is incomplete or this is a distinct
  parse failure. SAVELOAD's file list, by the look of the scripts.
- **E3** `pause` ×15, `quit` ×8 — real Lingo builtins, unbound, and reached in
  ordinary play. Both want a decision (B5: builtins cannot currently record one).
- **E4** `peoplefunk` ×15 reported as an unbound *builtin*, but it is one of the
  35 handlers the game defines itself. Reported here means the handler table did
  not resolve it from where it was called: a scope question for task 4.x, not a
  missing builtin. The check labels it rather than counting it.
- **E5** `enterFrame` ×14029, `exitFrame` ×5060, `mouseDown` ×116 as EVENT
  entries. `lingo_engine.gd:401` reports whenever neither the frame script nor a
  movie handler resolves the event — which is ordinary Director playback on most
  frames. As written, the EVENT diagnostic cannot distinguish "no handler on this
  frame" from the spec's "an event the runtime does not bind", and it dominates
  the occurrence counts. There is also no recorded event vocabulary to compare
  against: `categories_order` is sprite, movie, member, builtin.
- **E6** 19 `unset_variable` names, led by `nextroomdata` ×2591, `savepath` ×370,
  `wreck` ×121 and `firsttalk` ×54. These are the game's own globals read before
  assignment, correctly kept out of the unbound-name list. Backlog only in the
  sense that a few may be globals the port should own.

## Honesty about this backlog

- The static half is complete: it does not depend on anything being played, and
  a name no script uses is still reported.
- The played half is broad and shallow, and where it is thin the harness is
  thin, not the surface. It enters 72 movies but takes 10 labels and 6 hotspots
  from each; it carries no inventory, advances no story flag, presses no key and
  drags nothing. So "no property diagnostic fired" most plausibly means the
  paths that touch exotic properties need story state this sweep never builds —
  the 33 + 131 + 75 declared-unsupported names are unbound whether or not a
  click reached them, which is exactly why the static half does not wait for
  one. Anything not listed in E was not exercised; it was not proven absent.
- `windowType`'s 20 corpus writes come from the manifest's `ambiguous` list,
  which by definition means the generator could not attribute the name to one
  entity. Treat it as an upper bound.
- `member_prop` over-collects. `lingo_interpreter.gd:536` and `:551` route every
  dot and `of` access on a non-sprite, non-member expression into
  `get_member_prop`, so a name reported there is not necessarily a member
  property. `the volume of sound 1` arrives that way. The 75 unbound member
  names are not 75 missing member bindings.
- Reachability classification is a hand-written table in the check, guarded by a
  mechanical assertion that the draw path does not read Lingo sprite state. The
  guard catches the classification going stale; it does not derive it.
