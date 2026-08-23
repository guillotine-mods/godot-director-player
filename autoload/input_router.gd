extends Node
## Unifies mouse + gamepad into a stage-space cursor and click stream.

signal stage_click(stage_pos: Vector2)
signal stage_hover(stage_pos: Vector2)
## Director's inventory mechanic is mouseDown (store home) → drag → mouseUp
## (test intersects), which a click stream alone cannot express.
signal stage_press(stage_pos: Vector2)
signal stage_drag(stage_pos: Vector2)
signal stage_release(stage_pos: Vector2)
## "What can I click here?" -- `project.godot`'s `hint` action, on **H** and on
## joypad button 3. `_on_hint_requested` is the listener, and `bugs.md` 130 is
## the entry that says why there had not been one.
##
## There is no `skip_requested` beside it, and the asymmetry is deliberate rather
## than an oversight (`bugs.md` 129). Skip carried Escape to the retired
## renderer's `skip_current()`, which decided "is this a skippable minigame" from
## a table of Piposh 2 titles and then walked to the next marker -- and
## `scenes/director_preview.gd`'s comment on `skip_release` records why no
## title-agnostic version of that walk exists: a marker labels a position, and
## nothing in a `VWLB` says which positions are scenes. So the signal had no
## reachable *destination*, not merely no listener, and deleting it was the only
## honest move.
##
## **`hint` is the tractable sibling and the difference is where the answer comes
## from.** It asks the frame -- which of the sprites the score placed can answer
## a mouse message -- and the frame is in the container. Nothing here reads a
## marker, a room name or a title. So the same shape (bound, emitted, unwired)
## had two opposite right answers, and reading them as one is what `bugs.md` 130
## exists to stop.
signal hint_requested

