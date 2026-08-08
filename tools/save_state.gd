extends SceneTree
## Does a save state reproduce the session — in another process, field by field?
##
##   godot --headless --path . --script tools/save_state.gd
##   godot --path . --script tools/save_state.gd          # + the real keys
##
## Six sections, and the fourth and fifth are the ones that could catch the
## failure this exists to prevent.
##
## **Every field is accounted for.** The node's own property list is read and
## compared against `preview/save_state.gd:ACCOUNTED` in both directions. A field
## added to `director_preview.gd` by any later change and not classified as
## saved, rebuilt or excluded fails here — which is the only way "everything is
## saved" survives contact with a codebase that keeps growing fields. It is the
## same argument `tools/preview_surface.gd` makes about the reflective surface:
## the dangerous failure is the silent one, so the list is generated from the
## thing itself rather than curated.
##
## **The record is whole.** `REQUIRED` names every section `capture` must emit. A
## capture that quietly stopped writing one would otherwise make every comparison
## below pass over a smaller set, which is this repo's own recorded failure mode
## — four harnesses have reported success over an empty set.
##
## **Values survive JSON.** Untagged, an integer comes back a float, a symbol
## comes back a string, VOID comes back indistinguishable from an absent key, and
## a dictionary with integer keys comes back with string keys — which is every
## channel-keyed dictionary on the node. Each type is round-tripped through
## `JSON.stringify`/`parse_string` and compared by *type* as well as value.
##
## **The mutation reaches the record.** Every saved field is written to a value
## it did not have, and the capture is asserted to differ from the one before —
## before anything is restored. Without this the round-trip below is satisfied by
## a `capture` that returns a constant, and this session has already shipped two
## features that looked implemented and reached nothing.
##
## **A save outlives the process that made it.** Two more Godots: the first boots
## the player, mutates, quick-saves and exits; the second is launched with
## `--save <file>` and nothing else, and writes out what it came back up as. This
## process — which has never had either state in memory — compares the two
## records key by key. A single-process test cannot tell "persisted" from "still
## in memory", which is precisely the bug `saveMovie` shipped with.
##
## **The keys work.** Windowed only: real `Shift+F5` / `Shift+F6` / `Shift+F1`
## events through `Input.parse_input_event`, which is the player's own path and
## the only one that shows a chord binding reaching a command. Headless Godot has
## no keyboard focus, so the section is skipped — loudly — without a window.
##
## Title-agnostic: it needs a movie with a score and nothing else. The window it
## opens is the boot movie playing in a window of its own, which every title can
## do.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const SaveState := preload("res://scenes/preview/save_state.gd")
const SaveFiles := preload("res://scenes/preview/save_files.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")

## Where the two-process pair meets. `user://`, not the saves tree: this writes
## on every gate run and the saves tree is the developer's.
const SCRATCH_SAVE := "user://save_state_gate.json"
const SCRATCH_BACK := "user://save_state_gate_reloaded.json"

## Sections of the record the second process cannot be expected to match.
##
## `stamp` carries a wall-clock time and is written by whoever saves; `frozen` is
## a session counter for state that is deliberately not restored (see
## `ACCOUNTED`). Everything else must come back identical, and naming the two
## exceptions here rather than skipping "whatever differs" is what keeps the
## comparison honest.
const NOT_COMPARED := ["stamp", "frozen"]


func _init() -> void:
	var args := Args.parse()
	match Args.text(args, "child", ""):
		"save":
			await _child_save(args)
			return
		"reload":
			await _child_reload(args)
			return
	await _parent(args)


func _parent(args: Dictionary) -> void:
	var h := Harness.new()
	DebugKeys.load_config()
	var windowed := not DisplayServer.get_name().contains("headless")

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	if preview.get("_score") == null:
		print("no movie opened; nothing to save")
		quit(1)
		return

	_accounted(h, preview)
	_shape(h, preview)
	_encoding(h)
	await _round_trip(h, preview)
	await _two_process(h, args, preview)
	await _keys(h, preview, windowed)

	quit(h.finish("a save state reproduces the session it was taken from"))


# ------------------------------------------------- every field is accounted for

