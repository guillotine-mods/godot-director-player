extends RefCounted
## The whole session, written down and read back — an emulator's save state.
##
## The point of this is **reproduction**. A bug arrives as a sentence, and the
## four facts `preview/snapshot.gd` copies to the clipboard turn it into
## something you can look at; this turns it into something you can *run*. Save on
## the frame the bug happened, hand over the file, and the engine comes back up
## in that state — same movie, same frame, same globals, same puppets.
##
## ## The rule this file is built around
##
## **Every field on the node is accounted for, in `ACCOUNTED`, as saved, rebuilt
## or excluded-and-why.** Not "the important ones". `tools/save_state.gd` reads
## the node's own property list and fails when a field exists that this table
## does not name, so a field added by a later change cannot silently fall out of
## the save: the harness goes red the first time anybody runs it, rather than the
## save quietly reproducing a slightly different session for ever.
##
## That inversion is the whole design. A "saves everything" claim that nothing
## can check is worth nothing, and this repo has shipped two features that looked
## implemented and reached nothing.
##
## ## Three kinds of state
##
## **Saved** is anything a script can observe or write: the Lingo globals (both
## dictionaries — see `preview/boot.gd:start_lingo`, they are session state and
## are carried across `go to movie`), puppet overrides, field text, channel
## cursors and constraints, the `play` stack, the frame clock's hold, the palette,
## the score's sound channels, the open windows.
##
## **Rebuilt** is anything derived from the container: the score, the cast table,
## the labels, the interpreter and its compiled bundles, the decoded textures and
## hit images, the film loops, the preloader. Opening the movie produces all of
## it, and serialising a `Texture2D` would be storing a slower way of getting the
## same bytes.
##
## **Excluded** is what cannot mean anything in another process — an
## `AudioStreamPlayer`'s playback position, a `Node` reference, a pointer to an
## AST node inside a frozen handler — plus a short list of in-flight things a
## save can never catch mid-way, because the save key is read in `_input`, which
## runs between frames and never inside a click or a dispatch.
##
## ## What a window is
##
## A Movie-In-A-Window is another whole movie (§14, and the essay in
## `director_preview.gd`), so its state is *this same record* nested under
## `windows`. Globals and field text are deliberately **not** re-installed into a
## window on restore: `_share_movie_state_with` makes the window's dictionaries
## the same objects as the stage's, and writing a copy into one would break the
## sharing the corpus depends on — `SAVELOAD` writes `nof` in a window and the
## stage reads it.

const LingoValue := preload("res://lingo/lingo_value.gd")

## The format. Bumped when a record written by an older engine can no longer be
## read, which is a different question from the commit stamp: the commit says
## "a different build wrote this" and is a warning, this says "the reader cannot
## understand these bytes" and is a refusal.
const VERSION := 1

