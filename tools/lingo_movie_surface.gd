extends SceneTree
## The movie surface a title reads *about itself*, driven from Lingo.
##
##   godot --headless --path . --script tools/lingo_movie_surface.gd
##
## Every row here was `absent` in the reference map that `docs/ENGINE_TODO.md`
## pins, and every one of them is now claimed live. `tools/lingo_surface_audit.gd`
## can say a name is bound and cannot say what the binding reached — that is the
## whole reason it distinguishes `live` from `inert`, and the distinction is a
## *reading* of the arm's body, not an observation of its effect. This file is
## the observation: each check asserts against something the movie already knows
## by another route, so a binding that answers a plausible constant fails.
##
## Which is not hypothetical. `the frameScript` answering 0 and `the frameScript`
## being unbound are the same value to a script; the check below compares it
## against the score's own decode of the same cell, so the two have to agree
## about a specific frame of a specific movie rather than about zero.
##
## Title-agnostic, like `tools/lingo_system_builtins.gd` beside it. Every check
## is against whichever movie the config boots, and nothing here names a room, a
## channel or a member — the score, the labels and the container are asked what
## they hold and the Lingo answer is compared against that.

const Harness := preload("res://tools/lib/harness.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Diagnostics := preload("res://lingo/lingo_diagnostics.gd")
## For the check that a `textSize` write reaches the paint path and not only the
## table it was stored in.
const TextArt := preload("res://scenes/preview/text_art.gd")

var _preview: Node = null
var _host = null
var _interp = null


func _init() -> void:
	var h := Harness.new()
	_preview = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(_preview)
	await process_frame
	await process_frame
	_host = _preview.get("_host")
	_interp = _preview.get("_interpreter")

	h.begin("the harness has a movie, a host and an interpreter")
	h.check("the preview booted a score", _preview.get("_score") != null)
	h.check("the preview booted a label table", _preview.get("_labels") != null)
	h.check("the Lingo host is attached", _host != null)
	h.check("the interpreter is attached", _interp != null)
	h.complete("the harness has a movie, a host and an interpreter")
	if _host == null or _interp == null or _preview.get("_score") == null:
		quit(h.finish("the movie surface a title reads about itself"))
		return

	_score_checks(h)
	_label_checks(h)
	_call_frame_checks(h)
	_item_delimiter_checks(h)
	_member_checks(h)
	_machine_checks(h)
	_memory_hint_checks(h)
	_do_checks(h)
	_trace_checks(h)

	_preview.queue_free()
	await process_frame
	quit(h.finish("the movie surface a title reads about itself"))


# ---------------------------------------------------- the score, as a movie


## The main channel of the frame the playhead is on.
##
## Each of these is compared against `director_score.gd`'s own decode of the same
## cell rather than against a literal, because the harness may not know which
## title is booted — and because a check against a literal is a check that the
## binding returns a number, which is exactly what an unbound one does.
func _score_checks(h) -> void:
	h.begin("the frame's main channel is readable as movie properties (§3)")
	var score = _preview.get("_score")
	h.check(
		"`the lastFrame` is the score's frame count (%d)" % int(score.frame_count),
		int(_value("the lastFrame")) == int(score.frame_count),
		"unbound this answered VOID, and `repeat with i = 1 to the lastFrame` "
		+ "never entered its body")
	# The playhead's own index. This used to subtract one, and so did the binding
	# it checks, so the pair agreed on the frame *before* the playhead and the
	# check passed while both were wrong -- the failure mode this file's own
	# header warns about, from the other direction.
	var record: Dictionary = score.frame(_preview.current_frame())
	var script_member: Variant = record.get("frame_script", null)
	var want_script := int(script_member) if script_member != null else 0
	h.check(
		"`the frameScript` is this frame's script member (%d)" % want_script,
		int(_value("the frameScript")) == want_script,
		"compared against the score's own decode of the cell, so a binding that "
		+ "answers 0 for every frame fails on any frame that carries one")
	h.check(
		"`the frameTempo` is this frame's tempo cell (%d)" % int(record.get("tempo", 0)),
		int(_value("the frameTempo")) == int(record.get("tempo", 0)))
	h.check(
		"`the frameTransition` is this frame's transition member (%d)"
			% int(record.get("transition_member", 0)),
		int(_value("the frameTransition")) == int(record.get("transition_member", 0)))
	var palette: Dictionary = record.get("palette", {})
	h.check(
		"`the framePalette` is this frame's palette member (%d)"
			% int(palette.get("member", 0)),
		int(_value("the framePalette")) == int(palette.get("member", 0)))
	var sounds := {1: 0, 2: 0}
	for entry in (record.get("sound_channels", []) as Array):
		var row: Dictionary = entry
		if sounds.has(int(row.get("channel", 0))):
			sounds[int(row["channel"])] = int(row.get("cast_id", 0))
	h.check(
		"`the frameSound1` and `the frameSound2` are this frame's sound cells (%d, %d)"
			% [sounds[1], sounds[2]],
		int(_value("the frameSound1")) == sounds[1]
			and int(_value("the frameSound2")) == sounds[2])
	h.complete("the frame's main channel is readable as movie properties (§3)")


## `the labelList` and `the frameLabel`, which are two different questions.
##
## The second is "does *this* frame carry a marker", not "which marker is in
## force" — that is `marker(0)`, and the two differ on every frame between two
## markers, which is nearly all of them.
func _label_checks(h) -> void:
	h.begin("the movie's markers are readable (§3)")
	var labels = _preview.get("_labels")
	var named: Array = []
	for marker in labels.markers:
		var row: Dictionary = marker
		if str(row.get("name", "")) != "":
			named.append(row)
	var list := str(_value("the labelList"))
	h.check(
		"`the labelList` has a line per named marker (%d)" % named.size(),
		list.split("\n", false).size() == named.size()
			if named.size() > 0 else list == "",
		"got %d line(s) from %d marker(s)" % [list.split("\n", false).size(), named.size()])
	if named.is_empty():
		h.complete("the movie's markers are readable (§3)")
		return
	var first: Dictionary = named[0]
	h.check(
		"the first named marker is in it (\"%s\")" % str(first["name"]),
		list.split("\n", false).has(str(first["name"])))
	# The frame the marker is on, asked of the movie by walking the playhead
	# there. `the frameLabel` is empty everywhere else, and that is the half a
	# port is likely to get wrong: answering the marker in force would make it
	# non-empty on every frame after the first one.
	_run("go to frame %d" % (int(first["frame"]) + 1))
	h.check(
		"`the frameLabel` on that marker's frame is its name",
		str(_value("the frameLabel")) == str(first["name"]),
		"got \"%s\" on frame %d" % [str(_value("the frameLabel")), int(first["frame"]) + 1])
	h.complete("the movie's markers are readable (§3)")


# ------------------------------------------------------------- the call frame


## `the result`, `the paramCount` and `param(n)` — three questions about the call
## that is running, which nothing outside the interpreter can answer.
func _call_frame_checks(h) -> void:
	h.begin("the running call is readable (§3, §1.6)")
	var script := Compiler.new().compile_source(
		"on answers\n  return 41 + 1\nend\n"
		+ "on silent\n  return\nend\n"
		+ "on counts\n  return the paramCount\nend\n"
		+ "on second a, b, c\n  return param(2)\nend\n"
		+ "on reassigns a\n  set a to \"changed\"\n  return param(1)\nend\n"
		+ "on probe\n"
		+ "  answers()\n"
		+ "  return the result\n"
		+ "end\n", "CallFrameProbe")
	h.check("the probe script compiled", not script.is_empty())
	if script.is_empty():
		h.complete("the running call is readable (§3, §1.6)")
		return
	h.check(
		"`the result` is what the last handler returned (42)",
		int(_interp.call_handler("probe", [], script)) == 42,
		"unbound this answered VOID, and a movie that calls a handler as a "
		+ "command has no other way to read what it worked out")
	# The reference stores the dropped return value only when it is not VOID, so
	# a handler that returns nothing leaves the previous answer standing. That is
	# what lets a script call three handlers and read `the result` for the one of
	# them that answered.
	_interp.call_handler("silent", [], script)
	h.check(
		"a handler that returns nothing does not clear it",
		int(_interp.call_handler("probe", [], script)) == 42,
		"`lingo-code.cpp` skips a VOID return when it stores the result")
	h.check(
		"`the paramCount` is how many arguments came in (3)",
		int(_interp.call_handler("counts", [1, 2, 3], script)) == 3)
	h.check(
		"`the paramCount` is 0 for a handler called with none",
		int(_interp.call_handler("counts", [], script)) == 0)
	h.check(
		"`param(2)` is the second argument",
		str(_interp.call_handler("second", ["a", "b", "c"], script)) == "b")
	h.check(
		"`param(n)` reads the named parameter's *current* value",
		str(_interp.call_handler("reassigns", ["original"], script)) == "changed",
		"the reference fetches the local rather than the passed list when the "
		+ "handler names its parameters, so a handler that reassigns one sees it")
	h.complete("the running call is readable (§3, §1.6)")


## `the itemDelimiter` — bound all along, and reported `absent` by the audit for
## as long as the audit read only the host. The check is on the thing that
## consumes it, because a property that round-trips and separates nothing is the
## `moveableSprite` shape.
func _item_delimiter_checks(h) -> void:
	h.begin("`the itemDelimiter` separates items (§2.6)")
	_run("set the itemDelimiter to \",\"")
	h.check(
		"the default is a comma",
		str(_value("the itemDelimiter")) == ",")
	h.check(
		"`item 2 of \"a,b,c\"` is \"b\"",
		str(_value("item 2 of \"a,b,c\"")) == "b")
	_run("set the itemDelimiter to \";\"")
	h.check(
		"a write reads back",
		str(_value("the itemDelimiter")) == ";")
	h.check(
		"and the split follows it: `item 2 of \"a;b;c\"` is \"b\"",
		str(_value("item 2 of \"a;b;c\"")) == "b",
		"got \"%s\"" % str(_value("item 2 of \"a;b;c\"")))
	h.check(
		"and a comma is no longer a separator",
		str(_value("item 1 of \"a,b\"")) == "a,b")
	_run("set the itemDelimiter to \",\"")
	h.complete("`the itemDelimiter` separates items (§2.6)")


# --------------------------------------------------------------- the members


## What a member can be asked about itself.
##
## Every check picks its subject out of the *booted movie's own cast* rather than
## naming one, so this runs against whichever title the config points at. The
## comparisons are against `director_cast.gd`'s decode of the same member, which
## is the only way to tell "answered" from "answered zero".
func _member_checks(h) -> void:
	h.begin("a member answers for itself (§5)")
	var table = _preview.get("_table")
	var cast = table.cast_for(1) if table != null else null
	h.check("the movie's own cast opened", cast != null)
	if cast == null:
		h.complete("a member answers for itself (§5)")
		return
	# The first member of each kind this movie happens to have. A title with no
	# field or no shape simply skips those rows rather than failing them.
	var of_kind: Dictionary = {}
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(int(number))
		var kind := str(m.get("type_name", ""))
		if not of_kind.has(kind):
			of_kind[kind] = int(number)
	h.check(
		"the cast holds members of %d kind(s): %s"
			% [of_kind.size(), ", ".join(PackedStringArray(of_kind.keys()))],
		not of_kind.is_empty())
	for kind in of_kind:
		var number: int = of_kind[kind]
		var m: Dictionary = cast.member(number)
		h.check(
			"`the type of member %d` is #%s" % [number, kind],
			_value("the type of member %d" % number) == StringName(str(kind)),
			"a **symbol**, not a number: `if the type of member x = #field` is how "
			+ "a script tests it and an integer compares equal to nothing")
		h.check(
			"`the rect of member %d` matches the member's own rectangle" % number,
			_rect_of(m) == _value("the rect of member %d" % number),
			"want %s, got %s" % [str(_rect_of(m)), str(_value("the rect of member %d" % number))])
		# **In the member's own coordinates, not as an offset from its top-left.**
		#
		# This asserted the offset until `preview/members.gd` gained a `regPoint`
		# writer and the read was corrected alongside it: the reference pushes
		# `_regX`/`_regY` unchanged (`castmember/bitmap.cpp:getField`) and the
		# drawing offset is a *second* quantity, `_regX - _initialRect.left`. The
		# two disagree for 97,464 of 120,869 bitmap members across the eight
		# corpora, so this check went red for member 1 and member 205 and stayed
		# green for member 28 -- the one whose rect happens to start at the
		# origin, where offset and coordinate are the same number.
		#
		# Recorded rather than quietly re-pointed, because a harness that was
		# asserting the old rule is the shape `porting-fidelity-verification`
		# warns about: it passed for as long as the engine agreed with it, and it
		# is the *engine* that was corrected here. `tools/reg_point.gd` asserts
		# the other half, the drawn rectangle, which is what a wrong reading
		# would actually cost.
		var origin: Dictionary = m.get("initial_rect", {})
		h.check(
			"`the regPoint of member %d` is in the member's own coordinates" % number,
			_value("the regPoint of member %d" % number)
				== [int(m.get("reg_offset_x", 0)) + int(origin.get("left", 0)),
					int(m.get("reg_offset_y", 0)) + int(origin.get("top", 0))],
			"want offset + rect origin, got %s"
				% str(_value("the regPoint of member %d" % number)))
		h.check(
			"`the castLibNum of member %d` is the movie's own library" % number,
			int(_value("the castLibNum of member %d" % number)) == 1)
	# A text member, where the properties that were `absent` with sites live.
	if of_kind.has("field"):
		var field_number: int = of_kind["field"]
		var m: Dictionary = cast.member(field_number)
		var styled: Dictionary = m.get("text_style", {})
		h.check(
			"`the textSize of member %d` is the member's own point size (%d)"
				% [field_number, int(styled.get("font_size", 0))],
			int(_value("the textSize of member %d" % field_number))
				== int(styled.get("font_size", 0))
				and int(styled.get("font_size", 0)) > 0,
			"§19 lists this absent at 3 sites; 0 would mean the style run did not "
			+ "decode, which is a different fault from the property not existing")
		h.check(
			"`the fontSize` is the same property by D5's spelling",
			int(_value("the fontSize of member %d" % field_number))
				== int(_value("the textSize of member %d" % field_number)))
		# **All three of this corpus's `textSize` sites are writes.** A read-only
		# binding would have closed the row in §19 and served none of them, which
		# is the half-a-property shape §19's own summary is about.
		_run("set the textSize of member %d to 24" % field_number)
		h.check(
			"a `textSize` write reads back as itself",
			int(_value("the textSize of member %d" % field_number)) == 24,
			"a write that reads back the authored size is a lie the caller cannot "
			+ "detect")
		h.check(
			"and reaches the style the renderer paints from",
			int(TextArt.style_for(_preview, {"cast_lib": 1, "cast_id": field_number},
				m)["font_size"]) == 24,
			"the override table and the paint path have to be the same one")
		h.check(
			"and the line height follows the point size",
			int(_value("the textHeight of member %d" % field_number)) > 24,
			"Director re-derives it on a `textSize` write; the authored height "
			+ "behind a doubled point size overlaps every line with the next")
		_run("set the textSize of member %d to %d"
			% [field_number, int(styled.get("font_size", 12))])
		h.check(
			"`the lineCount of member %d` counts the lines of its text" % field_number,
			int(_value("the lineCount of member %d" % field_number))
				== int(_value("the number of lines in the text of member %d" % field_number)),
			"the same rule as `count(..., #line)`, which drops a trailing empty "
			+ "line -- two implementations of that would disagree on every field "
			+ "that ends in a newline")
		h.check(
			"`the wordWrap of member %d` is a flag, not VOID" % field_number,
			[0, 1].has(int(_value("the wordWrap of member %d" % field_number))))
	# `the size of member` and `the scriptText of member`, on whatever carries them.
	var sized := 0
	var scripted := 0
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(int(number))
		if int(m.get("data_chunk_id", -1)) >= 0 and sized == 0:
			sized = int(number)
		if str(m.get("source", "")).strip_edges() != "" and scripted == 0:
			scripted = int(number)
	if sized > 0:
		h.check(
			"`the size of member %d` is its payload's byte count (%d)"
				% [sized, table.member_payload_size(1, sized)],
			int(_value("the size of member %d" % sized))
				== table.member_payload_size(1, sized)
				and table.member_payload_size(1, sized) > 0)
	if scripted > 0:
		h.check(
			"`the scriptText of member %d` is the Lingo the author typed" % scripted,
			str(_value("the scriptText of member %d" % scripted))
				== str(cast.member(scripted).get("source", "")),
			"the whole corpus is compiled from this text and no movie could ask "
			+ "for it")
	h.check(
		"`the fileName of member 1` is the container it lives in",
		str(_value("the fileName of member 1")) == table.container_path_of(1)
			and table.container_path_of(1) != "")
	# `the hilite of member` — §19's 39-site gap, and a *write* rather than a read.
	# The store is the node's and the consumer is `preview/hilite.gd:artwork`.
	var subject: int = int(of_kind.values()[0])
	h.check(
		"`the hilite of member %d` starts clear" % subject,
		int(_value("the hilite of member %d" % subject)) == 0)
	_run("set the hilite of member %d to 1" % subject)
	h.check(
		"a write reads back",
		int(_value("the hilite of member %d" % subject)) == 1,
		"`lingo_set_member_prop` knew `editable` and `text` and dropped the rest "
		+ "without reporting it")
	h.check(
		"and reaches the store the painter reads",
		bool(_preview.get("_member_hilite").get(
			_preview.call("_field_key", 1, subject), false)),
		"a member write that round-trips through a dictionary nothing paints from "
		+ "is the `moveableSprite` shape")
	_run("set the hilite of member %d to 0" % subject)
	h.check("and clears again", int(_value("the hilite of member %d" % subject)) == 0)
	# The other half of that fix: a member write with no arm is now *reported*.
	# `LingoDiagnostics.MEMBER_PROP` was declared and had never been emitted.
	var before: int = _interp.diagnostics.names_in("member_prop").size()
	_run("set the noSuchMemberProperty of member %d to 1" % subject)
	h.check(
		"a member write with no arm is reported rather than dropped",
		int(_interp.diagnostics.names_in("member_prop").size()) > before,
		"this is the one gap shape with no symptom: the statement returns, the "
		+ "read answers the authored value, and nothing says it did nothing")
	h.complete("a member answers for itself (§5)")


## A member's own rectangle in Director's [left, top, right, bottom] order,
## derived the way `preview/members.gd` derives it so the check is on the
## property and not on a second copy of the rule.
func _rect_of(m: Dictionary) -> Array:
	var box: Dictionary = m.get("initial_rect", {})
	if box.is_empty():
		return [0, 0, int(m.get("width", 0)), int(m.get("height", 0))]
	return [int(box.get("left", 0)), int(box.get("top", 0)),
		int(box.get("right", 0)), int(box.get("bottom", 0))]


# --------------------------------------------------------------- the machine


## What the player can say about itself. Each of these is a real question a 1997
## script asks before it commits to a code path, and each answer here is checked
## against the same fact read another way rather than against a literal.
func _machine_checks(h) -> void:
	h.begin("the player answers for itself (§3)")
	h.check(
		"`the movieFileSize` is the container's size on disk (%d)"
			% _preview.movie_file_size(),
		int(_value("the movieFileSize")) == _preview.movie_file_size()
			and _preview.movie_file_size() > 0,
		"0 here would mean the movie has no file, which is not a state this "
		+ "player can be in")
	var screens: Variant = _value("the desktopRectList")
	h.check(
		"`the desktopRectList` has one rect per screen (%d)"
			% DisplayServer.get_screen_count(),
		typeof(screens) == TYPE_ARRAY
			and (screens as Array).size() == DisplayServer.get_screen_count())
	h.check(
		"`the rollOver` with no argument is the channel under the mouse (%d)"
			% _preview.lingo_rollover_channel(),
		int(_value("the rollOver")) == _preview.lingo_rollover_channel(),
		"`rollOver(n)` is a different function and was the only one bound (§8.15)")
	h.check(
		"`the selection` is empty with nothing focused",
		str(_value("the selection")) == "" if _preview.lingo_focus_channel() == 0 else true)
	h.check(
		"`the quickTimePresent` is false, and honestly so",
		int(_value("the quickTimePresent")) == 0,
		"there is no digital video in this port; a movie that guards on this "
		+ "takes the branch that works")
	# **A list, and no longer an empty one.** The check this replaces asserted
	# emptiness, which was right while no Xtra was implemented and is now a claim
	# that FileIO is not loaded. What has to hold either way is the *shape*: a
	# movie scanning `the xtras` for one must be able to loop over it, and every
	# entry has to be an object it can send `new` to rather than a bare name --
	# §7.3's own warning, and the reason the registry holds records.
	var xtras: Variant = _value("the xtras")
	var every_entry_is_an_xtra := typeof(xtras) == TYPE_ARRAY
	for entry in (xtras as Array) if typeof(xtras) == TYPE_ARRAY else []:
		if not (entry is Object) or not (entry as Object).has_method("make_xtra_instance"):
			every_entry_is_an_xtra = false
	h.check(
		"`the xtras` is a list, and every entry is an Xtra `new` can be applied to",
		every_entry_is_an_xtra and not (xtras as Array).is_empty(),
		"holds %s; FileIO is the one Xtra this player implements" % JSON.stringify(xtras))
	h.check(
		"`version()` and `the productVersion` agree (\"6.0\")",
		str(_value("version()")) == "6.0" and str(_value("the productVersion")) == "6.0")
	var volumes: Variant = _value("getVolumes()")
	h.check(
		"`getVolumes()` names at least one volume",
		typeof(volumes) == TYPE_ARRAY and not (volumes as Array).is_empty(),
		"Piposh 1 scans for its CD by drive letter; this is the other spelling "
		+ "of the same question and it has to have an answer")
	h.check(
		"`externalParamCount()` is 0 for a projector",
		int(_value("externalParamCount()")) == 0,
		"a function and not a `the` property, which is how the reference has it")
	h.check(
		"and `externalParamName(1)` past the end is VOID, not \"\"",
		_value("externalParamName(1)") == null,
		"a movie loops until this answers nothing; \"\" is a value and the loop "
		+ "would not end")
	# The same fault, in the binding that was already shipped. `getPref` answers
	# VOID for a preference that has never been written, and the interpreter's
	# host contract spells "no such builtin" as a null return -- so a VOID answer
	# came back as 0 *and* filed the builtin as missing. Every "first run?" test
	# in Lingo is `if getPref("x") = VOID then`, and 0 is not VOID.
	var unwritten := "harnessprobe" + str(Time.get_ticks_usec())
	h.check(
		"`getPref` for a name never written is VOID, not 0",
		_value("getPref(\"%s\")" % unwritten) == null,
		"got %s" % str(_value("getPref(\"%s\")" % unwritten)))
	h.complete("the player answers for itself (§3)")


## The memory hints, which are not no-ops.
##
## They were recorded as deliberate no-ops on the grounds that this port loads on
## demand — true — and every one of them reports what it loaded through `the
## result`, which a movie can observe. That is the test the `noop` channel is
## supposed to apply and it was never applied to these.
func _memory_hint_checks(h) -> void:
	h.begin("the preload hints report through `the result` (§1.11)")
	var script := Compiler.new().compile_source(
		"on bare\n  preLoad\n  return the result\nend\n"
		+ "on ranged\n  preLoad 2, 7\n  return the result\nend\n"
		+ "on cast\n  preLoadCast 3\n  return the result\nend\n",
		"PreloadProbe")
	h.check("the probe script compiled", not script.is_empty())
	if script.is_empty():
		h.complete("the preload hints report through `the result` (§1.11)")
		return
	var last := int(_preview.get("_score").frame_count)
	h.check(
		"`preLoad` with no argument answers the last frame (%d)" % last,
		int(_interp.call_handler("bare", [], script)) == last,
		"the reference answers the frame count: it preloaded all of them")
	h.check(
		"`preLoad 2, 7` answers the last frame asked for (7)",
		int(_interp.call_handler("ranged", [], script)) == 7)
	h.check(
		"`preLoadCast 3` answers 3",
		int(_interp.call_handler("cast", [], script)) == 3)
	h.begin("`clearGlobals` empties the globals (§1.11)")
	_run("set the itemDelimiter to \",\"")
	_interp.globals["harnessprobe"] = 1
	_run("clearGlobals")
	h.check(
		"a global set before it is gone after it",
		not _interp.globals.has("harnessprobe"),
		"it was in the host's IGNORED list, so a movie that reset itself did not")
	h.complete("`clearGlobals` empties the globals (§1.11)")
	h.complete("the preload hints report through `the result` (§1.11)")


## `do`, `abort` and `symbol` — three commands the port answered VOID for.
##
## `do` is checked on the thing that makes it `do` rather than `value`: it runs in
## the **caller's** frame, so a `do` that sets a local has to be visible to the
## next statement of the handler that wrote it. A version that built a fresh scope
## would pass every other test one could write for it.
func _do_checks(h) -> void:
	h.begin("`do`, `abort` and `symbol` (§1.11, §1.9)")
	var script := Compiler.new().compile_source(
		"on locals\n"
		+ "  set x to 1\n"
		+ "  do \"set x to 7\"\n"
		+ "  return x\n"
		+ "end\n"
		+ "on globalside\n"
		+ "  global harnessdone\n"
		+ "  do \"set harnessdone to 9\"\n"
		+ "  return harnessdone\n"
		+ "end\n"
		+ "on broken\n"
		+ "  do \"repeat repeat repeat\"\n"
		+ "  return 5\n"
		+ "end\n"
		+ "on aborts\n"
		+ "  set marker to 1\n"
		+ "  abort\n"
		+ "  set marker to 2\n"
		+ "  return marker\n"
		+ "end\n"
		+ "on callsaborts\n"
		+ "  aborts()\n"
		+ "  return 3\n"
		+ "end\n", "DoProbe")
	h.check("the probe script compiled", not script.is_empty())
	if script.is_empty():
		h.complete("`do`, `abort` and `symbol` (§1.11, §1.9)")
		return
	h.check(
		"`do` runs in the caller's frame, so it can write the caller's local",
		int(_interp.call_handler("locals", [], script)) == 7,
		"a fresh scope would answer 1 and look like it worked from every other "
		+ "angle; this is the whole of what makes `do` different from `value`")
	h.check(
		"and reaches a global the caller declared",
		int(_interp.call_handler("globalside", [], script)) == 9)
	h.check(
		"a `do` string that will not compile is reported, and the handler carries on",
		int(_interp.call_handler("broken", [], script)) == 5,
		"Director reports it and continues; a movie that computes its Lingo must "
		+ "not be stopped by one bad string")
	h.check(
		"`abort` leaves the handler that ran it",
		_interp.call_handler("aborts", [], script) == null,
		"`exit` returns from one handler; `abort` stops the dispatch. It was in "
		+ "the host's IGNORED list, which made it `nothing` under another name")
	_interp.reset_steps()
	h.check(
		"and the handler that called it",
		_interp.call_handler("callsaborts", [], script) == null,
		"a chain that carried on would run the statements the movie was escaping")
	_interp.reset_steps()
	h.check(
		"`symbol(\"mouseUp\")` is #mouseUp",
		_value("symbol(\"mouseUp\")") == &"mouseUp")
	h.check(
		"and round-trips through `string`",
		str(_value("string(symbol(\"mouseUp\"))")) == "mouseUp")
	h.complete("`do`, `abort` and `symbol` (§1.11, §1.9)")


## `the trace` — Director's statement trace, and the switch this port has spent
## its whole life re-implementing with `print` one session at a time.
func _trace_checks(h) -> void:
	h.begin("`the trace` reaches the interpreter (§3)")
	var was: bool = Diagnostics.trace
	Diagnostics.trace = false
	_run("set the trace to 1")
	h.check(
		"a write reaches the interpreter's own switch",
		Diagnostics.trace,
		"the consumer is `lingo_interpreter.gd:_exec`; a host that stored this "
		+ "and nothing read it would be the `moveableSprite` shape one level up")
	h.check("and reads back", int(_value("the trace")) == 1)
	_run("set the trace to 0")
	h.check("and off again", not Diagnostics.trace and int(_value("the trace")) == 0)
	Diagnostics.trace = was
	h.complete("`the trace` reaches the interpreter (§3)")


# ------------------------------------------------------------------ driving


func _run(source: String) -> void:
	var script := Compiler.new().compile_source(
		"on probe\n  %s\nend\n" % source, "MovieSurfaceProbe")
	if script.is_empty():
		push_warning("lingo_movie_surface: `%s` did not compile" % source)
		return
	_interp.call_handler("probe", [], script)


func _value(expression: String) -> Variant:
	var script := Compiler.new().compile_source(
		"on probe\n  return %s\nend\n" % expression, "MovieSurfaceProbe")
	if script.is_empty():
		return "<did not compile>"
	return _interp.call_handler("probe", [], script)