## The node's own script variables against `ACCOUNTED`, both ways.
##
## `PROPERTY_USAGE_SCRIPT_VARIABLE` rather than a name filter: it is exactly the
## set `var` declares in `director_preview.gd`, so a built-in Node property that
## happens to start with an underscore cannot drift into the comparison and a
## script variable cannot drift out of it.
func _accounted(h: Harness, preview: Node) -> void:
	h.begin("every field on the node is saved, rebuilt or excluded")
	var declared: Array[String] = []
	for entry in preview.get_property_list():
		var usage := int(entry.get("usage", 0))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := str(entry.get("name", ""))
		if not name.begins_with("_"):
			continue
		declared.append(name)
	h.check("the node declares fields at all (%d)" % declared.size(),
		declared.size() > 40, str(declared.size()))

	var unclassified: Array[String] = []
	for name in declared:
		if not SaveState.ACCOUNTED.has(name):
			unclassified.append(name)
	h.check("no field is unclassified", unclassified.is_empty(),
		"add to save_state.gd ACCOUNTED: %s" % ", ".join(unclassified))

	# The other direction, which is the one that rots: a field renamed or removed
	# leaves an entry here claiming to save something that no longer exists, and a
	# stale inventory is worse than none because it is trusted.
	var stale: Array[String] = []
	for name in SaveState.ACCOUNTED:
		if not declared.has(str(name)):
			stale.append(str(name))
	h.check("no entry names a field that is gone", stale.is_empty(),
		"remove from ACCOUNTED: %s" % ", ".join(stale))

	# Every verdict has to say something. "excluded" with no reason is the shape
	# of an entry added to silence this check.
	var mute: Array[String] = []
	for name in SaveState.ACCOUNTED:
		var verdict := str(SaveState.ACCOUNTED[name])
		if verdict == "saved":
			continue
		if verdict.begins_with("rebuilt:") or verdict.begins_with("excluded:") \
				or verdict.begins_with("saved:"):
			continue
		mute.append("%s -> '%s'" % [str(name), verdict])
	h.check("every verdict that is not a bare 'saved' gives its reason",
		mute.is_empty(), ", ".join(mute))
	h.complete("every field on the node is saved, rebuilt or excluded")


func _shape(h: Harness, preview: Node) -> void:
	h.begin("the record carries every section")
	var record: Dictionary = SaveState.capture(preview)
	var missing: Array[String] = []
	for key in SaveState.REQUIRED:
		if not record.has(key):
			missing.append(str(key))
	h.check("no section is missing", missing.is_empty(), ", ".join(missing))
	# JSON is the format, so a record that will not stringify is not a record.
	var text := JSON.stringify(record)
	h.check("the record is JSON", text != "" and text != "null")
	var back: Variant = JSON.parse_string(text)
	h.check("and parses back to a dictionary", typeof(back) == TYPE_DICTIONARY)
	h.complete("the record carries every section")


# ------------------------------------------------------------------- encoding

## Every Lingo value type, through JSON and back, compared by type and value.
##
## The subjects are the ones `lingo/lingo_builtins.gd` lists as the language's
## representations, plus the two shapes that only exist on the node: a dictionary
## keyed by integer (every channel-keyed field) and a nested list.
func _encoding(h: Harness) -> void:
	h.begin("a Lingo value survives JSON")
	var subjects: Array = [
		0, 1, -12, 3.5, "", "a string", StringName("symbol"), null,
		Vector2(3, 4), Rect2(1, 2, 30, 40),
		[1, "two", StringName("three"), null],
		{"a": 1, "b": [2, 3]},
		{1: "one", 2: {"nested": StringName("s")}},
		true, false,
		PackedStringArray(["x", "y"]),
	]
	for subject in subjects:
		var text := JSON.stringify(SaveState.encode(subject))
		var got: Variant = SaveState.decode(JSON.parse_string(text))
		h.check("%s survives" % _describe(subject),
			typeof(got) == typeof(subject) and _same(got, subject),
			"got %s" % _describe(got))
	# The two that untagged JSON destroys, called out by name because both were
	# live hazards: `12` must not come back `12.0`, and a channel-keyed dictionary
	# must not come back keyed by "3".
	var integer: Variant = SaveState.decode(
		JSON.parse_string(JSON.stringify(SaveState.encode(12))))
	h.check("an integer comes back an integer, not a float",
		typeof(integer) == TYPE_INT, type_string(typeof(integer)))
	var keyed: Variant = SaveState.decode(
		JSON.parse_string(JSON.stringify(SaveState.encode({3: "ch"}))))
	h.check("an integer dictionary key comes back an integer",
		typeof(keyed) == TYPE_DICTIONARY and (keyed as Dictionary).has(3),
		str(keyed))
	h.complete("a Lingo value survives JSON")