## Every `_`-prefixed field on `scenes/director_preview.gd`, and what this file
## does about it. `tools/save_state.gd` asserts that the node's own property list
## and this table name the same set, in both directions.
##
## The value is the verdict and, where it is not `saved`, the reason. Read it as
## the answer to "why is my bug not reproducing" — if a field is `rebuilt` or
## `excluded` and your bug is in it, the entry says what to do about it.
const ACCOUNTED := {
	# ---------------------------------------------------------------- saved
	"_index": "saved",
	"_ticks": "saved",
	"_entered_index": "saved",
	"_held": "saved",
	"_jump_queued": "saved",
	# Saved for the same reason `held` and `jump_queued` are: it is a statement
	# about the step the save was taken *inside*. A movie paused on a frame whose
	# `exitFrame` calls `pause` comes back with the latch clear if this is dropped,
	# so the first step after the load re-sends that `exitFrame`, re-pauses, and the
	# restored session can never be resumed — a load that looks like a hang.
	"_exit_frame_called": "saved",
	# Saved for that same reason, one step finer: it is only ever true between a
	# `play done` and the frame entry it returns through. Dropped, that entry
	# clears the latch, the caller's `exitFrame` runs a second time, and a handler
	# whose `play` is what parked it plays again -- the loop this flag exists to
	# break, re-armed by the load.
	"_returning_from_play": "saved",
	"_skip_sent": "saved",
	"_overrides": "saved",
	"_field_text": "saved",
	"_member_editable": "saved",
	# Both are the same kind of thing one step along: a member property a script
	# wrote, which the cast does not carry and a reload cannot re-derive. A
	# restored session that drops them shows the pre-script artwork -- an unlit
	# button, text back at its authored size -- which reads as the save having
	# been taken a moment earlier than it was.
	"_member_hilite": "saved",
	"_member_style": "saved",
	"_channel_cursors": "saved",
	"_channel_constraints": "saved",
	"_last_member": "saved",
	"_loop_start": "saved",
	"_play_stack": "saved",
	# Saved, and then re-arbitrated. `text_focus.gd:arbitrate` re-decides the pair
	# from the frame's editable sprites on every paint and *keeps* them when they
	# still name one of its candidates — so what the record buys is which of
	# several editable fields holds focus, and on a frame with none it lands at
	# zero however it was saved. That is Director's behaviour rather than a loss.
	"_focus_channel": "saved: subject to `text_focus.gd:arbitrate` on the next paint",
	"_focus_member": "saved: with the focus channel",
	"_sel_start": "saved",
	"_sel_end": "saved",
	"_global_cursor": "saved",
	"_paused": "saved",
	"_show_boxes": "saved",
	# The collision-zone overlay, which arrived while this table was being written
	# and is why the check that caught it fails both ways. The toggle is saved
	# beside `_show_boxes` because it is the same kind of thing -- a view the user
	# chose. The zones themselves are not: they accumulate as scripts ask
	# `intersects` / `within`, so a restored session repopulates them the first
	# time it asks, and saving them would freeze one playthrough's questions into
	# a state meant to reproduce the answers.
	"_show_collisions": "saved",
	"_collision_channels": "rebuilt: repopulated as scripts ask `intersects`",
	"_hit_pixels": "saved",
	"_fast_forward_fps": "saved",
	"_aspect": "saved",
	"_lingo_on": "saved",
	"_transitions_played": "saved",
	"_puppet_transition": "saved",
	"_sent": "saved",
	"_ran": "saved",
	"_traced": "saved",
	"_loop_stats": "saved",
	"_last_click": "saved",
	"_mouse_down_seen": "saved",
	"_clock": "saved: fps, the hold and its reason, and the three waits",
	"_palette_state": "saved: the ids and the cycling offsets",
	"_score_sound": "saved: what the score put on each channel, and the puppet claims",
	"_window_type": "saved",
	"_center_stage": "saved",
	"_window_rect": "saved",
	"_draw_rect": "saved",
	"_window_title": "saved",
	"_title_visible": "saved",
	"_modal": "saved",
	"_window_shown": "saved",
	"_window_key": "saved: names the window, and is what `lingo_window` is asked for",
	"_window_path": "saved",
	"_windows": "saved: each one is this same record, nested",
	"_window_order": "saved: the stacking order, which decides who takes a click",
	"_interpreter": "saved: its `globals` dictionary. The bundles are rebuilt.",
	"_host": "saved: globals, the four script hooks and the last key. Counters rebuilt.",

	# -------------------------------------------------------------- rebuilt
	"_movie": "rebuilt: the container is reopened from the path in the record",
	"_score": "rebuilt: parsed from the reopened container",
	"_labels": "rebuilt: parsed from the reopened container",
	"_table": "rebuilt: the cast table is opened against the container",
	"_config": "rebuilt: read from the reopened container",
	"_ccl": "rebuilt: the movie's own film-loop cast list",
	"_palette": "rebuilt: the table `_palette_state` resolves its ids to",
	"_paths": "rebuilt: the game root comes from the record, through `load_config`",
	"_preloader": "rebuilt: it holds only which frames it has already paid for",
	"_script_casts": "rebuilt: compiled with the interpreter",
	"_lib_keys": "rebuilt: compiled with the interpreter",
	"_audio": "rebuilt: the autoload is found by name",
	"_stage_preview": "rebuilt: a window is re-parented to the stage that restores it",
	"_textures": "rebuilt: a decoded Texture2D is a slower copy of bytes already on disk",
	"_hit_images": "rebuilt: decoded with the textures",
	"_hilite_textures": "rebuilt: derived from `_hit_images` on the first press",
	"_loops": "rebuilt: a film loop is parsed on first draw",
	"_text_drawn": "rebuilt: what the last paint laid out; the next paint writes it",
	"_clip_rect": "rebuilt: `_clip_to_stage` re-arms it every paint",
	"_cursor_applied": "rebuilt: cleared so the restored cursor is genuinely pushed",
	"_cursor_now": "rebuilt: `_resolve_cursor` recomputes it from `_global_cursor`,"
		+ " the channel cursors and what is hovered — all three of which are"
		+ " restored, so writing this down as well would be storing the answer"
		+ " beside its inputs for the two to disagree over",
	"_last_save": "excluded: which file this session last loaded. A fact about"
		+ " the loader, not about the movie — and a save that carried it would"
		+ " make quick-load's target depend on the save you happened to open.",
	"_pending_enter": "rebuilt: a bool is saved and the frame script re-resolved from `_index`",
	"_hover_channel": "rebuilt: a hit test at the live pointer",
	"_rollover_channel": "rebuilt: with the hover channel",
	"_pointer": "rebuilt: from the pointer of the process that loads",
	"_pointer_seen": "rebuilt: with the pointer",
	"_pointer_from_events": "rebuilt: a property of the machine, not of the session",
	"_caret_since": "rebuilt: the blink phase restarts, which is what a keystroke does",

	# ------------------------------------------------------------- excluded
	"_trail_image": "excluded: an accumulation of past paints. No script can read"
		+ " it (`the picture of window` is unimplemented, §16.25), and embedding a"
		+ " 640x480 PNG per save buys pixels nothing can act on. The sidecar PNG"
		+ " shows them.",
	"_trail_layer": "excluded: the texture over `_trail_image`",
	"_trail_placed": "excluded: with the trail image",
	"_trail_dirty": "excluded: with the trail image",
	"_press_target": "excluded: a Node, and a half-finished click. The save key is"
		+ " read in `_input`, which never runs inside one.",
	"_press_channel": "excluded: with the press",
	"_press_member": "excluded: with the press",
	"_click_script": "excluded: with the press",
	"_chain": "excluded: the queued recipients of a mouse message in flight",
	"_drag_channel": "excluded: a drag is a button being held, and a held button"
		+ " does not survive a process",
	"_drag_offset": "excluded: with the drag",
	"_text_drag": "excluded: with the drag",
	"_saw_press": "excluded: with the press",
	"_typed_away": "excluded: with the press",
	"_frozen_lingo": "excluded: a chain of positions inside compiled AST nodes,"
		+ " which are objects of this process. The queue drains inside the step"
		+ " that filled it, so a save taken from `_input` finds it empty — the"
		+ " record carries the depth and the load says so if it was not.",
	"_frozen_play": "excluded: with the frozen chains",
	"_enter_frame_froze": "excluded: with the frozen chains",
	"_frozen_parked": "excluded: a session counter for the frozen chains",
	"_in_exit_frame": "excluded: true only during a dispatch, and `_input` is not one",
	"_toast": "excluded: a message that dismisses itself in two seconds",
	"_toast_until": "excluded: with the toast",
	"_status": "excluded: the HUD line, rebuilt from the state around it",
	"_picker": "excluded: the container picker is closed by loading, deliberately —"
		+ " it takes every key while open and a restored session must take none",
}

