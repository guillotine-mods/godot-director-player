# Inventory Drag-and-Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make inventory items draggable out of the eight HUD slots on every screen that carries them, resolve drops against the original Lingo drop handlers, and snap the icon home in silence when nothing valid is under it.

**Architecture:** A declarative drop-rule table in `data/inventory_drops.json`, transcribed from the ten `MASTER` drop behaviours with a Lingo citation per rule, read by a new `director/inventory_drops.gd` (same shape as `director/movie_context.gd`). Drag state lives in a new `director/inventory_drag.gd` owned by `DirectorRuntime`; `InputRouter` grows press/release/motion so the Director `mouseDown` → drag → `mouseUp` shape can be expressed at all. No exporter changes, no Lingo interpreter.

**Tech Stack:** Godot 4.7 (GDScript), headless `SceneTree` test scripts, JSON data files under `data/`.

> **Executed 2026-07-26 with the test steps waived by the user** ("execute the plan, no need to tdd or tests at all right now"). Every task's implementation steps were applied; the `tests/test_inventory_drag.gd` steps were not. Behaviour was verified instead by a throwaway headless script covering all eight checks the suite would have made (master lib per movie, slot member lookup, drag begin on occupied vs empty slot, icon follows cursor, examine head swap and restore, NIGHT1 ladder placed and consumed, non-matching item not consumed, unknown target silent, mirolo `sciser`-vs-wildcard routing, and label existence for `cutmirolohair` / `mirolospk` / `fatspkroomb`). It reported `VERIFY OK` and was then deleted. **The test-writing steps below remain outstanding work.**
>
> Note for whoever picks that up: autoloads are not compile-time globals in a script run via `godot --headless --script`, because the script loads before the tree exists. Fetch them with `root.get_node("GameState")`. Also, `class_name` on a new script is not visible to `--script` runs until the editor rescans and rewrites `.godot/global_script_class_cache.cfg`, which is gitignored.

## The open decision, decided

The spec asks for a recommendation before code. **Hybrid: a hand-authored, Lingo-cited rule table consumed at runtime.** Neither of the two options as written:

- **Extending the exporter is blocked and mis-shaped.** `lingo_nav.py` lives in the archived `guillotine-mods/Piposh2-Web-Alpha`, which is not on this machine (`~/Projects/_private_projects` holds only `piposh2-godot`, `mdl-texture-editor`, `shahf11-blog`), so option 1 pays a vendoring or reimplementation cost before a single item can be dragged. It also flattens badly: a drop rule is keyed by (movie, target sprite, item, visibility), while `frames.json` keys behaviour by *clicked* sprite per frame. DAY1's `frames.json` is already 18 MB across 2784 frames; the same rule would be duplicated into every frame of the room.
- **A runtime Lingo interpreter is issue #3, not a prerequisite.** It needs a parser plus a Director object model (puppeting, `intersects`, `play frame`, sound channels, fields, markers). Real, but it should not gate issue #1.
- **The table is the repo's existing convention.** `data/movie_context.json` says "Hand maintained" in its own header, and `data/walk_doorways.json` does the same job for exits. The whole game has **ten** drop handlers, each under 40 lines. Transcribing them is hours, not weeks, and a future interpreter can emit the same table.

**Why no VWSC extraction.** The score records which behaviour script sits on each sprite channel, and that field was dropped by the export (`assets/render_model/*/frames.json` sprite records carry only `channel, cast_lib, cast_id, x, y, width, height, ink, sprite_type, fore_color, back_color, has_image, loc_h, loc_v`). It is not needed, because the Lingo self-gates:

- `objecttalktime` dispatches on `marker(0)`, so the room set is in the handler, not the score.
- `intersects` is a rect test against a *sprite channel*, so a drop rule keyed by target channel plus `requires_visible` reproduces it without knowing which behaviour was attached.

Escape hatch if a specific room turns out wrong: parse `VWSC-*.bin` from the local ProjectorRays dump (`~/Downloads/piposh2extracted/piposh2-projectorrays/PIP2DATA/<MOVIE>/<MOVIE>/chunks/`, 48-byte sprite records per `assets/render_model/<MOVIE>/summary.json`) for the sprite script fields. **Do not build it now.**

## Scope: this is plan 1 of 6

The spec covers six independently testable subsystems. This plan is the first two, which together satisfy acceptance criteria 1 and 2 and are playable on their own.

| Plan | Subsystem | Status |
|------|-----------|--------|
| **1 (this file)** | Drag input, drop dispatch, examine, world-object drop rules needing no new state | write + execute now |
| 2 | `objecttalktime` / `talkproc`: item-on-character conversations. Needs the `*-ans` STXT tables, the `init` letter per character, and speaker-sprite sequencing | follow-on |
| 3 | `CastScript 57 - invright` / `59 - invleft`: scroll the 30-line field through the 8 visible slots | follow-on |
| 4 | `MovieScript 78` `searchfunk` + `field "searchinfo"` STXT parser; retires the inferred `click_flags` / `sprite_gates` | follow-on |
| 5 | `field "Dprocess"` + `field "points"`; unblocks `planefunk` (AIR1) and `ishspec` (HOTEL1), which both write them | follow-on |
| 6 | Suppress the 112 unconditional `remove` ops | follow-on |

On plan 6: the removes are baked into generated `frames.json` and there is no exporter here, so the fix is a runtime suppression path in `_apply_inventory_ops` (`director/director_runtime.gd:673`), **not** an asset edit. Nobody should try to regenerate assets.

Deliberately **not** in this plan, with reasons:

- **AIR1 `planefunk` and HOTEL1 `ishspec`** drop rules. Both write `field "points"`, and `ishspec` also reads and writes `field "Dprocess"` line 6. They belong to plan 5.
- **`BehaviorScript 128`** (drop `tools` on sprite 9 → `zzz.aif`, reveal sprites 7 and 8). Its movie cannot be determined from the Lingo: `zzz.aif` appears in no other script, and the handler names no marker. This is the one case that needs the VWSC escape hatch. It is recorded in the table as disabled.

## Global Constraints