# ---------------------------------------------------- mutate, save, restore

## The single-process round trip, with the mutation asserted to have reached the
## record before anything is restored.
func _round_trip(h: Harness, preview: Node) -> void:
	var before: Dictionary = SaveState.capture(preview)
	_mutate(preview, "gate")
	var saved: Dictionary = SaveState.capture(preview)

	h.begin("the mutation reaches the record")
	var reached: Array[String] = []
	for key in saved:
		if NOT_COMPARED.has(str(key)):
			continue
		if JSON.stringify(saved[key]) != JSON.stringify(before.get(key)):
			reached.append(str(key))
	# Named individually, so a section that stopped being captured says which.
	for key in ["interpreter_globals", "host_globals", "overrides", "field_text",
			"channel_cursors", "channel_constraints", "play_stack", "clock",
			"palette", "score_sound", "focus", "hooks", "flags", "counters",
			"skip_sent", "loop_start", "last_member", "windows", "index"]:
		h.check("%s changed when it was written to" % key, reached.has(key),
			"the capture did not see the write")
	h.complete("the mutation reaches the record")

	# Now put the session somewhere else entirely, and restore.
	_mutate(preview, "clobber")
	var clobbered: Dictionary = SaveState.capture(preview)
	h.begin("a restore puts every section back")
	h.check("the session really moved before the restore",
		JSON.stringify(clobbered) != JSON.stringify(saved))
	preview.call("lingo_go_movie", str(saved.get("movie", "")), null)
	var failed: String = SaveState.restore(preview, saved)
	h.check("the restore is accepted", failed == "", failed)
	SaveState.restore_windows(preview, saved)
	await process_frame
	var got: Dictionary = SaveState.capture(preview)
	_compare(h, "restored", saved, got)
	h.complete("a restore puts every section back")