## Keys `capture` always writes. `tools/save_state.gd` asserts the record carries
## every one of them, so a capture that silently stopped emitting a section is a
## failure rather than a comparison over a smaller set.
const REQUIRED := [
	"version", "movie", "index", "ticks", "interpreter_globals", "host_globals",
	"overrides", "field_text", "member_editable", "channel_cursors",
	"channel_constraints", "last_member", "loop_start", "skip_sent",
	"play_stack", "clock", "palette", "score_sound", "focus", "hooks",
	"flags", "counters", "windows", "sound", "frozen",
]


# ---------------------------------------------------------------- capturing

## The whole session as a JSON-safe dictionary.
##
## `movie` is stored root-relative and lower-cased — the same spelling
## `DirectorPaths.containers()` hands out and `resolve` matches on — so a save
## names the file rather than this machine's checkout, and the two `MASTER.CST`
## this corpus ships stay distinguishable by their subdirectory.
static func capture(host) -> Dictionary:
	var out: Dictionary = {
		"version": VERSION,
		"movie": _movie_key(host),
		"index": int(host._index),
		"ticks": int(host._ticks),
		"entered_index": int(host._entered_index),
		"held": bool(host._held),
		"jump_queued": bool(host._jump_queued),
		"exit_frame_called": bool(host._exit_frame_called),
		"returning_from_play": bool(host._returning_from_play),
		"pending_enter": host._pending_enter != null,
		"interpreter_globals": encode(
			host._interpreter.globals if host._interpreter != null else {}),
		"host_globals": encode(host._host.globals if host._host != null else {}),
		"overrides": encode(host._overrides),
		"field_text": encode(host._field_text),
		"member_editable": encode(host._member_editable),
		"member_hilite": encode(host._member_hilite),
		"member_style": encode(host._member_style),
		"channel_cursors": encode(host._channel_cursors),
		"channel_constraints": encode(host._channel_constraints),
		"last_member": encode(host._last_member),
		"loop_start": encode(host._loop_start),
		"skip_sent": encode(host._skip_sent),
		"play_stack": encode(host._play_stack),
		"puppet_transition": encode(host._puppet_transition),
		"clock": host._clock.state(),
		"palette": host._palette_state.state(),
		"score_sound": host._score_sound.state(),
		"focus": {
			"channel": int(host._focus_channel),
			"member": int(host._focus_member),
			"sel_start": int(host._sel_start),
			"sel_end": int(host._sel_end),
		},
		"hooks": _hooks_of(host),
		"flags": {
			"paused": bool(host._paused),
			"show_boxes": bool(host._show_boxes),
			"hit_pixels": bool(host._hit_pixels),
			"lingo_on": bool(host._lingo_on),
			"fast_forward_fps": float(host._fast_forward_fps),
			"aspect": str(host._aspect),
			"global_cursor": encode(host._global_cursor),
			"mouse_down_seen": bool(host._mouse_down_seen),
		},
		"counters": {
			"sent": encode(host._sent),
			"ran": encode(host._ran),
			"traced": encode(host._traced),
			"loop_stats": encode(host._loop_stats),
			"transitions_played": int(host._transitions_played),
			"last_click": encode(host._last_click),
		},
		"window": _window_props_of(host),
		"windows": _windows_of(host),
		"sound": _sound_of(host),
		# Not restorable and not meant to be — see `ACCOUNTED`. Recorded because a
		# non-zero value means the save was taken somewhere `_input` should not have
		# been able to reach, and that is worth saying out loud on the load.
		"frozen": {
			"parked": int(host._frozen_parked),
			"pending": int((host._frozen_lingo as Array).size()),
			"play_pending": 0 if (host._frozen_play as Array).is_empty() else 1,
		},
	}
	return out