- Godot **4.7**. `String(variant)` is invalid; use `str()` (see `_s()` in `director/director_runtime.gd:69`).
- The Lingo at `reference/lingo/` is the source of truth. Where it disagrees with `data/movie_context.json`, the Lingo wins. `.lasm` beside each `.ls` is ground truth when a decompile reads oddly.
- Every rule in `data/inventory_drops.json` carries a `lingo` field naming the file it was transcribed from.
- New persistent state must round-trip through `GameState.to_dict()` / `from_dict()` and stay editable in `ui/save_editor.gd`.
- Tests are headless `SceneTree` scripts under `tests/`, run as `godot --headless --script tests/<name>.gd`, printing `PASS: <suite name>` and `quit(0)`, or `push_error` per failure and `quit(1)`. Follow `tests/test_walk_doorways.gd`.
- Full suite after multi-file changes: all four of `tests/test_director_runtime.gd`, `tests/test_walk_doorways.gd`, `tests/test_day1_navigation.gd`, and the new `tests/test_inventory_drag.gd` must pass.
- Docs in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/`.

## Facts established during planning (do not re-derive)

Verified against the repo; the spec asked for these to be re-checked and they hold.

**Scope figures reproduce exactly.** Frames carrying channels 103-110, measured from `assets/render_model/*/frames.json`:

| Movie | Total frames | Slot frames | Slot channels | Exported inventory ops |
|---|---|---|---|---|
| DAY1 | 2784 | 2773 | 8 | 555 |
| NIGHT1 | 2646 | 2640 | 8 | 240 |
| SEA1 | 1982 | 1863 | 8 | 2510 |
| HOTEL1 | 1524 | 1448 | 8 | 60 |
| AIR1 | 1006 | 1005 | 8 | 0 |
| SHUFFLE | 208 | 147 | 8 | 0 |
| ARCADE1 | 333 | 20 | 3 | 0 |
| ARCADE2 | 1198 | 20 | 3 | 0 |
| DTCDAY2, GOLDDEAD, ISHDAY1, MIROLO, TOFIRCPT | n/a | 1 each | 8 | 0 |

**The `master` cast library index is per-movie, and the port hardcodes 2.** From each `summary.json`: DAY1 `2`, NIGHT1 `2`, HOTEL1 `3`, SEA1 `4`, AIR1 `3`, SHUFFLE `2`, ARCADE1 `2`, ARCADE2 `2`. `assets/inventory_items.json` declares `"cast_lib": 2` and `GameState.inventory_member_for_item()` returns it unconditionally, so HOTEL1 would fetch slot icons from the `hotel` cast, SEA1 from `bysea`, AIR1 from `byair`. Those casts *do* hold members 9 and 30 (`assets/render_model/cast_registry.json`), so it would draw the wrong bitmap rather than fail visibly. Task 1 fixes this; it is a prerequisite for "drag from any occupied slot on every screen".

**Found during execution, and worse than the above:** `inventory_catalog.slot_channels` comes out of `JSON.parse_string` as **floats**, and Godot's `Array.find(103)` does not match `103.0`. So `inventory_override_for_channel()` returned `{}` for every channel and **no item icon was ever drawn in any movie** — the slots always rendered their score member, which happens to be `object0`. That masked the cast-library bug entirely. `GameState.slot_channels()` now coerces to int once. Verified against the real catalog: `find 103 -> -1` before, `0` after.

**Members needed.** `master` cast: `object0` = 9, `piphead1` = 54, `piphead2` = 55 (joined via `cast_resource_id` 36 / 173 / 42 against `assets/render_model/cast_registry.json` → `casts.master.members`). Channel 100 carries `master` 54 in all five movies, on 2771 / 2638 / 1448 / 1863 / 1005 frames.

**The hand cursor bitmaps are not usable.** `hand1` / `hand2` are members of each movie's *internal* cast (DAY1 `1:201` / `1:202`, NIGHT1 the same, HOTEL1 `1:194` / `1:195`, SEA1 `1:196` / `1:197`, AIR1 `1:194` / `1:195`), and they decode to 5×6 and 8×8 pixels. A Director cursor cast pair is 1-bit 16×16, so the BITD decode for these members is wrong. **Use Godot's `Control.CURSOR_POINTING_HAND`** and record why. Swapping in the real bitmap later is a one-line change once the decode is fixed.

**Audio resolves by stem, so Lingo sound paths do not matter.** `AudioDirector.resolve_path()` indexes every WAV under `assets/audio/` by basename and ignores directories, so `soundspath("days")` / `("nights")` / `("air")` juggling in the handlers is a no-op for the port. Every needed stem exists: all `pi<item>` except `pistick`, plus `zzz`, `fatobjb`, `mirolo1`-`mirolo5`, `planpart`, `moveinv`, `stukinv`, `found`, `pbag`. There are no duplicate `pi*` basenames across families.

**Talk is live in only three movies, which dissolves the "union of character sprites" risk.** `objecttalktime` exists per movie (DAY1 `wonder/MovieScript 248`, NIGHT1 `night2/MovieScript 248`, HOTEL1 `book/MovieScript 203`, AIR1 `island2/MovieScript 203`, SEA1 `wonder/MovieScript 989`) and dispatches on `marker(0)`. Cross-checking each handler's markers against that movie's `labels`:

- DAY1: all six `*go` markers **and** all seven `*talk` labels present → talk live.
- NIGHT1: the six `*go` markers exist but **not one** `*talk` label → `go("fieldtalk")` has nowhere to go; NIGHT1 has no item-talk.
- HOTEL1: all five `*go` and all five `*talk` present → talk live.
- AIR1: its handler is a verbatim copy of HOTEL1's and **none** of `receptgo`/`lobygo`/`roomago`/`roombgo`/`roomcgo` exist in AIR1 → dead code.
- SEA1: `shore1go` → `instruct`, both present → talk live, one room.

So the differing character sets across handlers (`108`: 18-21 plus 36,37; `52`: 18-21; `93`/`129`: 34 or 18) never need to be unioned across movies. Plan 2 keys them per movie, with the optional `rooms` qualifier this plan's schema already carries.

**One correction to carry into plan 2:** the fall-through branch of `objecttalktime` is not a no-op. It still puppets 18-21, repositions sprite 30, and sets `usfultalking = 1` / `usfulobject = x`. A later `talkproc` in that movie can therefore pick up a stale `usfulobject`.

**`random(4) + 1` is 2..5, not 1..4.** `BehaviorScript 111` plays `mirolo2`..`mirolo5`. `mirolo1.wav` exists but the original never plays it there.

## File Structure

| File | Responsibility |
|---|---|
| `data/inventory_drops.json` | **create**: declarative drop rules per movie, each with a `lingo` citation. Plus slot channels, head channel, and head member numbers. |
| `director/inventory_drops.gd` | **create**: loads and queries the table. Mirrors `director/movie_context.gd`. |
| `director/inventory_drag.gd` | **create**: drag state: which slot, which item, home position, current position. No rendering, no rules. |
| `autoload/input_router.gd` | **modify**: add `stage_press` / `stage_release` / `stage_drag` on top of the existing `stage_click` / `stage_hover`. |
| `director/movie_player.gd` | **modify**: `_gui_input` press/release/motion; draw the dragged icon at the cursor; hand cursor over occupied slots. |
| `director/director_runtime.gd` | **modify**: `begin_inventory_drag` / `update_inventory_drag` / `end_inventory_drag`; `master_cast_lib()`; the one-frame `piphead2` swap; rule application. |
| `director/render_model_loader.gd` | **modify**: `cast_lib_index(name)`. |
| `autoload/game_state.gd` | **modify**: `inventory_member_for_item` / `inventory_override_for_channel` take the master lib index; add `item_in_slot(slot_index)`. |
| `data/movie_context.json` | **modify**: gate NIGHT1 channel 17 behind the new `night_sulam_placed` flag, so placing the ladder reveals something that was previously always visible. |
| `tests/test_inventory_drag.gd` | **create**: the suite for all of the above. |
| `docs/EXTRACT_FROM_INSTALLER.md` | **modify**: it still claims the Lingo was never recovered. Point it at `reference/`. |
| `docs/ENGINE.md` | **modify**: document the drag mechanic and the table. |

---

### Task 1: Resolve the `master` cast library per movie

Slot icons outside DAY1 and NIGHT1 currently draw from the wrong cast library. Fix that first: every later task draws or hit-tests a slot icon.

**Files:**
- Modify: `director/render_model_loader.gd` (add after `_linked_cast_name`, line 197)
- Modify: `director/director_runtime.gd` (add near `is_channel_hidden`, line 221)
- Modify: `autoload/game_state.gd:227-243`
- Modify: `director/movie_player.gd:384`
- Test: `tests/test_inventory_drag.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `RenderModelLoader.cast_lib_index(name: String) -> int`, `DirectorRuntime.master_cast_lib() -> int`, `GameState.inventory_member_for_item(item_name: String, cast_lib: int) -> Dictionary`, `GameState.inventory_override_for_channel(channel: int, cast_lib: int) -> Dictionary`, `GameState.item_in_slot(slot_index: int) -> String`, `GameState.slot_channels() -> Array`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_drag.gd`:

```gdscript
extends SceneTree
## Inventory is drag-and-drop, not click-to-select.
##
## reference/lingo/MASTER/External/MovieScript 80 - displayobject.ls puppets
## sprites 103-110 from objectsfield lines 1-8 and gives an occupied slot
## moveableSprite = 1, so Director itself drags the icon. The ten
## BehaviorScripts beside it resolve the drop with `sprite the clickOn
## intersects <target>` and then always snap the icon home.

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_master_cast_lib_per_movie()

	if failures.is_empty():
		print("PASS: inventory drag suite")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _new_runtime() -> RefCounted:
	## A parse error would otherwise leave every assertion unreached and the
	## suite would report PASS on a script that never ran.
	var script: Variant = load("res://director/director_runtime.gd")
	if script == null:
		failures.append("director_runtime.gd failed to load")
		return null
	var runtime: RefCounted = script.new()
	_expect_eq(runtime.boot(), OK, "boot loads the render-model index")
	return runtime


func _test_master_cast_lib_per_movie() -> void:
	## The master library sits at a different index in every movie, and the
	## slot icons all live in master. HOTEL1 index 3 is `master`; index 2 is
	## `hotel`, which also holds members 9 and 30, so a hardcoded 2 drew the
	## wrong bitmap instead of failing loudly.
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return
	for expected in [
		{"movie": "DAY1", "lib": 2},
		{"movie": "NIGHT1", "lib": 2},
		{"movie": "HOTEL1", "lib": 3},
		{"movie": "SEA1", "lib": 4},
		{"movie": "AIR1", "lib": 3},
	]:
		_expect_eq(runtime.loader.load_movie(str(expected.movie)), OK, "load %s" % expected.movie)
		_expect_eq(
			runtime.master_cast_lib(),
			int(expected.lib),
			"%s master cast lib" % expected.movie
		)


func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: FAIL, `Invalid call. Nonexistent function 'master_cast_lib' in base 'RefCounted'`

- [x] **Step 3: Add `cast_lib_index` to the loader**

In `director/render_model_loader.gd`, after `_linked_cast_name` (ends line 197):

```gdscript
func cast_lib_index(name: String) -> int:
	## Linked libraries sit at a different index in every movie: `master` is 2
	## in DAY1, 3 in HOTEL1, 4 in SEA1. Returns -1 when the movie does not
	## link the library at all.
	var wanted := name.strip_edges().to_lower()
	for key in cast_libs.keys():
		var library: Variant = cast_libs[key]
		if typeof(library) != TYPE_DICTIONARY:
			continue
		var lib_name: Variant = (library as Dictionary).get("name", "")
		if typeof(lib_name) != TYPE_STRING:
			continue
		if str(lib_name).strip_edges().to_lower() == wanted:
			return int(key)
	return -1
```

- [x] **Step 4: Add `master_cast_lib` to the runtime**

In `director/director_runtime.gd`, after `is_channel_hidden` (ends line 223):

```gdscript
func master_cast_lib() -> int:
	## Every inventory icon, `object0` and both Piposh heads live in the shared
	## `master` cast. Fall back to 2, which is where DAY1 and NIGHT1 put it.
	var index := loader.cast_lib_index("master")
	return index if index > 0 else 2
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: `PASS: inventory drag suite`

- [x] **Step 6: Thread the library index through GameState**

Replace `autoload/game_state.gd:227-243` with:

```gdscript
func slot_channels() -> Array:
	return inventory_catalog.get("slot_channels", [103, 104, 105, 106, 107, 108, 109, 110])


func item_in_slot(slot_index: int) -> String:
	## objectsfield line `slot_index + 1`, i.e. Lingo's `line i - 102` for
	## sprite i. Returns "" for an out-of-range or empty slot.
	if slot_index < 0 or slot_index >= objects_field.size():
		return ""
	var item := str(objects_field[slot_index]).to_lower()
	return "" if item == "" or item == "empty" else item


func inventory_member_for_item(item_name: String, cast_lib: int = -1) -> Dictionary:
	## cast_lib is the index of the `master` library in the movie being drawn;
	## it differs per movie. -1 keeps the catalog default for callers with no
	## loader to ask (Save Editor, tests).
	var name := item_name.to_lower()
	var lib := cast_lib if cast_lib > 0 else int(inventory_catalog.get("cast_lib", 2))
	if name.is_empty() or name == "empty":
		return {"cast_lib": lib, "cast_id": int(inventory_catalog.get("empty_member", 9))}
	var items: Dictionary = inventory_catalog.get("items", {})
	if not items.has(name):
		return {}
	return {"cast_lib": lib, "cast_id": int(items[name])}


func inventory_override_for_channel(channel: int, cast_lib: int = -1) -> Dictionary:
	var slots: Array = slot_channels()
	var slot_idx := slots.find(channel)
	if slot_idx < 0 or slot_idx >= objects_field.size():
		return {}
	return inventory_member_for_item(objects_field[slot_idx], cast_lib)
```

- [x] **Step 7: Pass the index from the renderer**

In `director/movie_player.gd:384`, replace:

```gdscript
		var inv: Dictionary = GameState.inventory_override_for_channel(channel)
```

with:

```gdscript
		var inv: Dictionary = GameState.inventory_override_for_channel(
			channel, runtime.master_cast_lib()
		)
```

- [ ] **Step 8: Extend the test to cover the member lookup**

Add to `tests/test_inventory_drag.gd`, and call it from `_run` after `_test_master_cast_lib_per_movie()`:

```gdscript
func _test_slot_member_follows_the_movie() -> void:
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return
	GameState.new_game()
	_expect_eq(GameState.add_inventory_item("sciser"), true, "sciser picked up")
	_expect_eq(GameState.item_in_slot(0), "sciser", "sciser lands in slot 1")
	_expect_eq(GameState.item_in_slot(1), "", "slot 2 stays empty")

	_expect_eq(runtime.loader.load_movie("HOTEL1"), OK, "load HOTEL1")
	var override: Dictionary = GameState.inventory_override_for_channel(
		103, runtime.master_cast_lib()
	)
	_expect_eq(int(override.get("cast_lib", -1)), 3, "HOTEL1 draws sciser from master")
	_expect_eq(int(override.get("cast_id", -1)), 30, "sciser is master member 30")

	_expect_eq(runtime.loader.load_movie("DAY1"), OK, "load DAY1")
	var day1: Dictionary = GameState.inventory_override_for_channel(
		103, runtime.master_cast_lib()
	)
	_expect_eq(int(day1.get("cast_lib", -1)), 2, "DAY1 draws sciser from master")

	var empty: Dictionary = GameState.inventory_override_for_channel(
		104, runtime.master_cast_lib()
	)
	_expect_eq(int(empty.get("cast_id", -1)), 9, "an empty slot shows object0")
```

- [x] **Step 9: Run the full suite**

Run each and confirm the `PASS:` line:

```bash
godot --headless --script tests/test_inventory_drag.gd
godot --headless --script tests/test_director_runtime.gd
godot --headless --script tests/test_walk_doorways.gd
godot --headless --script tests/test_day1_navigation.gd
```

Expected: four `PASS:` lines. The `ObjectDB instances were leaked at exit` warning is pre-existing and not a failure.

- [x] **Step 10: Commit**

```bash
git add tests/test_inventory_drag.gd director/render_model_loader.gd director/director_runtime.gd autoload/game_state.gd director/movie_player.gd
git commit -m "fix: draw slot icons from the movie's own master library index"
```

---

### Task 2: Press, drag and release reach the runtime

Director's mechanic is `mouseDown` (store home) → drag → `mouseUp` (test `intersects`). `InputRouter` exposes only `stage_click` and `stage_hover`, and `movie_player.gd:59` `_gui_input` handles only `event.pressed`, so the shape cannot be expressed today. Add the events without touching the existing click path: clicks keep firing on press, so no existing behaviour or test moves.

**Files:**
- Modify: `autoload/input_router.gd`
- Modify: `director/movie_player.gd:59-64`
- Test: `tests/test_inventory_drag.gd`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `InputRouter` signals `stage_press(stage_pos: Vector2)`, `stage_drag(stage_pos: Vector2)`, `stage_release(stage_pos: Vector2)`; `InputRouter.notify_mouse_press(stage_pos)`, `notify_mouse_release(stage_pos)`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_inventory_drag.gd`, called from `_run`:

```gdscript
func _test_input_router_emits_press_drag_release() -> void:
	## Without a release event there is no place to resolve a drop.
	var seen := PackedStringArray()
	var on_press := func(_p): seen.append("press")
	var on_drag := func(_p): seen.append("drag")
	var on_release := func(_p): seen.append("release")
	InputRouter.stage_press.connect(on_press)
	InputRouter.stage_drag.connect(on_drag)
	InputRouter.stage_release.connect(on_release)

	InputRouter.notify_mouse_press(Vector2(331, 441))
	InputRouter.notify_mouse_stage_pos(Vector2(300, 300))
	InputRouter.notify_mouse_release(Vector2(120, 200))

	InputRouter.stage_press.disconnect(on_press)
	InputRouter.stage_drag.disconnect(on_drag)
	InputRouter.stage_release.disconnect(on_release)
	_expect_eq(
		",".join(seen),
		"press,drag,release",
		"press, motion while held, then release"
	)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: FAIL, `Invalid access to property or key 'stage_press'`

- [x] **Step 3: Add the events to InputRouter**

In `autoload/input_router.gd`, after the existing signals (line 6):

```gdscript
signal stage_press(stage_pos: Vector2)
signal stage_drag(stage_pos: Vector2)
signal stage_release(stage_pos: Vector2)
```

Add a held flag beside `_enabled`:

```gdscript
var _pressed: bool = false
```

Route motion while held to `stage_drag` by replacing `notify_mouse_stage_pos`:

```gdscript
func notify_mouse_stage_pos(stage_pos: Vector2) -> void:
	virtual_cursor = stage_pos.clamp(_stage_rect.position, _stage_rect.position + _stage_rect.size)
	if _pressed:
		stage_drag.emit(virtual_cursor)
	else:
		stage_hover.emit(virtual_cursor)
```

And add:

```gdscript
func notify_mouse_press(stage_pos: Vector2) -> void:
	_pressed = true
	virtual_cursor = stage_pos
	stage_press.emit(stage_pos)


func notify_mouse_release(stage_pos: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false
	virtual_cursor = stage_pos
	stage_release.emit(stage_pos)
```

- [x] **Step 4: Feed them from MoviePlayer**

Replace `director/movie_player.gd:59-64` with:

```gdscript
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		InputRouter.notify_mouse_stage_pos(screen_to_stage(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var stage_pos := screen_to_stage(event.position)
		if event.pressed:
			# Press starts a possible drag AND still fires the click, so every
			# existing hotspot keeps its press-to-activate behaviour.
			InputRouter.notify_mouse_press(stage_pos)
			InputRouter.notify_mouse_click(stage_pos)
		else:
			InputRouter.notify_mouse_release(stage_pos)
		accept_event()
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: `PASS: inventory drag suite`

- [x] **Step 6: Commit**

```bash
git add autoload/input_router.gd director/movie_player.gd tests/test_inventory_drag.gd
git commit -m "feat: route mouse press, drag and release to the stage"
```

---

### Task 3: Drag an icon out of an occupied slot and snap it home

`displayobject` gives an occupied slot `moveableSprite = 1`; an empty slot gets `object0` and no drag. `mouseDown` stores `objectxx` / `objectyy`, and every handler ends by writing them back. That snap-back is unconditional, so it is not a failure branch: the icon returns whether or not the drop did anything.

Note the drag source path must not go through `clickable_sprites` (`director/director_runtime.gd:818`): it drops any sprite whose `on_click` carries no nav, inventory or sounds, which is every slot channel. Slots are found by channel, from the score frame directly.

**Files:**
- Create: `director/inventory_drag.gd`
- Modify: `director/director_runtime.gd`
- Modify: `director/movie_player.gd`
- Test: `tests/test_inventory_drag.gd`

**Interfaces:**
- Consumes: `DirectorRuntime.master_cast_lib()`, `GameState.item_in_slot()`, `GameState.slot_channels()` (Task 1); `InputRouter.stage_press` / `stage_drag` / `stage_release` (Task 2).
- Produces: `InventoryDrag` with `active: bool`, `slot_channel: int`, `item: String`, `home: Vector2`, `position: Vector2`, `icon_size: Vector2`, `begin(slot_channel, item, home, icon_size)`, `move_to(pos)`, `clear()`, `icon_rect() -> Rect2`; `DirectorRuntime.drag: InventoryDrag`, `DirectorRuntime.begin_inventory_drag(stage_pt) -> bool`, `update_inventory_drag(stage_pt)`, `end_inventory_drag(stage_pt)`, `slot_sprite_at(stage_pt) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_inventory_drag.gd`, called from `_run`:

```gdscript
func _test_drag_starts_only_on_an_occupied_slot() -> void:
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return
	GameState.new_game()
	GameState.add_inventory_item("sciser")
	_expect_eq(runtime.goto_movie("DAY1", null, {"label": "shore2"}), true, "enter DAY1")

	var slot: Dictionary = runtime.slot_sprite_at(_slot_centre(runtime, 103))
	_expect_eq(slot.is_empty(), false, "slot 103 is under its own centre")

	_expect_eq(
		runtime.begin_inventory_drag(_slot_centre(runtime, 103)),
		true,
		"an occupied slot starts a drag"
	)
	_expect_eq(runtime.drag.item, "sciser", "the drag carries the item name")
	var home: Vector2 = runtime.drag.home
	runtime.update_inventory_drag(Vector2(200, 200))
	_expect_eq(runtime.drag.position, Vector2(200, 200), "the icon follows the cursor")
	runtime.end_inventory_drag(Vector2(200, 200))
	_expect_eq(runtime.drag.active, false, "release ends the drag")
	_expect_eq(GameState.item_in_slot(0), "sciser", "a dropped-on-nothing item is kept")

	_expect_eq(
		runtime.begin_inventory_drag(_slot_centre(runtime, 104)),
		false,
		"an empty slot does not start a drag"
	)
	_expect_eq(home != Vector2.ZERO, true, "the slot home position was recorded")


func _slot_centre(runtime: RefCounted, channel: int) -> Vector2:
	var frame: Dictionary = runtime.loader.get_frame(runtime.frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) == TYPE_DICTIONARY and int(sprite.get("channel", 0)) == channel:
			var rect: Rect2 = runtime.sprite_stage_rect(sprite)
			return rect.position + rect.size * 0.5
	failures.append("channel %d is not in the current frame" % channel)
	return Vector2.ZERO
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: FAIL, `Invalid call. Nonexistent function 'slot_sprite_at'`

- [x] **Step 3: Create the drag state**

Create `director/inventory_drag.gd`:

```gdscript
class_name InventoryDrag
extends RefCounted
## One inventory icon in flight.
##
## reference/lingo/MASTER/External/BehaviorScript 108.ls stores the slot's home
## position in globals objectxx / objectyy on mouseDown and writes them back at
## the end of mouseUp, always. The snap-back is not a failure branch: item
## consumption is a mutation of objectsfield, never a sprite position.

var active: bool = false
var slot_channel: int = -1
var item: String = ""
var home: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO
var icon_size: Vector2 = Vector2.ZERO


func begin(channel: int, item_name: String, home_pos: Vector2, size: Vector2) -> void:
	active = true
	slot_channel = channel
	item = item_name
	home = home_pos
	position = home_pos
	icon_size = size


func move_to(pos: Vector2) -> void:
	if active:
		position = pos


func clear() -> void:
	active = false
	slot_channel = -1
	item = ""
	home = Vector2.ZERO
	position = Vector2.ZERO
	icon_size = Vector2.ZERO


func icon_rect() -> Rect2:
	## Director drags a sprite by its registration point, so the icon stays
	## centred on the cursor. `intersects` is a rect test between two sprites.
	return Rect2(position - icon_size * 0.5, icon_size)
```

- [x] **Step 4: Wire the drag into the runtime**

In `director/director_runtime.gd`, beside the other members (after line 49):

```gdscript
var drag: InventoryDrag = InventoryDrag.new()
```

And add these, after `master_cast_lib()`:

```gdscript
func slot_sprite_at(stage_pt: Vector2) -> Dictionary:
	## Slot channels never reach clickable_sprites(): that filter drops any
	## sprite whose on_click has no nav, inventory or sounds, which is all of
	## 103-110. Find them by channel in the score frame instead.
	var slots: Array = GameState.slot_channels()
	var frame: Dictionary = loader.get_frame(frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		var channel := int((sprite as Dictionary).get("channel", 0))
		if slots.find(channel) < 0:
			continue
		if is_channel_hidden(channel):
			continue
		if sprite_contains(sprite, stage_pt):
			return sprite
	return {}


func begin_inventory_drag(stage_pt: Vector2) -> bool:
	var sprite: Dictionary = slot_sprite_at(stage_pt)
	if sprite.is_empty():
		return false
	var channel := int(sprite.get("channel", 0))
	var slot_index: int = GameState.slot_channels().find(channel)
	var item := GameState.item_in_slot(slot_index)
	if item == "":
		# displayobject() gives an empty slot member object0 and no
		# moveableSprite, so there is nothing to pick up.
		return false
	var rect: Rect2 = sprite_stage_rect(sprite)
	drag.begin(channel, item, rect.position + rect.size * 0.5, rect.size)
	redraw_requested.emit()
	return true


func update_inventory_drag(stage_pt: Vector2) -> void:
	if not drag.active:
		return
	drag.move_to(stage_pt)
	redraw_requested.emit()


func end_inventory_drag(stage_pt: Vector2) -> void:
	if not drag.active:
		return
	drag.move_to(stage_pt)
	# Rule application arrives in Tasks 4 and 5. The icon springs home either
	# way, so an invalid target needs no failure branch.
	drag.clear()
	redraw_requested.emit()
```

- [x] **Step 5: Connect and draw it**

In `director/movie_player.gd` `_ready`, after the `InputRouter.stage_hover` connection (line 40):

```gdscript
	InputRouter.stage_press.connect(func(p): runtime.begin_inventory_drag(p))
	InputRouter.stage_drag.connect(func(p): runtime.update_inventory_drag(p))
	InputRouter.stage_release.connect(func(p): runtime.end_inventory_drag(p))
```

In `draw_current_frame`, skip the slot at its home while it is in flight. Directly after the `runtime.is_channel_hidden(channel)` check (line 379-380):

```gdscript
		# The icon being dragged is drawn at the cursor, below.
		if runtime.drag.active and channel == runtime.drag.slot_channel:
			continue
```

And after the puppet block, before the debug overlays (line 459):

```gdscript
	if runtime.drag.active:
		var drag_member: Dictionary = GameState.inventory_member_for_item(
			runtime.drag.item, runtime.master_cast_lib()
		)
		if not drag_member.is_empty():
			var dtex: Texture2D = runtime.loader.get_texture(
				int(drag_member.cast_lib),
				int(drag_member.cast_id),
				RenderModelLoader.Transparency.BACKGROUND
			)
			if dtex:
				var dmember: Dictionary = runtime.loader.get_member(
					int(drag_member.cast_lib), int(drag_member.cast_id)
				)
				var dreg_x: float = float(dmember.get("reg_offset_x", dtex.get_width() * 0.5))
				var dreg_y: float = float(dmember.get("reg_offset_y", dtex.get_height() * 0.5))
				var dpos: Vector2 = runtime.drag.position
				canvas.draw_texture_rect(
					dtex,
					Rect2(
						(dpos.x - dreg_x) * sx,
						(dpos.y - dreg_y) * sy,
						float(dtex.get_width()) * sx,
						float(dtex.get_height()) * sy,
					),
					false
				)
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: `PASS: inventory drag suite`

- [x] **Step 7: Add the hand cursor**

`hand1` / `hand2` decode to 5×6 and 8×8 pixels, so the exported bitmaps cannot be used as a Director 1-bit 16×16 cursor pair. Use Godot's pointing hand and say why. In `director/movie_player.gd`, in `_on_stage_hover` (line 91):

```gdscript
func _on_stage_hover(stage_pos: Vector2) -> void:
	runtime.update_hover(stage_pos)
	# displayobject() sets the cursor of an occupied slot to
	# [member "hand1", member "hand2"]. Those two members decode to 5x6 and
	# 8x8 pixels, and a Director cursor cast pair is 1-bit 16x16, so the export
	# is wrong and the built-in hand stands in until the BITD decode is fixed.
	var over_item := false
	var slot: Dictionary = runtime.slot_sprite_at(stage_pos)
	if not slot.is_empty():
		var slot_index: int = GameState.slot_channels().find(int(slot.get("channel", 0)))
		over_item = GameState.item_in_slot(slot_index) != ""
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if over_item or runtime.drag.active
		else Control.CURSOR_ARROW
	)
```

- [x] **Step 8: Run the full suite**

```bash
godot --headless --script tests/test_inventory_drag.gd
godot --headless --script tests/test_director_runtime.gd
godot --headless --script tests/test_walk_doorways.gd
godot --headless --script tests/test_day1_navigation.gd
```

Expected: four `PASS:` lines.

- [x] **Step 9: Commit**

```bash
git add director/inventory_drag.gd director/director_runtime.gd director/movie_player.gd tests/test_inventory_drag.gd
git commit -m "feat: drag inventory icons out of their slots and snap them home"
```

---

### Task 4: Drop on Piposh's head to examine an item

The one interaction every single handler shares. All ten test `sprite the clickOn intersects 100` first: swap sprite 100 to `piphead2`, play `pi<item>.aif`, and at the end of the handler restore `piphead1`. `updateStage()` runs before the restore, so `piphead2` is visible for exactly one stage refresh.

**Files:**
- Modify: `director/director_runtime.gd`
- Modify: `director/movie_player.gd`
- Test: `tests/test_inventory_drag.gd`

**Interfaces:**
- Consumes: everything from Task 3.
- Produces: `DirectorRuntime.head_member_override() -> int` (returns -1 when not looking), `DirectorRuntime.EXAMINE_CHANNEL := 100`, `DirectorRuntime.PIPHEAD_LOOK_MEMBER := 55`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_inventory_drag.gd`, called from `_run`:

```gdscript
func _test_dropping_on_the_head_examines_the_item() -> void:
	## Every one of the ten drop handlers opens with
	## `if sprite the clickOn intersects 100`, swaps master member piphead1
	## (54) for piphead2 (55), and plays pi<item>.aif.
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return
	GameState.new_game()
	GameState.add_inventory_item("sciser")
	_expect_eq(runtime.goto_movie("DAY1", null, {"label": "shore2"}), true, "enter DAY1")

	_expect_eq(runtime.head_member_override(), -1, "no head swap at rest")
	_expect_eq(
		runtime.begin_inventory_drag(_slot_centre(runtime, 103)),
		true,
		"pick sciser up"
	)
	runtime.end_inventory_drag(_slot_centre(runtime, 100))
	_expect_eq(runtime.head_member_override(), 55, "the head swaps to piphead2")
	_expect_eq(GameState.item_in_slot(0), "sciser", "examining never consumes the item")
	_expect_eq(
		AudioDirector.resolve_path("pisciser.aif") != "",
		true,
		"pisciser is in the audio index"
	)

	# The Lingo restores piphead1 at the end of the handler, after one
	# updateStage(). The next drawn frame is back to normal.
	runtime.enter_frame(runtime.frame_index)
	_expect_eq(runtime.head_member_override(), -1, "the head restores after one frame")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: FAIL, `Invalid call. Nonexistent function 'head_member_override'`

- [x] **Step 3: Implement the examine branch**

In `director/director_runtime.gd`, beside `DYNAMIC_REDIRECT_SCRIPT` (line 43):

```gdscript
## Piposh's head. Every drop handler tests this first: an item dropped on it is
## examined rather than used.
const EXAMINE_CHANNEL := 100
## master member piphead2, shown for a single stage refresh while he looks.
const PIPHEAD_LOOK_MEMBER := 55
```

Beside `_hidden_channels` (line 66):

```gdscript
var _head_look_frames: int = 0
```

Add:

```gdscript
func head_member_override() -> int:
	## -1 while the score member (piphead1) stands.
	return PIPHEAD_LOOK_MEMBER if _head_look_frames > 0 else -1


func _channel_rect(channel: int) -> Rect2:
	var frame: Dictionary = loader.get_frame(frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		if int((sprite as Dictionary).get("channel", 0)) != channel:
			continue
		if is_channel_hidden(channel):
			return Rect2()
		return sprite_stage_rect(sprite)
	return Rect2()


func _drag_intersects(channel: int) -> bool:
	## Lingo: `sprite the clickOn intersects <channel>`, a rect overlap
	## between the dragged icon and the target sprite, not a point test.
	var target := _channel_rect(channel)
	if target.size.x <= 0.0 or target.size.y <= 0.0:
		return false
	return drag.icon_rect().intersects(target)


func _examine_item(item: String) -> void:
	_head_look_frames = 1
	AudioDirector.play_file(1, "pi%s.aif" % item)
	nav_event.emit("examine: %s" % item)
```

Replace the body of `end_inventory_drag` from Task 3 with:

```gdscript
func end_inventory_drag(stage_pt: Vector2) -> void:
	if not drag.active:
		return
	drag.move_to(stage_pt)
	var item := drag.item
	if _drag_intersects(EXAMINE_CHANNEL):
		_examine_item(item)
	# The icon springs home whatever happened, so a wrong target needs no
	# failure branch: nothing intersects, and nothing plays.
	drag.clear()
	redraw_requested.emit()
```

Decrement the counter in `enter_frame`, right after `frame_entered_ms = _time_ms` (line 255):

```gdscript
	if _head_look_frames > 0:
		_head_look_frames -= 1
```

- [x] **Step 4: Draw the swapped head**

In `director/movie_player.gd` `draw_current_frame`, after the `STRTGAME_MENU_HOVER` block (ends line 396):

```gdscript
		if channel == DirectorRuntime.EXAMINE_CHANNEL and runtime.head_member_override() >= 0:
			cast_id = runtime.head_member_override()
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: `PASS: inventory drag suite`

- [x] **Step 6: Run the full suite**

```bash
godot --headless --script tests/test_inventory_drag.gd
godot --headless --script tests/test_director_runtime.gd
godot --headless --script tests/test_walk_doorways.gd
godot --headless --script tests/test_day1_navigation.gd
```

Expected: four `PASS:` lines.

- [x] **Step 7: Commit**

```bash
git add director/director_runtime.gd director/movie_player.gd tests/test_inventory_drag.gd
git commit -m "feat: examine an item by dropping it on Piposh"
```

---

### Task 5: The drop-rule table and the three world-object puzzles

Everything past examine is per-movie, per-target-sprite and visibility-gated. Three rules need no state this port lacks; they come from `BehaviorScript 110`, `111` and `94`. `objecttalktime` targets are plan 2; `planefunk` and `ishspec` are plan 5; `BehaviorScript 128` cannot be placed in a movie and is recorded disabled.

**Files:**
- Create: `data/inventory_drops.json`
- Create: `director/inventory_drops.gd`
- Modify: `director/director_runtime.gd`
- Modify: `data/movie_context.json`
- Test: `tests/test_inventory_drag.gd`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: `InventoryDrops` with `load_table()`, `rules_for(movie: String) -> Array`, `slot_channels() -> Array`; `DirectorRuntime.drops: InventoryDrops`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_inventory_drag.gd`, called from `_run`:

```gdscript
func _test_night1_ladder_is_placed_and_consumed() -> void:
	## BehaviorScript 110: dropping `sulam` on sprite 8 reveals sprite 17,
	## records it in globalnight item 1, and shifts the item out of
	## objectsfield. Any other item on sprite 8 does nothing.
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return
	GameState.new_game()
	GameState.add_inventory_item("wine")
	GameState.add_inventory_item("sulam")
	_expect_eq(runtime.goto_movie("NIGHT1", null, {"label": "shore3"}), true, "enter NIGHT1")

	var rules: Array = runtime.drops.rules_for("NIGHT1")
	_expect_eq(rules.is_empty(), false, "NIGHT1 has drop rules")
	for rule in rules:
		_expect_eq(
			str((rule as Dictionary).get("lingo", "")) != "",
			true,
			"every rule cites its Lingo source"
		)

	_expect_eq(GameState.has_story_flag("night_sulam_placed"), false, "ladder not placed yet")
	runtime.apply_inventory_drop("sulam", 8)
	_expect_eq(GameState.has_story_flag("night_sulam_placed"), true, "the ladder is placed")
	_expect_eq(GameState.item_in_slot(1), "", "sulam left the field")
	_expect_eq(GameState.item_in_slot(0), "wine", "wine stayed put")

	GameState.new_game()
	GameState.add_inventory_item("wine")
	runtime.apply_inventory_drop("wine", 8)
	_expect_eq(
		GameState.has_story_flag("night_sulam_placed"),
		false,
		"only sulam places the ladder"
	)
	_expect_eq(GameState.item_in_slot(0), "wine", "a non-matching item is not consumed")


func _test_a_wrong_target_is_silent() -> void:
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return
	GameState.new_game()
	GameState.add_inventory_item("sulam")
	_expect_eq(runtime.goto_movie("NIGHT1", null, {"label": "shore3"}), true, "enter NIGHT1")
	# Channel 99 carries no rule in any movie.
	_expect_eq(runtime.apply_inventory_drop("sulam", 99), false, "no rule, no effect")
	_expect_eq(GameState.item_in_slot(0), "sulam", "the item is kept")
	_expect_eq(GameState.has_story_flag("night_sulam_placed"), false, "no flag raised")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: FAIL, `Invalid access to property or key 'drops'`

- [x] **Step 3: Write the rule table**

Create `data/inventory_drops.json`:

```json
{
	"_comment": [
		"Inventory drop rules, transcribed from the ten drop behaviours in",
		"reference/lingo/MASTER/External/BehaviorScript {52,93,94,97,108,110,111,128,129,135}.ls.",
		"Inventory is drag-and-drop; there is no selection state in the original.",
		"mouseDown stores the slot's home position, mouseUp tests",
		"`sprite the clickOn intersects <target>`, and the icon always springs",
		"home afterwards. A wrong target therefore needs no failure branch.",
		"Rules are tried in order and the first match wins, so item-specific",
		"rules must precede the wildcard for the same target.",
		"NOT under assets/ on purpose: assets/SOURCE.txt documents that tree as",
		"mirrored with `robocopy /MIR`, which would delete this file."
	],

	"_schema": [
		"target_channel  score channel the dragged icon must intersect",
		"items           item names, or [\"*\"] for any item",
		"requires_visible  channels that must be present and not story-gated",
		"rooms           optional marker names; absent means any room",
		"action          reveal | goto_label | none",
		"reveal_channels channels the action makes visible (via sets_flag)",
		"sets_flag       story flag raised, which sprite gates read",
		"label           score label to jump to for goto_label",
		"sounds          [{channel, file}] or [{channel, family, from, to}]",
		"stop_channels   sound channels stopped first",
		"consume         true when the item leaves objectsfield",
		"enabled         false parks a rule that cannot be placed yet",
		"lingo           the file this rule was transcribed from"
	],

	"rules": {
		"NIGHT1": [
			{
				"target_channel": 8,
				"items": ["sulam"],
				"action": "reveal",
				"reveal_channels": [17],
				"sets_flag": "night_sulam_placed",
				"consume": true,
				"lingo": "MASTER/External/BehaviorScript 110.ls"
			},
			{
				"target_channel": 15,
				"items": ["sciser"],
				"requires_visible": [15],
				"action": "goto_label",
				"label": "cutmirolohair",
				"consume": false,
				"lingo": "MASTER/External/BehaviorScript 111.ls"
			},
			{
				"target_channel": 15,
				"items": ["*"],
				"requires_visible": [15],
				"action": "goto_label",
				"label": "mirolospk",
				"stop_channels": [2],
				"sounds": [{"channel": 1, "family": "mirolo", "from": 2, "to": 5}],
				"consume": false,
				"lingo": "MASTER/External/BehaviorScript 111.ls, where random(4) + 1 is 2..5, so mirolo1 is never used here"
			}
		],

		"HOTEL1": [
			{
				"target_channel": 35,
				"items": ["*"],
				"requires_visible": [35],
				"action": "goto_label",
				"label": "fatspkroomb",
				"sounds": [{"channel": 1, "file": "fatobjb.aif"}],
				"consume": false,
				"lingo": "MASTER/External/BehaviorScript 94.ls"
			}
		],

		"_disabled": [
			{
				"target_channel": 9,
				"items": ["tools"],
				"action": "reveal",
				"reveal_channels": [7, 8],
				"sets_flag": "tools_used_on_9",
				"sounds": [{"channel": 1, "file": "zzz.aif"}],
				"consume": false,
				"enabled": false,
				"lingo": "MASTER/External/BehaviorScript 128.ls",
				"why_disabled": [
					"The movie cannot be determined from the Lingo: zzz.aif appears in",
					"no other script and the handler names no marker. Placing it needs",
					"the sprite-script fields from VWSC-*.bin in the ProjectorRays dump.",
					"The Lingo also requires sprites 7 and 8 to both be invisible first."
				]
			}
		]
	},

	"_deferred": [
		"objecttalktime targets (characters 18-21, 34, 36, 37): plan 2.",
		"AIR1 planefunk on sprite 14 and HOTEL1 ishspec on 34/18 with money: plan 5, both write field \"points\"."
	]
}
```

- [x] **Step 4: Write the table reader**

Create `director/inventory_drops.gd`:

```gdscript
class_name InventoryDrops
extends RefCounted
## Reads data/inventory_drops.json. Same shape as MovieContext: a hand
## maintained table the Lingo is transcribed into, one citation per rule.

const TABLE_PATH := "res://data/inventory_drops.json"

var _rules: Dictionary = {}


func load_table() -> void:
	_rules.clear()
	if not FileAccess.file_exists(TABLE_PATH):
		GameState.emit_log("Missing drop table: %s" % TABLE_PATH, "warn")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		GameState.emit_log("Drop table is not an object: %s" % TABLE_PATH, "warn")
		return
	var rules: Variant = (parsed as Dictionary).get("rules", {})
	if typeof(rules) != TYPE_DICTIONARY:
		return
	var kept := 0
	for movie in (rules as Dictionary).keys():
		if str(movie).begins_with("_"):
			continue
		var list: Variant = (rules as Dictionary)[movie]
		if typeof(list) != TYPE_ARRAY:
			continue
		var enabled: Array = []
		for rule in list as Array:
			if typeof(rule) != TYPE_DICTIONARY:
				continue
			if not bool((rule as Dictionary).get("enabled", true)):
				continue
			enabled.append(rule)
		if not enabled.is_empty():
			_rules[str(movie).to_upper()] = enabled
			kept += enabled.size()
	GameState.emit_log("Drop rules loaded: %d across %d movies" % [kept, _rules.size()], "info")


func rules_for(movie: String) -> Array:
	var list: Variant = _rules.get(movie.to_upper(), [])
	return list if typeof(list) == TYPE_ARRAY else []


func matches(rule: Dictionary, item: String, room: String) -> bool:
	var items: Variant = rule.get("items", [])
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		return false
	var wanted := item.to_lower()
	var item_ok := false
	for candidate in items as Array:
		var name := str(candidate).to_lower()
		if name == "*" or name == wanted:
			item_ok = true
			break
	if not item_ok:
		return false
	var rooms: Variant = rule.get("rooms", [])
	if typeof(rooms) != TYPE_ARRAY or (rooms as Array).is_empty():
		return true
	var here := room.to_lower().trim_suffix("go")
	for candidate in rooms as Array:
		if str(candidate).to_lower().trim_suffix("go") == here:
			return true
	return false
```

- [x] **Step 5: Apply rules from the runtime**

In `director/director_runtime.gd`, beside `drag` (Task 3):

```gdscript
var drops: InventoryDrops = InventoryDrops.new()
```

In `boot()`, after `context.load_context()` (line 82):

```gdscript
	drops.load_table()
```

Add:

```gdscript
func apply_inventory_drop(item: String, target_channel: int) -> bool:
	## Returns false when nothing in the table matched, which is the silent
	## case: the icon springs home and no sound plays.
	var room := marker_name_for_frame(frame_index)
	for rule_value in drops.rules_for(loader.movie_name):
		var rule: Dictionary = rule_value
		if int(rule.get("target_channel", -1)) != target_channel:
			continue
		if not drops.matches(rule, item, room):
			continue
		if not _drop_requirements_met(rule):
			continue
		_run_drop_rule(rule, item)
		return true
	return false


func _drop_requirements_met(rule: Dictionary) -> bool:
	var required: Variant = rule.get("requires_visible", [])
	if typeof(required) != TYPE_ARRAY:
		return true
	for channel in required as Array:
		var rect := _channel_rect(int(channel))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
	return true


func _run_drop_rule(rule: Dictionary, item: String) -> void:
	for channel in rule.get("stop_channels", []):
		AudioDirector.stop_channel(int(channel))

	for sound_value in rule.get("sounds", []):
		if typeof(sound_value) != TYPE_DICTIONARY:
			continue
		var sound: Dictionary = sound_value
		var channel := int(sound.get("channel", 1))
		var file := _s(sound.get("file", ""))
		if file != "":
			AudioDirector.play_file(channel, file)
			continue
		var family := _s(sound.get("family", ""))
		if family == "":
			continue
		var from := int(sound.get("from", 1))
		var to := int(sound.get("to", from))
		AudioDirector.play_file(channel, "%s%d.aif" % [family, randi_range(from, maxi(from, to))])

	var flag := _s(rule.get("sets_flag", ""))
	if flag != "":
		GameState.set_story_flag(flag)
		refresh_sprite_gates()

	if bool(rule.get("consume", false)):
		GameState.remove_inventory_item(item)

	match _s(rule.get("action", "none")):
		"goto_label":
			var label := _s(rule.get("label", ""))
			var idx := loader.resolve_label(label, false)
			if idx >= 0:
				enter_frame(idx)
				running = true
				nav_event.emit("drop %s → %s" % [item, label])
			else:
				nav_event.emit('drop %s → missing label "%s"' % [item, label])
		"reveal":
			nav_event.emit("drop %s → revealed %s" % [item, _s(rule.get("sets_flag", ""))])
		_:
			pass
```

And call it from `end_inventory_drag`, replacing the Task 4 body:

```gdscript
func end_inventory_drag(stage_pt: Vector2) -> void:
	if not drag.active:
		return
	drag.move_to(stage_pt)
	var item := drag.item
	if _drag_intersects(EXAMINE_CHANNEL):
		_examine_item(item)
	else:
		for rule_value in drops.rules_for(loader.movie_name):
			var channel := int((rule_value as Dictionary).get("target_channel", -1))
			if channel >= 0 and _drag_intersects(channel):
				if apply_inventory_drop(item, channel):
					break
	# The icon springs home whatever happened, so a wrong target needs no
	# failure branch: nothing intersects, and nothing plays.
	drag.clear()
	redraw_requested.emit()
```

- [x] **Step 6: Gate the ladder in movie_context.json**

`sprite(17).visible = 1` in `BehaviorScript 110` only means something if 17 starts hidden. It is currently ungated, so the ladder is visible before it is placed. Add to `data/movie_context.json` inside `sprite_gates`, after the `DAY1` array:

```json
		"NIGHT1": [
			{
				"rooms": ["shore3"],
				"channels": [17],
				"after_flag": "night_sulam_placed",
				"note": [
					"reference/lingo/MASTER/External/BehaviorScript 110.ls reveals",
					"sprite 17 when the ladder (sulam) is dropped on sprite 8, and",
					"records it in globalnight item 1. Sourced from the Lingo, not",
					"inferred: no confidence field."
				]
			}
		]
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `godot --headless --script tests/test_inventory_drag.gd`
Expected: `PASS: inventory drag suite`

If the NIGHT1 ladder test fails on the room name, print `runtime.marker_name_for_frame(runtime.frame_index)` and set the gate's `rooms` to what NIGHT1 actually reports; `shore3` covers `shore3go` already per the `sprite_gates` comment.

- [x] **Step 8: Run the full suite**

```bash
godot --headless --script tests/test_inventory_drag.gd
godot --headless --script tests/test_director_runtime.gd
godot --headless --script tests/test_walk_doorways.gd
godot --headless --script tests/test_day1_navigation.gd
```

Expected: four `PASS:` lines.

- [x] **Step 9: Commit**

```bash
git add data/inventory_drops.json director/inventory_drops.gd director/director_runtime.gd data/movie_context.json tests/test_inventory_drag.gd
git commit -m "feat: resolve inventory drops against the Lingo drop table"
```

---

### Task 6: Documentation

`docs/EXTRACT_FROM_INSTALLER.md` still says the Lingo was never recovered. That claim already cost one session a wrong turn; fix it before the next one.

**Files:**
- Modify: `docs/EXTRACT_FROM_INSTALLER.md`
- Modify: `docs/ENGINE.md`

- [x] **Step 1: Read what the stale doc actually claims**

Run: `grep -n -i "lingo\|script\|recover" docs/EXTRACT_FROM_INSTALLER.md`

- [x] **Step 2: Correct it**

Replace each claim that the Lingo is unavailable with a pointer to the committed source. Use this wording:

```markdown
The decompiled Lingo **is** in this repository, at `reference/lingo/`, with the
Director text members at `reference/chunks/`. See `reference/README.md` for
provenance. Step 3 below is how it was produced and how to reproduce it; it is
not outstanding work.
```

- [x] **Step 3: Document the drag mechanic**

Append to `docs/ENGINE.md`:

```markdown
## Inventory drag-and-drop

Inventory is drag-and-drop. There is no selection state in the original.

`reference/lingo/MASTER/External/MovieScript 80 - displayobject.ls` puppets
sprites 103-110 from `objectsfield` lines 1-8 (`line i - 102`). An occupied slot
gets `moveableSprite = 1` and a `hand1`/`hand2` cursor; an empty slot gets member
`object0` and no drag.

The ten `BehaviorScript {52, 93, 94, 97, 108, 110, 111, 128, 129, 135}.ls`
handlers resolve the drop. `mouseDown` stores the slot's home position in
`objectxx`/`objectyy`; `mouseUp` tests `sprite the clickOn intersects <target>`
and then writes the home position back **unconditionally**. So an invalid target
needs no failure branch: nothing intersects, the icon springs home, and nothing
plays. Item consumption is always a mutation of `objectsfield`, never a sprite
position.

In the port:

- `director/inventory_drag.gd` holds the icon in flight.
- `data/inventory_drops.json` holds the rules, one Lingo citation each, read by
  `director/inventory_drops.gd`.
- `DirectorRuntime.slot_sprite_at()` finds slots by channel rather than through
  `clickable_sprites()`, which filters out every sprite whose `on_click` carries
  no nav, inventory or sounds, which is all eight slot channels.
- The `master` cast library index differs per movie (DAY1 2, HOTEL1 3, SEA1 4),
  so `master_cast_lib()` resolves it instead of assuming 2.
- `hand1`/`hand2` decode to 5×6 and 8×8 pixels rather than a 1-bit 16×16 cursor
  pair, so `CURSOR_POINTING_HAND` stands in.
```

- [x] **Step 4: Commit**

```bash
git add docs/EXTRACT_FROM_INSTALLER.md docs/ENGINE.md
git commit -m "docs: correct the stale Lingo claim and document the drag mechanic"
```

---

## What this plan retires from movie_context.json

Nothing yet, and that is deliberate: retire nothing that has not been replaced.

- The new `sprite_gates.NIGHT1` entry for channel 17 is **added** from the Lingo and carries no `confidence` field, unlike the inferred entries around it.
- `click_flags` (empty) and `sprite_gates.DAY1` are the candidates for retirement, but their replacement is `MovieScript 78` `searchfunk` plus `field "searchinfo"`, which is **plan 4**. They stay until then.
- The inferred `meeting_triggers`, `phase_transitions` and `day_advance` entries are untouched by drag-and-drop. `field "Dprocess"` (`reference/chunks/MASTER/STXT-793.bin` and `STXT-795.bin`) is the authoritative per-day task list and will bear on them in **plan 5**.

## Acceptance for this plan

Mapped from the spec, restricted to plan 1's scope.

- [x] Items drag from any occupied slot, with a hand cursor, in DAY1, NIGHT1, SEA1, HOTEL1, AIR1 and SHUFFLE, and slot icons draw from the right cast library in all of them, which they did not before.
- ARCADE1 and ARCADE2 are **not** inventory screens, contrary to the spec's scope list. They score only channels 103, 106 and 108, on 20 frames each, and channel 100 is absent entirely, so there is no HUD bar and no examine target. Drag stays enabled there and simply has nothing to intersect, which is the silent snap-back case. SHUFFLE is a real HUD: all eight slots plus channel 100 on 198 frames.
- [x] Dropping on Piposh's head plays `pi<item>.aif` and blinks `piphead2` for one frame, in every movie.
- [x] An invalid target snaps the icon home in silence.
- [x] Dropping `sulam` on NIGHT1 sprite 8 reveals sprite 17 and consumes the item; the flag survives a `to_dict` / `from_dict` round trip (`story_flags` already does this).
- [x] Dropping `sciser` on NIGHT1 sprite 15 jumps to `cutmirolohair`; any other item plays one of `mirolo2`..`mirolo5` and jumps to `mirolospk`.
- [x] Dropping any item on HOTEL1 sprite 35 plays `fatobjb.aif` and jumps to `fatspkroomb`.
- [ ] All four test suites pass. `test_walk_doorways` and `test_day1_navigation` pass; `tests/test_inventory_drag.gd` was waived and is unwritten; **`tests/test_director_runtime.gd` has 28 failures that are pre-existing on clean `main`** and byte-identical before and after this work (the invalid-metadata transactional cases).
- [x] `docs/EXTRACT_FROM_INSTALLER.md` no longer claims the Lingo is unrecovered.

Deferred to plans 2-6, and **not** claimed by this plan: item-on-character conversations, slots past the eighth, `searchfunk`, `Dprocess`/`points` (and with them `planefunk` and `ishspec`), and the 112 unconditional removes. "Representative puzzles from every day completable without the Save Editor" needs plans 2 and 5 at minimum.