## Write a distinguishable value into every field the record claims to carry.
##
## One function for both the "did the write reach the capture" pass and the
## "clobber it and restore" pass, with `tag` deciding the values, so the two
## cannot drift into testing different fields.
func _mutate(preview: Node, tag: String) -> void:
	var salt := 1 if tag == "gate" else 2
	var host = preview.get("_host")
	var interp = preview.get("_interpreter")
	interp.globals["gate_number"] = 100 * salt
	interp.globals["gate_string"] = "%s value" % tag
	interp.globals["gate_list"] = [salt, StringName(tag), null, Vector2(salt, salt)]
	interp.globals["gate_plist"] = {"k": salt, "j": [tag]}
	host.globals["gate_host"] = salt * 7

	# Puppet state, per field, the way a script writes it.
	preview.call("lingo_set_sprite_prop", 4 + salt, "loch", 111 * salt)
	preview.call("lingo_set_sprite_prop", 4 + salt, "locv", 222 * salt)
	(preview.get("_channel_cursors") as Dictionary)[6] = [salt, salt + 1]
	(preview.get("_channel_constraints") as Dictionary)[7] = salt
	(preview.get("_last_member") as Dictionary)[8] = 40 + salt
	(preview.get("_loop_start") as Dictionary)[9] = 500 * salt
	(preview.get("_skip_sent") as Dictionary)[3 * salt] = true
	(preview.get("_field_text") as Dictionary)["gate:1"] = "%s text" % tag
	(preview.get("_member_editable") as Dictionary)["gate:1"] = salt == 1
	preview.set("_play_stack", [{"movie": "%s.dir" % tag, "frame": salt}])

	# The clock: a hold and a wait, which is what a timing bug is made of.
	var clock = preview.get("_clock")
	clock.fps = 8.0 + salt
	clock.hold(400.0 * salt, "delay")
	clock.clicked()
	if salt == 1:
		clock.enter_frame({"wait_click": true, "delay_ms": 0.0})

	preview.get("_palette_state").set_puppet(-salt)
	preview.get("_score_sound").set_puppet(salt, true)

	# The selection only. `_focus_channel` and `_focus_member` are saved but
	# re-arbitrated from the frame's editable sprites on the next paint
	# (`text_focus.gd:arbitrate`), so writing a channel the frame does not hold an
	# editable field on would be asserting against Director's own behaviour rather
	# than against the save. `the selStart` and `the selEnd` are movie-level and
	# survive, which is the half a save has to carry.
	preview.set("_sel_start", salt)
	preview.set("_sel_end", salt + 3)

	host.key_down_script = "%s_down" % tag
	host.key_up_script = "%s_up" % tag
	host.key_code = 40 + salt
	host.key_char = tag.substr(0, 1)
	host.click_sprite = salt
	host.click_loc = Vector2(11 * salt, 22 * salt)

	preview.set("_show_boxes", salt == 1)
	preview.set("_hit_pixels", salt == 2)
	preview.set("_cursor_now", "gate-%s" % tag)
	preview.set("_global_cursor", salt)
	preview.set("_fast_forward_fps", 30.0 * salt)
	preview.set("_transitions_played", salt)
	preview.set("_sent", {"gate": salt})
	preview.set("_ran", {"gate": salt})
	preview.set("_traced", ["%s trace" % tag])
	preview.set("_loop_stats", {"gate": salt})
	preview.set("_last_click", {
		"at": Vector2(salt, salt), "frame": salt, "channel": salt,
		"tier": tag, "script": tag, "handler": salt == 1,
	})
	preview.set("_ticks", 1000 * salt)
	preview.set("_index", salt)

	# A window, which is a whole second movie and the hardest thing here to put
	# back. The boot movie in a window of its own: every title can do that, and
	# nothing about it is this corpus's.
	var name := str(preview.get("_movie").path).get_file()
	if salt == 1:
		preview.call("lingo_window", name)
		preview.call("lingo_open_window", name)
		# Paused with the stage, or the comparison is against a moving target: a
		# window runs its own `_process`, and one process frame between the save
		# and the restore leaves its clock owing a different fraction of a step and
		# its frame scripts having written a global the saved side never had.
		for key in (preview.get("_windows") as Dictionary):
			var node: Node = (preview.get("_windows") as Dictionary)[key]
			if node != null:
				node.set("_paused", true)
	else:
		preview.call("lingo_forget_window", name, true)

	# Last, so nothing above is undone by a tick between the write and the save.
	preview.set("_paused", true)


## Two records, key by key. Fails on any divergence and says which key.
func _compare(h: Harness, label: String, want: Dictionary, got: Dictionary) -> void:
	var compared := 0
	for key in want:
		if NOT_COMPARED.has(str(key)):
			continue
		compared += 1
		var a := JSON.stringify(want[key])
		var b := JSON.stringify(got.get(key))
		h.check("%s: %s" % [label, str(key)], a == b, _diff(a, b))
	# A comparison over nothing is the failure this harness exists to make
	# impossible, so the count is asserted rather than assumed.
	h.check("%s: the comparison covered the record (%d keys)" % [label, compared],
		compared >= SaveState.REQUIRED.size() - NOT_COMPARED.size())


# --------------------------------------------------------------- two processes