## A window's record: this same capture, plus the properties that make it a
## window. Its `windows` is always empty — a window in this port cannot open one.
static func _windows_of(host) -> Array:
	var out: Array = []
	for key in host._window_order:
		var node: Node = host._windows.get(key)
		if node == null:
			continue
		var record: Dictionary = capture(node)
		record["key"] = str(key)
		out.append(record)
	# A window created but never opened is still addressable — all 21 sites in
	# this corpus set properties on one before `open`, so a save between those two
	# statements has to keep it.
	for key in host._windows:
		if host._window_order.has(key):
			continue
		var node: Node = host._windows.get(key)
		if node == null:
			continue
		var record: Dictionary = capture(node)
		record["key"] = str(key)
		record["unordered"] = true
		out.append(record)
	return out


static func _window_props_of(host) -> Dictionary:
	return {
		"key": str(host._window_key),
		"path": _relative(host, str(host._window_path)),
		"type": int(host._window_type),
		"center_stage": bool(host._center_stage),
		"shown": bool(host._window_shown),
		"modal": bool(host._modal),
		"title": str(host._window_title),
		"title_visible": bool(host._title_visible),
		"rect": _rect_or_null(host._window_rect),
		"draw_rect": _rect_or_null(host._draw_rect),
	}


static func _hooks_of(host) -> Dictionary:
	if host._host == null:
		return {}
	return {
		"key_down_script": str(host._host.key_down_script),
		"key_up_script": str(host._host.key_up_script),
		"mouse_down_script": str(host._host.mouse_down_script),
		"mouse_up_script": str(host._host.mouse_up_script),
		"key_code": int(host._host.key_code),
		"key_char": str(host._host.key_char),
		"click_sprite": int(host._host.click_sprite),
		"click_loc": [host._host.click_loc.x, host._host.click_loc.y],
		"double_click": bool(host._host.double_click),
		# The movie-wide properties a script can set and then be restored into the
		# middle of.
		#
		# `the timer` is deliberately *not* here, and it is the one field on the
		# host that is excluded rather than saved. It is a live clock read off the
		# engine's millisecond counter, so its origin means nothing in a second
		# process and its elapsed value has already moved by the time anything
		# compares two records -- which is what it did: three of this file's
		# byte-exact comparisons failed by the eight ticks the restore took.
		# `_restore_hooks` starts it fresh instead, which is what a movie that had
		# just called `startTimer` sees, and the only cost is that the next
		# `if the timer > clockspeed` in a restored session waits a full period.
		"search_path": (host._host.search_path as Array).duplicate(),
		"exit_lock": bool(host._host.exit_lock),
		"playback_paused": bool(host._host.playback_paused),
	}


## `the soundLevel` and the per-channel volumes, which are session settings a
## script writes. What is *playing* is not here: see `restore_sound`.
static func _sound_of(host) -> Dictionary:
	var audio: Node = host._audio
	if audio == null:
		return {}
	var volumes: Dictionary = {}
	for channel in range(1, 9):
		volumes[str(channel)] = int(audio.call("channel_volume", channel))
	return {"level": int(audio.get("sound_level")), "volumes": volumes}


# --------------------------------------------------------------- restoring

