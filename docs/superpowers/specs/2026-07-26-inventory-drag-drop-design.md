# Inventory Drag-and-Drop Design

Closes GitHub issue #1, "Implement inventory selection and item-based puzzle
interactions", across every screen that carries the inventory bar.

## Problem

The port can display inventory items and apply the exported add/remove
operations, but nothing else. Players cannot use an item on anything, and no
conditional puzzle logic runs.

The cause was a missing source of truth rather than a regression. The export in
`assets/render_model/*/frames.json` carries only what a small lifted grammar
extracted from the original Lingo: navigation, sounds, and unconditional
inventory add/remove. Every conditional in the game lived solely in the Lingo,
which this repository had no copy of, so behaviour was reconstructed by
inference. That is why several `data/movie_context.json` entries carry a
`confidence` field. The web predecessor had the same three inventory functions
and no more, so this is unbuilt work, not something the Godot migration broke.

The Lingo is now committed at `reference/`. See `reference/README.md` for
provenance and layout. Note that `docs/EXTRACT_FROM_INSTALLER.md` is stale on
this point and still claims the Lingo was never recovered.

## The original mechanism

Issue #1 asks for "item selection/deselection". The game has no selection state.
Inventory is drag-and-drop, and the design must follow that instead.

`reference/lingo/MASTER/External/MovieScript 80 - displayobject.ls` puppets
sprites 103 to 110 from `objectsfield` lines 1 to 8, indexed as `line i - 102`.
An occupied slot receives `moveableSprite = 1` and cursor `[hand1, hand2]`, so
Director itself drags the icon. An empty slot receives member `object0` and no
moveableSprite.

The drop handlers are `reference/lingo/MASTER/External/BehaviorScript {52, 93,
94, 97, 108, 110, 111, 128, 129, 135}.ls`, one variant per room. `mouseDown`
stores the slot's home position into globals `objectxx` and `objectyy`. `mouseUp`
tests `sprite the clickOn intersects <target>`:

- sprite 100 is Piposh's head. Swap its member to `piphead2`, play
  `pi<item>.aif`, restore `piphead1`. This is the examine interaction.
- sprites 18 to 21, 36 and 37 are characters. Call `objecttalktime(<item>)`,
  which sets `usfulobject` and jumps to the room's `*talk` marker.
- other per-room sprites (8, 9, 15, 34, 35 among them) are world objects,
  usually gated on `.visible = 1`.

Afterwards it unconditionally restores the icon to `objectxx`/`objectyy`.

Two consequences shape the acceptance criteria. An invalid target needs no
failure branch, because nothing intersects, the icon springs home, and no sound
plays. And item consumption is always a mutation of `objectsfield`, never a
sprite position, so the visual snap-back is independent of whether the puzzle
succeeded.

Interactions are also arrival-gated. `walkonby()` walks toward `egozh`/`egozv`
with `whatodo` as a `"stand"`/`"walktime"` state machine, so clicking a distant
target walks first and acts on arrival. `director/puppet_controller.gd` already
implements the walk; the gating is what is missing.

## Scope

Screens carrying the inventory bar on channels 103 to 110, by frame count:
`DAY1` 2773, `NIGHT1` 2640, `SEA1` 1863, `HOTEL1` 1448, `AIR1` 1005, `SHUFFLE`
147 partial, `ARCADE1` and `ARCADE2` 20 frames with only 3 channels, and five
movies with a single stray frame. Exported inventory operations exist in `DAY1`,
`HOTEL1`, `NIGHT1` and `SEA1` only. Re-verify these figures rather than trusting
them; they were measured once.

"All screens" means every one of the above behaves per its own Lingo, not that
`DAY1` works and the rest are assumed to follow.

## Current implementation

- `autoload/game_state.gd:194-243` holds `objects_field` plus add, remove and
  the channel-to-member override. No selection, no drag, no use.
- `director/director_runtime.gd:673` `_apply_inventory_ops` applies exported ops
  unconditionally.
- `director/director_runtime.gd:818` `clickable_sprites` drops any sprite whose
  `on_click` has no nav, inventory or sounds, which is why the slot channels are
  currently unclickable.
- `director/movie_player.gd:362` `draw_current_frame` draws slot icons with a
  special case near line 427; `:59` `_gui_input` feeds clicks through
  `InputRouter`.

## Gaps beyond the issue text

Include these; they are part of making the screens correct.

- `reference/lingo/MASTER/External/CastScript 57 - invright.ls` and
  `59 - invleft.ls` scroll the 30-line `objectsfield` through the 8 visible
  slots, playing `moveinv.aif` on success and `stukinv.aif` at the end. Nothing
  in this port exposes items past line 8, so they are unreachable rather than
  merely off-screen.
- `reference/lingo/MASTER/External/MovieScript 78.ls` (`searchfunk`) is
  table-driven off `field "searchinfo"` with columns name, x, y, action and sound
  family, playing a random variant from the family. This is the authoritative
  version of the inferred `click_flags` and `sprite_gates`.
- The port has no equivalent of `field "Dprocess"` (per-day task tracker) or
  `field "points"` (score). Both are written by the pickup scripts, for example
  `reference/lingo/DAY1/wonder/CastScript 220 - a1.ls`.
- The 112 distinct unconditional `remove` operations in the export are a latent
  bug: they consume the item with no check that the use was correct.

`reference/chunks/<MOVIE>/STXT-*.bin` hold the data tables in Director
text-member format and need a small parser. `STXT-760` documents the
`clickoncharacter` schema, `STXT-793` and `STXT-795` hold the `Dprocess` task
list, `STXT-668` the `syz` perspective mapping.

## Open decision

Recommend an approach with reasoning before writing code.

1. Lift the conditionals into `frames.json` by extending the exporter. The
   generator (`lingo_nav.py`) lives in the archived private repo
   `guillotine-mods/Piposh2-Web-Alpha`, so this means vendoring it here or
   reimplementing it.
2. Interpret a Lingo subset at runtime, which is open issue #3 and would make
   issue #1 fall out of it.

Drop targets are per-sprite, per-room and visibility-gated, which flattens
awkwardly into `on_click` entries but sits naturally in a table keyed by movie,
room, slot behaviour and target sprite. A hybrid is worth considering. Whichever
route wins, retire the `movie_context.json` entries the Lingo now covers and
state which were retired.

## Constraints

- Read the Lingo rather than inferring behaviour. Where the two disagree, the
  Lingo wins, and `.lasm` beside each `.ls` is the ground truth when a decompile
  reads oddly.
- New state must round-trip through `game_state.gd` `to_dict`/`from_dict` and
  remain editable in `ui/save_editor.gd`.
- Follow the repo conventions: design docs in `docs/superpowers/specs/`, plans in
  `docs/superpowers/plans/`, tests in `tests/*.gd`. Run the full suite after
  multi-file changes and confirm coverage did not regress.

## Acceptance

From issue #1, adjusted for the drag mechanism:

- Items can be dragged from any occupied slot, with the hand cursor, on every
  screen listed under Scope.
- Valid targets produce the original outcome; invalid targets snap the icon home
  silently.
- Items mutate `objectsfield` correctly and world hotspots reflect puzzle state.
- Items past the eighth slot are reachable through the scroll buttons.
- Representative puzzles from every day are completable without the Save Editor.