## The assertion a single process cannot make.
func _two_process(h: Harness, args: Dictionary, preview: Node) -> void:
	h.begin("a save outlives the process that wrote it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_BACK))
	var marker := "gate-%d" % Time.get_ticks_usec()

	var wrote := _run_child(h, args, ["--child", "save", "--marker", marker], "saver")
	if not h.check("the saving process exits cleanly", wrote == 0, "exit %d" % wrote):
		h.complete("a save outlives the process that wrote it")
		return
	var saved: Dictionary = SaveFiles.read(ProjectSettings.globalize_path(SCRATCH_SAVE))
	if not h.check("the save file is here and readable", str(saved["error"]) == "",
			str(saved["error"])):
		h.complete("a save outlives the process that wrote it")
		return
	var record: Dictionary = saved["data"]
	var stamp: Dictionary = record.get("stamp", {})
	h.check("it is stamped with the engine commit",
		str(stamp.get("commit", "")) != "" and str(stamp.get("commit", "")) != "unknown",
		str(stamp.get("commit", "none")))
	h.check("and with the game root it was taken in",
		str(stamp.get("root", "")).begins_with("res://games/"), str(stamp.get("root", "")))
	h.check("and it carries the marker the other process wrote",
		JSON.stringify(record.get("interpreter_globals", {})).contains(marker))
	# The one duplicated string across the engine/preview boundary: `director/`
	# reads `stamp.root` by hand because it may not depend on `scenes/`. Both
	# readers, one file, same answer — or the pair has drifted.
	h.check("`--save`'s root reader agrees with the one that wrote it",
		Paths._root_from_save(ProjectSettings.globalize_path(SCRATCH_SAVE))
			== str(stamp.get("root", "")),
		Paths._root_from_save(ProjectSettings.globalize_path(SCRATCH_SAVE)))

	# The stamp is only worth carrying if something acts on it. A save of another
	# game is refused, because every member and channel number in it resolves
	# against *this* game — to real members showing the wrong thing, which reads
	# as corruption rather than as a mismatch. A save from another commit is
	# warned about and loaded, because the person using this is changing the
	# engine daily and refusing would make the feature useless on its second day.
	h.begin("a foreign save is refused and a stale one is warned about")
	var foreign := record.duplicate(true)
	(foreign["stamp"] as Dictionary)["game"] = "not-this-game"
	var refused: Dictionary = SaveFiles.check(preview, foreign)
	h.check("another game refuses", str(refused["refuse"]) != "", str(refused["refuse"]))
	var stale := record.duplicate(true)
	(stale["stamp"] as Dictionary)["commit"] = "0123456789abcdef0123456789abcdef01234567"
	var warned: Dictionary = SaveFiles.check(preview, stale)
	h.check("another commit does not refuse", str(warned["refuse"]) == "",
		str(warned["refuse"]))
	# Naming *both* commits, because "this save is from another build" without
	# saying which two builds is a warning nobody can act on.
	h.check("but does warn, naming both",
		str(warned["warn"]).contains("0123456789ab")
			and str(warned["warn"]).contains(SaveFiles.engine_commit().substr(0, 12)),
		str(warned["warn"]))
	var future := record.duplicate(true)
	future["version"] = SaveState.VERSION + 1
	h.check("a format this engine cannot read refuses",
		str((SaveFiles.check(preview, future) as Dictionary)["refuse"]) != "")
	h.check("and the save in hand is clean",
		str((SaveFiles.check(preview, record) as Dictionary)["refuse"]) == "")
	h.complete("a foreign save is refused and a stale one is warned about")

	# ...and now the whole point: a *third* process boots from that file alone.
	var back := _run_child(h, args, ["--child", "reload",
		"--save", ProjectSettings.globalize_path(SCRATCH_SAVE)], "loader")
	if not h.check("the loading process exits cleanly", back == 0, "exit %d" % back):
		h.complete("a save outlives the process that wrote it")
		return
	var reloaded: Dictionary = SaveFiles.read(ProjectSettings.globalize_path(SCRATCH_BACK))
	if not h.check("it wrote out what it came back up as",
			str(reloaded["error"]) == "", str(reloaded["error"])):
		h.complete("a save outlives the process that wrote it")
		return
	_compare(h, "second process", record, reloaded["data"])
	h.complete("a save outlives the process that wrote it")


func _run_child(h: Harness, args: Dictionary, extra: Array, label: String) -> int:
	var project := ProjectSettings.globalize_path("res://")
	var line := ["--headless", "--path", project,
		"--script", "res://tools/save_state.gd", "--"]
	line.append_array(extra)
	# The child reads `director_game.cfg` for itself, so a parent pinned to one
	# corpus and a child told nothing are two different games. `gate.sh` pins with
	# `--root`, which is what makes this load-bearing rather than tidy.
	if Args.text(args, "root", "") != "":
		line.append_array(["--root", Args.text(args, "root", "")])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), line, out, true)
	for entry in out:
		for row in str(entry).split("\n"):
			if str(row).strip_edges() != "":
				print("    %s | %s" % [label, str(row).strip_edges()])
	return code


# --------------------------------------------------------------------- keys