## Put a captured record back onto a live preview. Returns "" or why not.
##
## **The movie is not opened here.** The caller decides how it arrives — the boot
## path loads the container directly, an in-session load uses the engine's own
## `go to movie` so the movie is entered exactly as the game would enter it — and
## both then call this. Doing it here would mean `restore` had two behaviours
## depending on which one called it, which is the split `movie_session.gd:adopt`
## exists to have removed.
static func restore(host, data: Dictionary, shared: bool = false) -> String:
	if int(data.get("version", 0)) != VERSION:
		return "save format %s, this engine reads %d" % [
			str(data.get("version", "?")), VERSION]
	if host._score == null:
		return "no movie is open to restore onto"

	# Globals first: everything below may be read by a handler this restore
	# triggers, and a room that runs on the old globals for one frame is exactly
	# the bug `boot.gd:start_lingo` describes.
	#
	# `shared` is a window whose dictionaries are the *same objects* as the
	# stage's (`_share_movie_state_with`). Installing a copy into one would break
	# that sharing, and `SAVELOAD` writing `nof` for the stage to read is the
	# corpus's own case.
	if not shared:
		if host._interpreter != null:
			_fill(host._interpreter.globals, decode(data.get("interpreter_globals", {})))
		if host._host != null:
			_fill(host._host.globals, decode(data.get("host_globals", {})))
		_fill(host._field_text, decode(data.get("field_text", {})))
		_fill(host._member_editable, decode(data.get("member_editable", {})))
		_fill(host._member_hilite, decode(data.get("member_hilite", {})))
		_fill(host._member_style, decode(data.get("member_style", {})))

	_fill_int_keyed(host._overrides, decode(data.get("overrides", {})))
	_fill_int_keyed(host._channel_cursors, decode(data.get("channel_cursors", {})))
	_fill_int_keyed(host._channel_constraints, decode(data.get("channel_constraints", {})))
	_fill_int_keyed(host._last_member, decode(data.get("last_member", {})))
	_fill_int_keyed(host._loop_start, decode(data.get("loop_start", {})))
	_fill_int_keyed(host._skip_sent, decode(data.get("skip_sent", {})))
	host._play_stack = decode(data.get("play_stack", []))
	host._puppet_transition = decode(data.get("puppet_transition", {}))

	host._clock.restore_state(data.get("clock", {}))
	host._palette_state.restore_state(data.get("palette", {}))
	host._palette = host._palette_state.table
	host._score_sound.restore_state(data.get("score_sound", {}))

	var focus: Dictionary = data.get("focus", {})
	host._focus_channel = int(focus.get("channel", 0))
	host._focus_member = int(focus.get("member", 0))
	host._sel_start = int(focus.get("sel_start", 0))
	host._sel_end = int(focus.get("sel_end", 0))
	host._caret_since = Time.get_ticks_msec()

	_restore_hooks(host, data.get("hooks", {}))

	var flags: Dictionary = data.get("flags", {})
	host._paused = bool(flags.get("paused", false))
	host._show_boxes = bool(flags.get("show_boxes", true))
	host._hit_pixels = bool(flags.get("hit_pixels", true))
	host._lingo_on = bool(flags.get("lingo_on", true))
	host._fast_forward_fps = float(flags.get("fast_forward_fps", 0.0))
	host._aspect = str(flags.get("aspect", host._aspect))
	host._global_cursor = decode(flags.get("global_cursor", 0))
	host._mouse_down_seen = bool(flags.get("mouse_down_seen", false))

	var counters: Dictionary = data.get("counters", {})
	host._sent = decode(counters.get("sent", {}))
	host._ran = decode(counters.get("ran", {}))
	host._traced = decode(counters.get("traced", []))
	host._loop_stats = decode(counters.get("loop_stats", {}))
	host._transitions_played = int(counters.get("transitions_played", 0))
	host._last_click = decode(counters.get("last_click", {}))

	_restore_window_props(host, data.get("window", {}))
	restore_sound(host, data.get("sound", {}))

	# The playhead last, because everything above can be read by the frame it
	# lands on.
	#
	# **`_entered_index` is restored verbatim, not forced apart from `_index`.**
	# Forcing a re-entry looks safer and is wrong: `frame_loop.gd:sync_frame_entry`
	# re-arms the frame's tempo, its wait, its transition and its sound channels
	# from scratch, so a save taken 1,400 ms into a two-second delay would come
	# back with the whole delay ahead of it and the room's sound restarted. The
	# clock, the palette and the score's channels are restored above precisely so
	# that entry does not have to be re-run. If the record says the frame had not
	# been entered yet — which is what `_index != _entered_index` means — then the
	# next tick enters it, exactly as the saved session's next tick would have.
	host._index = clampi(int(data.get("index", 0)), 0,
		maxi(host._score.frame_count - 1, 0))
	host._ticks = int(data.get("ticks", 0))
	host._held = bool(data.get("held", false))
	host._jump_queued = bool(data.get("jump_queued", false))
	host._exit_frame_called = bool(data.get("exit_frame_called", false))
	host._returning_from_play = bool(data.get("returning_from_play", false))
	host._entered_index = int(data.get("entered_index", -1))
	host._pending_enter = (host.call("_frame_script", host._index)
		if bool(data.get("pending_enter", false)) else null)

	# The caches keyed against the movie that was open a moment ago. Cleared
	# rather than trusted: `_textures` is keyed by library and member number and
	# both are per movie, so a stale entry resolves to a *real* image of the wrong
	# thing, which reads as corruption rather than as an error.
	host._textures.clear()
	host._hit_images.clear()
	host._hilite_textures.clear()
	host._loops.clear()
	host._cursor_applied = "?none"
	host.call("_resolve_cursor")
	host.queue_redraw()

	var frozen: Dictionary = data.get("frozen", {})
	if int(frozen.get("pending", 0)) > 0 or int(frozen.get("play_pending", 0)) > 0:
		push_warning(("save: %d frozen handler(s) were parked when this was written"
			+ " and cannot be restored; the movie resumes without them")
			% [int(frozen.get("pending", 0)) + int(frozen.get("play_pending", 0))])
	return ""