## `scenes/preview/`, from an autoload, and both of these are read-only uses.
## The hint's rule and its mark are `hilite.gd`'s -- this file decides *when* to
## ask and *what to say about it*, which is the split every other consumer of
## that module already keeps.
const Hilite := preload("res://scenes/preview/hilite.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Toast := preload("res://scenes/preview/toast.gd")

var virtual_cursor: Vector2 = Vector2(320, 240)
var using_gamepad: bool = false
var _stage_rect := Rect2(0, 0, 640, 480)
var _enabled: bool = true
var _pressed: bool = false
## What `qol/hotspot_hints` was last published as, so the setting is pushed on
## the tick it changes rather than written to the node's metadata sixty times a
## second for a value that moves once a session.
var _hints_published := false


## The one connection `bugs.md` 130 is about.
##
## Made here rather than in the preview because the preview node is
## `scenes/director_preview.gd` and this signal is this file's. An autoload that
## emits a signal nothing in the project connects is indistinguishable from a
## feature that was never finished -- which is exactly what it was.
func _ready() -> void:
	hint_requested.connect(_on_hint_requested)


func set_stage_rect(rect: Rect2) -> void:
	_stage_rect = rect
	virtual_cursor = virtual_cursor.clamp(rect.position, rect.position + rect.size)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func _process(delta: float) -> void:
	if not _enabled:
		return

	var stick := Vector2(
		Input.get_axis("cursor_left", "cursor_right"),
		Input.get_axis("cursor_up", "cursor_down")
	)
	if stick.length() > 0.15:
		using_gamepad = true
		virtual_cursor += stick * AppSettings.controller_cursor_speed * delta
		virtual_cursor = virtual_cursor.clamp(_stage_rect.position, _stage_rect.position + _stage_rect.size)
		stage_hover.emit(virtual_cursor)

	if Input.is_action_just_pressed("hint"):
		hint_requested.emit()

	_serve_hint()


func _input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventMouseMotion:
		using_gamepad = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		using_gamepad = true

	if event.is_action_pressed("click") and not event is InputEventMouseButton:
		# Gamepad A / accept → click at virtual cursor
		stage_click.emit(virtual_cursor)
		get_viewport().set_input_as_handled()


func notify_mouse_stage_pos(stage_pos: Vector2) -> void:
	virtual_cursor = stage_pos.clamp(_stage_rect.position, _stage_rect.position + _stage_rect.size)
	if _pressed:
		stage_drag.emit(virtual_cursor)
	else:
		stage_hover.emit(virtual_cursor)


func notify_mouse_click(stage_pos: Vector2) -> void:
	virtual_cursor = stage_pos
	stage_click.emit(stage_pos)


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


# ---------------------------------------------------------------------------
# `hint`. `bugs.md` 130, and `scenes/preview/hilite.gd`'s second header for the
# rule this half drives.
# ---------------------------------------------------------------------------


## The preview the player is looking at, or null when there is not one.
##
## `current_scene`, because that is what `launcher.gd` hands the movie to and it
## is the **stage** rather than any Movie-In-A-Window hanging off it. Recognised
## by a method every preview has and nothing else in this project does, rather
## than by script path or node name: `boot.gd` already reaches an autoload by
## name with `get_node_or_null` and takes null for an answer, and this is the
## same contract read the other way round.
##
## Null in a `--script` harness, where there is no current scene at all. That is
## why every step below is a static function taking the node: a harness drives
## the real path by handing in the preview it instantiated, exactly as
## `tools/debug_bindings.gd` hands one to `preview/input_router.gd:key_event`.
func stage_preview() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene != null and scene.has_method("frame_sprites"):
		return scene
	return null


## Per tick: publish `qol/hotspot_hints`, and keep the stage repainting while a
## momentary hint is up.
##
## **The repaint is not optional and it is not the paint loop's job.** A movie
## holding on `go to the frame` repaints on its own cadence, but a `pause`d room
## or a preview somebody has stopped does not repaint at all -- so a hint would
## appear on whatever paint happened to come next and then stay on screen for
## ever, because the thing that makes it disappear is a paint. `toast.gd` has the
## same problem and solves it from inside `_paint`, which is the half of this
## that is behind the debug switch and therefore not available here.
##
## **It takes the node rather than finding it**, and that is the same argument
## `stage_preview` makes one function up: a `--script` harness has no current
## scene, so a private `_serve_hint()` would have made `qol/hotspot_hints` a
## setting nothing could prove reaches anything -- which is the state `bugs.md`
## 130 found all four launcher toggles in, and the state this one is leaving.
## `tools/hint.gd` drives this function, not a restatement of it.
func serve(host) -> void:
	if host == null:
		return
	if AppSettings.show_hotspot_hints != _hints_published:
		_hints_published = AppSettings.show_hotspot_hints
		Hilite.set_persistent(host, _hints_published)
	if Hilite.hint_live(host):
		host.queue_redraw()


func _serve_hint() -> void:
	serve(stage_preview())


func _on_hint_requested() -> void:
	answer(stage_preview())


## Point at something the player can click, and say what it was.
##
## Static and node-taking so that the harness drives this function rather than a
## reconstruction of it -- the failure `preview/README.md` describes for `tools/`
## reaching in by name is the same one a harness re-deriving the logic would hit,
## one level up.
##
## **Two audiences, on the two sides of `debug_keys.gd:enabled()`, and that split
## is the point.**
##
##   the player  gets the mark on the stage (`hilite.gd:mark`), which is drawn on
##               the player's side of the switch, carries no text, and is
##               therefore as useful in Hebrew and in Russian as in English. A
##               shipped build has it, because it is the feature.
##   us          get the toast, which is already behind the switch and already
##               English: the channel, the member, the eligibility clause that
##               made it a candidate, and the point a click has to land on. That
##               line is what turns "the hint pointed at the wrong thing" from an
##               impression into a report.
##
## The empty case says so in the toast and does **nothing** on the stage, which
## is `hilite.gd:aim`'s decision and the reason is recorded there: a frame with
## no clickable sprite is ordinary, not a fault, and a badge announcing it would
## be a third overlay painted over a movie in a shipped build.
static func answer(host) -> Dictionary:
	if host == null:
		return {}
	var table = host.get("_table")
	if table == null:
		return {}
	var found: Dictionary = Hilite.request(host, table, bool(host.get("_hit_pixels")))
	if not DebugKeys.enabled():
		return found
	var line := "hint: nothing on this frame answers the mouse"
	if not found.is_empty():
		line = "hint: ch%d  %d:%d  %s  click (%d,%d)" % [
			int(found["channel"]), int(found["cast_lib"]), int(found["cast_id"]),
			str(found["reason"]),
			int((found["point"] as Vector2).x), int((found["point"] as Vector2).y),
		]
	var shown: Array = Toast.show(line)
	host.set("_toast", str(shown[0]))
	host.set("_toast_until", int(shown[1]))
	return found
