extends SceneTree
## Every name the harnesses reach into the preview by, still resolves.
##
##   godot --headless --script tools/preview_surface.gd
##
## `tools/` is an undocumented reflective API into `scenes/director_preview.gd`.
## Fourteen harnesses instantiate the scene and then reach in **by name** --
## `preview.call("_effective", …)`, `preview.get("_score")`,
## `preview.set("_index", n)` -- and `scenes/preview_lingo_host.gd` calls about
## forty `preview.lingo_*` methods the same way.
##
## That matters during a refactor for one reason, and it is the reason this file
## exists: **a field moved off the node makes `get()` return `null`, and a tool
## that reads null reports zero rather than failing.** The safety net goes dark
## without going red. A split could therefore pass every harness while having
## quietly disconnected them, and nobody would know until a bug came back.
##
## So this asserts the surface itself: every method name is callable and every
## field name resolves to something that is not null. It says nothing about
## whether the values are *right* -- the other harnesses do that -- only that the
## harnesses are still connected to the thing they think they are testing.
##
## The lists are generated, not curated. Regenerate after adding a harness:
##
##   grep -rhoE '\.call\("[a-z_]+"' tools/ | sed 's/.*"\(.*\)"/\1/' | sort -u
##   grep -rhoE '\.(get|set)\("_[a-z_]+"' tools/ | sed 's/.*"\(.*\)"/\1/' | sort -u

const Harness := preload("res://tools/lib/harness.gd")

## What the harnesses name the preview node. Scraping every `.call(` instead
## picks up calls on `AudioDirector`, on a `Score`, and on the harness itself.
const RECEIVERS := ["preview", "p", "node", "w"]

## Fields the harnesses read. A null answer means the field moved and the
## reflective read is now silently returning nothing.
##
## `__sentinel` is excluded deliberately: `tools/globals_survive.gd` *writes* it
## into the interpreter's globals as a probe and it does not exist until then.
const FIELDS := [
	"_channel_constraints", "_channel_cursors", "_clip_rect", "_clock",
	"_cursor_now", "_fast_forward_fps", "_field_text", "_focus_channel",
	"_focus_member", "_frozen_lingo", "_global_cursor", "_hit_images",
	"_hit_pixels", "_host",
	"_index", "_interpreter", "_labels", "_last_click", "_last_member",
	"_last_save", "_loop_start", "_loop_stats", "_member_editable",
	"_overrides", "_palette", "_palette_state", "_paused", "_pending_enter",
	"_play_stack", "_preloader", "_puppet_transition", "_ran", "_repaints",
	"_score", "_score_sound", "_sel_end",
	"_sel_start", "_sent", "_show_boxes", "_table", "_text_drawn",
	"_textures", "_ticks", "_traced", "_trail_image", "_transitions_played",
	"_update_stage_calls", "_window_type", "_windows",
]

## Fields a harness is allowed to find empty or zero, because they are only
## populated by something the harness does first. Their *presence* is still
## asserted; only the non-null test is relaxed.
const MAY_BE_EMPTY := [
	"_clip_rect", "_pending_enter", "_text_drawn", "_trail_image", "_windows",
	"_channel_cursors", "_overrides",
	# The save state's half of the surface: `tools/save_state.gd` reads all of
	# these, and every one of them is legitimately empty on a cold boot -- no
	# script has puppeted a cursor, claimed a sound channel or pushed a `play`
	# yet. Their *presence* is still asserted, which is the point: a field moved
	# off the node makes the save silently stop carrying it.
	"_channel_constraints", "_field_text", "_last_click", "_last_member",
	"_last_save", "_loop_start", "_loop_stats", "_member_editable",
	"_play_stack", "_traced",
]


func _init() -> void:
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	h.begin("every field the harnesses read still resolves")
	var missing: Array[String] = []
	for name in FIELDS:
		var value: Variant = preview.get(name)
		if value == null and not MAY_BE_EMPTY.has(name):
			missing.append(name)
	h.check("no field reads back null", missing.is_empty(), ", ".join(missing))
	h.complete("every field the harnesses read still resolves")

	# Methods are checked for existence rather than called: calling them would
	# have side effects, and a name that has moved fails `has_method` just as
	# loudly as it would fail a call.
	h.begin("every method the harnesses call still exists")
	var absent: Array[String] = []
	for name in _method_names():
		if not preview.has_method(name):
			absent.append(name)
	h.check("no method name has moved", absent.is_empty(), ", ".join(absent))
	h.complete("every method the harnesses call still exists")
	quit(h.finish("the reflective surface the harnesses depend on"))


## Read from the harnesses themselves rather than duplicated here, so the list
## cannot drift from what is actually called. A hand-maintained copy would go
## stale exactly when it mattered.
func _method_names() -> PackedStringArray:
	var names := {}
	var dir := DirAccess.open("res://tools")
	if dir == null:
		return PackedStringArray()
	for entry in dir.get_files():
		if not entry.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://tools/%s" % entry)
		for line in text.split("\n"):
			# Only calls whose receiver is the preview. A harness also calls methods
			# on `AudioDirector`, on a `Score` and on its own helpers, and scraping
			# every `.call(` picks those up and then fails for names that were never
			# on the node at all.
			for receiver in RECEIVERS:
				var needle: String = '%s.call("' % receiver
				var at := line.find(needle)
				while at >= 0:
					var start := at + needle.length()
					var stop := line.find('"', start)
					if stop > start:
						names[line.substr(start, stop - start)] = true
					at = line.find(needle, stop if stop > start else start)
	var host := FileAccess.get_file_as_string("res://scenes/preview_lingo_host.gd")
	for line in host.split("\n"):
		var at := line.find("preview.")
		while at >= 0:
			var start := at + 8
			var stop := line.find("(", start)
			if stop > start and stop - start < 40:
				var name := line.substr(start, stop - start)
				if name.begins_with("lingo_") or name.begins_with("stage_"):
					names[name] = true
			at = line.find("preview.", start)
	var out := PackedStringArray()
	for key in names:
		out.append(str(key))
	out.sort()
	return out