## Audio, which is the one place a save is deliberately lossy.
##
## The levels are session state a script writes and are put back. What is
## *playing* is not: an `AudioStreamPlayer`'s position is this process's, and a
## restored session that resumed a line of speech three seconds in would be
## reproducing something the movie never did. Every channel is stopped instead,
## which is the state a movie's own `sound playFile` re-establishes on the frame
## that wanted it — and a `soundBusy` wait that was holding is released by the
## clock state, not by the sound.
static func restore_sound(host, data: Dictionary) -> void:
	var audio: Node = host._audio
	if audio == null or data.is_empty():
		return
	audio.call("stop_all")
	audio.call("set_sound_level", int(data.get("level", 7)))
	var volumes: Dictionary = data.get("volumes", {})
	for key in volumes:
		audio.call("set_channel_volume", int(str(key)), int(volumes[key]))


static func _restore_hooks(host, hooks: Dictionary) -> void:
	if host._host == null or hooks.is_empty():
		return
	host._host.key_down_script = str(hooks.get("key_down_script", ""))
	host._host.key_up_script = str(hooks.get("key_up_script", ""))
	host._host.mouse_down_script = str(hooks.get("mouse_down_script", ""))
	host._host.mouse_up_script = str(hooks.get("mouse_up_script", ""))
	host._host.key_code = int(hooks.get("key_code", -1))
	host._host.key_char = str(hooks.get("key_char", ""))
	host._host.click_sprite = int(hooks.get("click_sprite", 0))
	var at: Array = hooks.get("click_loc", [0, 0])
	host._host.click_loc = Vector2(float(at[0]), float(at[1])) if at.size() >= 2 else Vector2.ZERO
	host._host.double_click = bool(hooks.get("double_click", false))
	# Through `set_system_prop` rather than onto the fields, so the restore takes
	# the same coercion and the same side effects the write takes -- the search
	# path reaches the audio resolver rather than only the host.
	host._host.set_system_prop("searchpath", hooks.get("search_path", [""]))
	host._host.set_system_prop("exitlock", 1 if bool(hooks.get("exit_lock", false)) else 0)
	host._host.playback_paused = bool(hooks.get("playback_paused", false))
	# Not restored, started. See `_hooks_of`.
	host._host.timer_reset_ms = Time.get_ticks_msec()


static func _restore_window_props(host, props: Dictionary) -> void:
	if props.is_empty():
		return
	host._window_type = int(props.get("type", host._window_type))
	host._center_stage = bool(props.get("center_stage", false))
	host._modal = bool(props.get("modal", false))
	host._window_title = str(props.get("title", ""))
	host._title_visible = bool(props.get("title_visible", true))
	host._window_rect = _rect_from(props.get("rect", null))
	host._draw_rect = _rect_from(props.get("draw_rect", null))
	if host._window_key != "":
		if bool(props.get("shown", false)):
			host.call("window_shown")
		else:
			host.call("window_hidden")