## The chord bindings, through the path a player's fingers take.
##
## Everything above went in through `SaveState` directly, which proves the record
## and nothing about the wiring. This is `Input.parse_input_event` -> `_input` ->
## `preview/input_router.gd` -> the command, and it needs a window with keyboard
## focus, which headless Godot does not have.
##
## The control matters as much as the assertion: plain F5 must still step the
## playhead, or "Shift+F5 saved" would be satisfied by a dispatch that ignores
## modifiers entirely — which is exactly what it used to do.
func _keys(h: Harness, preview: Node, windowed: bool) -> void:
	h.begin("the chord bindings are reachable at all")
	for command in ["globals", "quick_save", "quick_load", "save_as", "load_file"]:
		var name := DebugKeys.key_name(command)
		h.check("%s is bound (%s)" % [command, name], name.contains("+"),
			"chords are the second band; got '%s'" % name)
		h.check("%s's chord resolves to a command" % command,
			DebugKeys.command_for(OS.find_keycode_from_string(name)) == command,
			DebugKeys.command_for(OS.find_keycode_from_string(name)))
	# The half that was broken: the plain key underneath a chord is a *different*
	# binding, and matching without modifiers collapsed the two.
	h.check("Shift+F5 and F5 are different commands",
		DebugKeys.command_for(OS.find_keycode_from_string("Shift+F5"))
			!= DebugKeys.command_for(KEY_F5),
		DebugKeys.command_for(KEY_F5))
	h.complete("the chord bindings are reachable at all")

	if not windowed:
		print("")
		print("headless: the `_input` wiring for the save keys is unasserted"
			+ " -- rerun without --headless")
		return

	var window := preview.get_window()
	window.grab_focus()
	DisplayServer.window_move_to_foreground()
	await process_frame
	preview.set("_paused", true)
	# This section presses the real key, so it writes the developer's real
	# quick-save. Put back afterwards, the way `tools/save_movie.gd` puts the
	# container back: a gate that quietly overwrites somebody's working state is a
	# gate that costs more than it finds.
	var quick := SaveFiles.quick_path(preview)
	var theirs := FileAccess.get_file_as_bytes(quick)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(quick))

	h.begin("a real Shift+F5 writes the quick-save")
	(preview.get("_interpreter") as Object).get("globals")["gate_windowed"] = 4242
	Input.parse_input_event(_key(KEY_F5, true, true))
	await process_frame
	await process_frame
	h.check("the file is there", FileAccess.file_exists(quick), quick)
	var written: Dictionary = SaveFiles.read(quick)
	h.check("and holds what was in the globals",
		JSON.stringify((written["data"] as Dictionary).get("interpreter_globals", {}))
			.contains("4242"))
	# The control: the same key without shift must still be `step_back`, or the
	# check above is satisfied by a dispatch that ignores modifiers.
	var index_before := int(preview.get("_index"))
	preview.set("_index", maxi(index_before, 3))
	Input.parse_input_event(_key(KEY_F5, true, false))
	await process_frame
	h.check("plain F5 still steps the playhead back",
		int(preview.get("_index")) < maxi(index_before, 3),
		str(preview.get("_index")))
	h.complete("a real Shift+F5 writes the quick-save")

	h.begin("a real Shift+F6 loads it back")
	(preview.get("_interpreter") as Object).get("globals")["gate_windowed"] = 1
	Input.parse_input_event(_key(KEY_F6, true, true))
	await process_frame
	await process_frame
	await process_frame
	h.check("the global came back",
		int((preview.get("_interpreter") as Object).get("globals").get("gate_windowed", 0))
			== 4242,
		str((preview.get("_interpreter") as Object).get("globals").get("gate_windowed", 0)))
	h.complete("a real Shift+F6 loads it back")

	h.begin("a real Shift+F1 prints the globals")
	var text: String = SaveState.globals_text(preview)
	h.check("the report names a global it holds", text.contains("gate_windowed"), text.substr(0, 120))
	Input.parse_input_event(_key(KEY_F1, true, true))
	await process_frame
	# The binding is asserted through the map rather than by capturing stdout:
	# what the key does is print, and a print is not observable from in here.
	h.check("and the chord is what runs it",
		DebugKeys.command_for(KEY_MASK_SHIFT | KEY_F1) == "globals",
		DebugKeys.command_for(KEY_MASK_SHIFT | KEY_F1))
	h.complete("a real Shift+F1 prints the globals")

	h.begin("the developer's quick-save is put back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		SaveFiles.png_for(quick)))
	if theirs.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(quick))
		h.check("there was none, and none is left", not FileAccess.file_exists(quick))
	else:
		var back := FileAccess.open(quick, FileAccess.WRITE)
		if h.check("theirs can be written back", back != null):
			back.store_buffer(theirs)
			back.close()
		h.check("byte-identical to how it was found",
			FileAccess.get_file_as_bytes(quick) == theirs)
	h.complete("the developer's quick-save is put back")


## One keystroke as the OS delivers it. `shift` sets both the modifier flag and
## the modifier mask, because `get_keycode_with_modifiers` reads the flag and
## `director_keys.gd` reads the bare keycode, and a synthetic event that sets
## only one of them tests neither path honestly.
func _key(code: Key, pressed: bool, shift: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	return event


# ------------------------------------------------------------------ children

## Boot, mutate, quick-save to the scratch path, exit.
func _child_save(args: Dictionary) -> void:
	var marker := Args.text(args, "marker", "child")
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	# Held before the first frame is awaited: a movie's own opening script
	# frequently sends the playhead somewhere else, and the state saved has to be
	# the state this process decided on rather than wherever the score wandered.
	preview.call("lingo_hold")
	await process_frame
	if preview.get("_score") == null:
		print("child: no movie opened")
		quit(1)
		return
	_mutate(preview, "gate")
	(preview.get("_interpreter") as Object).get("globals")["gate_marker"] = marker
	var report: Dictionary = SaveFiles.write_record(preview, SCRATCH_SAVE,
		SaveState.capture(preview), null)
	print("child: saved %s%s" % [str(report["path"]),
		("  ERROR " + str(report["error"])) if str(report["error"]) != "" else ""])
	quit(0 if str(report["error"]) == "" else 1)


## Boot from `--save` and nothing else, then write out what came back.
##
## `--save` alone: no `--file`, no `--frame`, no `--label`. If the save does not
## carry enough to stand the session up on its own, this is where that shows.
func _child_reload(args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	if preview.get("_score") == null:
		print("child: no movie opened from the save")
		quit(1)
		return
	if str(preview.get("_last_save")) == "":
		print("child: --save %s was not honoured" % Args.text(args, "save", ""))
		quit(1)
		return
	# **An independent reader of the root sees the save's game too.** This is the
	# check that `--save` was resolved in `DirectorPaths.load_config` and not in
	# `preview/boot.gd`: `AudioDirector` builds its sound index from its own
	# `load_config()` call, so a root applied at the boot site alone moves the
	# movies and leaves the sounds indexed against the config -- the title runs
	# silent and nothing says why. A fresh `Paths` here asks exactly the question
	# the autoload asks. `--root` is expected to win when the gate pins one.
	var fresh := Paths.new()
	fresh.load_config()
	var pinned := Args.text(args, "root", "")
	var expected: String = ("res://games/".path_join(pinned) if pinned != ""
		else str((SaveFiles.read(Args.text(args, "save", ""))["data"] as Dictionary)
			.get("stamp", {}).get("root", "")))
	if fresh.root != expected:
		print("child: a second reader of the root sees %s, the save says %s"
			% [fresh.root, expected])
		quit(1)
		return
	var report: Dictionary = SaveFiles.write_record(preview, SCRATCH_BACK,
		SaveState.capture(preview), null)
	print("child: reloaded %s frame %d -> %s" % [
		preview.call("movie_name"), int(preview.get("_index")), str(report["path"])])
	quit(0 if str(report["error"]) == "" else 1)


# ------------------------------------------------------------------ printing

func _describe(value: Variant) -> String:
	return "%s %s" % [type_string(typeof(value)), JSON.stringify(str(value))]


func _same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(SaveState.encode(a)) == JSON.stringify(SaveState.encode(b))


## Where two records first disagree, with the surrounding text.
##
## Printing the head of each side is useless here: these are hundreds of
## characters of tagged values that are identical for the first two hundred, so a
## truncated pair reads as "wanted X, got X". The offset of the first difference
## is the only part anybody needs.
func _diff(a: String, b: String) -> String:
	if a == b:
		return ""
	var at := 0
	var stop := mini(a.length(), b.length())
	while at < stop and a.unicode_at(at) == b.unicode_at(at):
		at += 1
	var from: int = maxi(at - 30, 0)
	return "differ at %d: wanted ...%s... got ...%s..." % [
		at, a.substr(from, 90), b.substr(from, 90)]