## Reopen the windows a save had open, in the order it had them.
##
## Called after `restore`, because a window is a child node of the stage and the
## stage has to be standing first. Each one is created through the engine's own
## `lingo_window`, so it arrives loaded and sharing the stage's globals and field
## text, exactly as a script's `window("x")` would produce it — and then its own
## record is restored onto it.
##
## **The stage's shared dictionaries are re-applied at the end**, and that is not
## belt-and-braces. `lingo_open_window` runs the window movie's `prepareMovie`
## and `startMovie` (`director_preview.gd:window_shown`), those handlers write
## globals, and the globals dictionary is the *stage's own object* — so opening a
## window during a restore overwrites some of the state that was just put back.
## Measured: reopening this corpus's boot movie in a window puts
## `soundspathstart` into the restored globals, which the saved session did not
## have at that point. Re-filling afterwards is what makes the record the final
## word rather than whatever the last window's opening handler happened to say.
static func restore_windows(host, data: Dictionary) -> void:
	for key in host._windows.keys():
		host.call("lingo_forget_window", str(key), true)
	for record_value in (data.get("windows", []) as Array):
		var record: Dictionary = record_value
		var key := str(record.get("key", ""))
		if key == "":
			continue
		# By the *path*, not the key. `lingo_window` resolves what it is handed
		# through `DirectorPaths.resolve`, and a key is the basename with the
		# extension stripped -- so asking for "saveload" makes resolution guess at
		# a packaging while asking for "saveload.dxr" names the file. The key it
		# derives from either is the same, so the window lands in the same slot.
		var props: Dictionary = record.get("window", {})
		var named := str(props.get("path", ""))
		host.call("lingo_window", named if named != "" else key)
		var node: Node = host._windows.get(key)
		if node == null:
			continue
		if bool(props.get("shown", false)) and not bool(record.get("unordered", false)):
			host.call("lingo_open_window", key)
		# `shared` — a window's globals and field text are the stage's own
		# dictionaries, already restored above.
		var failed: String = restore(node, record, true)
		if failed != "":
			push_warning("save: window %s: %s" % [key, failed])
	if host._interpreter != null:
		_fill(host._interpreter.globals, decode(data.get("interpreter_globals", {})))
	if host._host != null:
		_fill(host._host.globals, decode(data.get("host_globals", {})))
	_fill(host._field_text, decode(data.get("field_text", {})))
	_fill(host._member_editable, decode(data.get("member_editable", {})))
	_fill(host._member_hilite, decode(data.get("member_hilite", {})))
	_fill(host._member_style, decode(data.get("member_style", {})))


# ------------------------------------------------------------------- naming

## The movie's path relative to the game root, lower-cased. See `capture`.
static func _movie_key(host) -> String:
	return _relative(host, str(host._movie.path) if host._movie != null else "")


static func _relative(host, path: String) -> String:
	if path == "" or host._paths == null:
		return path
	var base := str(host._paths.root).trim_suffix("/")
	if path.begins_with(base + "/"):
		return path.substr(base.length() + 1).to_lower()
	return path.get_file().to_lower()


# ----------------------------------------------------------------- reading

## The globals, formatted to be read rather than parsed. What Shift+F1 prints.
##
## Both dictionaries, because both exist and only one of them is usually
## populated: `owns_global` on the host answers "do I already hold this name" and
## nothing seeds the host's, so every global a script declares lives in the
## interpreter's. Printing only that one would be right today and silently wrong
## the first time the host claims a name.
static func globals_text(host) -> String:
	var lines: Array[String] = []
	lines.append("globals — %s frame %d" % [host.movie_name(), int(host._index)])
	lines.append(_globals_block("interpreter",
		host._interpreter.globals if host._interpreter != null else {}))
	lines.append(_globals_block("host",
		host._host.globals if host._host != null else {}))
	return "\n".join(lines)


static func _globals_block(label: String, globals: Dictionary) -> String:
	if globals.is_empty():
		return "  %s: none" % label
	var names: Array = globals.keys()
	names.sort()
	var width := 0
	for name in names:
		width = maxi(width, str(name).length())
	var lines: Array[String] = ["  %s (%d):" % [label, globals.size()]]
	for name in names:
		lines.append("    %s = %s" % [
			str(name).rpad(width), _readable(globals[name])])
	return "\n".join(lines)


## One value, printed so a list reads as a list and a symbol reads as a symbol.
## `LingoValue.to_str` flattens a property list to `str(Dictionary)` and turns
## VOID into "", which is exactly the two cases somebody staring at a globals
## dump needs told apart.
static func _readable(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "VOID"
		TYPE_STRING:
			return JSON.stringify(value)
		TYPE_STRING_NAME:
			return "#%s" % str(value)
		TYPE_VECTOR2:
			var p: Vector2 = value
			return "point(%d, %d)" % [int(p.x), int(p.y)]
		TYPE_RECT2:
			var r: Rect2 = value
			return "rect(%d, %d, %d, %d)" % [
				int(r.position.x), int(r.position.y), int(r.end.x), int(r.end.y)]
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(_readable(item))
			return "[%s]" % ", ".join(parts)
		TYPE_DICTIONARY:
			var pairs := PackedStringArray()
			for key in value:
				pairs.append("%s: %s" % [str(key), _readable(value[key])])
			return "[%s]" % ", ".join(pairs) if not (value as Dictionary).is_empty() else "[:]"
	return str(value)


# ---------------------------------------------------------------- encoding

## Lingo values, tagged so JSON gives back what it was handed.
##
## Untagged JSON loses four distinctions that matter here and one that is fatal:
## an integer comes back as a float (so `the frame` becomes 12.0 and every
## `LingoValue.equal` against a member number still passes but every `str()`
## prints "12" via a float path), a symbol comes back as a string, a point comes
## back as an array, VOID comes back as null and is indistinguishable from a key
## that was absent, and **a Dictionary with integer keys comes back with string
## keys** — which is every channel-keyed dictionary on the node.
##
## So each value carries its type. Verbose, and the verbosity is the feature: a
## save is read by a human looking for why a bug reproduces differently.
static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return {"t": "void"}
		TYPE_BOOL:
			return {"t": "bool", "v": bool(value)}
		TYPE_INT:
			return {"t": "i", "v": int(value)}
		TYPE_FLOAT:
			return {"t": "f", "v": float(value)}
		TYPE_STRING:
			return {"t": "s", "v": str(value)}
		TYPE_STRING_NAME:
			return {"t": "sym", "v": str(value)}
		TYPE_VECTOR2:
			var p: Vector2 = value
			return {"t": "pt", "v": [p.x, p.y]}
		TYPE_VECTOR2I:
			var pi: Vector2i = value
			return {"t": "pti", "v": [pi.x, pi.y]}
		TYPE_RECT2:
			var r: Rect2 = value
			return {"t": "rect", "v": [r.position.x, r.position.y, r.size.x, r.size.y]}
		TYPE_ARRAY:
			var items: Array = []
			for item in value:
				items.append(encode(item))
			return {"t": "list", "v": items}
		TYPE_PACKED_STRING_ARRAY:
			var strings: Array = []
			for item in value:
				strings.append(str(item))
			return {"t": "psa", "v": strings}
		TYPE_DICTIONARY:
			# Pairs rather than an object, because Director's property lists are
			# ordered and a JSON object is not, and because the key may be an
			# integer — every channel-keyed dictionary on the node is.
			var pairs: Array = []
			for key in value:
				pairs.append([encode(key), encode(value[key])])
			return {"t": "plist", "v": pairs}
	# A value with no encoding is a real finding, not something to drop quietly:
	# it means the interpreter grew a type this file does not know about.
	push_warning("save: no encoding for %s (%s)" % [type_string(typeof(value)), str(value)])
	return {"t": "opaque", "v": str(value)}


static func decode(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return value
	var tagged: Dictionary = value
	match str(tagged.get("t", "")):
		"void":
			return null
		"bool":
			return bool(tagged.get("v", false))
		"i":
			return int(tagged.get("v", 0))
		"f":
			return float(tagged.get("v", 0.0))
		"s", "opaque":
			return str(tagged.get("v", ""))
		"sym":
			return StringName(str(tagged.get("v", "")))
		"pt":
			var p: Array = tagged.get("v", [0, 0])
			return Vector2(float(p[0]), float(p[1]))
		"pti":
			var pi: Array = tagged.get("v", [0, 0])
			return Vector2i(int(pi[0]), int(pi[1]))
		"rect":
			var r: Array = tagged.get("v", [0, 0, 0, 0])
			return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		"list":
			var items: Array = []
			for item in (tagged.get("v", []) as Array):
				items.append(decode(item))
			return items
		"psa":
			var strings := PackedStringArray()
			for item in (tagged.get("v", []) as Array):
				strings.append(str(item))
			return strings
		"plist":
			var out: Dictionary = {}
			for pair_value in (tagged.get("v", []) as Array):
				var pair: Array = pair_value
				if pair.size() < 2:
					continue
				out[decode(pair[0])] = decode(pair[1])
			return out
	return value


# ------------------------------------------------------------------ helpers

## Replace a dictionary's contents in place.
##
## In place, not by assignment, and that is the whole reason this exists:
## `_share_movie_state_with` makes a window's globals and field text *the same
## object* as the stage's, and `boot.gd:start_lingo` carries the same object
## across a `go to movie`. Assigning a new dictionary would silently break both
## — the two sides would stop seeing each other's writes, and the symptom is a
## room drawn from state that stopped updating.
static func _fill(target: Dictionary, source: Variant) -> void:
	target.clear()
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary):
		target[key] = (source as Dictionary)[key]


## The same, for the channel-keyed dictionaries, whose keys must come back as
## integers. `encode` already tags them, so this is only a guard for a record
## written by hand or by an older format.
static func _fill_int_keyed(target: Dictionary, source: Variant) -> void:
	target.clear()
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary):
		var value: Variant = (source as Dictionary)[key]
		if typeof(key) == TYPE_STRING and str(key).is_valid_int():
			target[int(str(key))] = value
		else:
			target[key] = value


static func _rect_or_null(rect) -> Variant:
	if rect == null:
		return null
	var r: Rect2 = rect
	return [r.position.x, r.position.y, r.size.x, r.size.y]


static func _rect_from(value: Variant):
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 4:
		return null
	var v: Array = value
	return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
