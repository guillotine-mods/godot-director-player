extends SceneTree
## Editable fields: can the player actually type into one, and does the caret go
## where they pointed? §8.4 and §7.7.
##
##   godot --path . --script tools/editable_text.gd -- --file PIP2DATA/SAVELOAD.dir
##   godot --headless --script tools/editable_text.gd -- --file PIP2DATA/SAVELOAD.dir
##
## **Run it windowed.** The headless half asserts the rules -- editability,
## focus arbitration, the selection round-trip, insertion and deletion -- by
## driving the engine's own entry points directly, and that proves the rules and
## nothing about the wiring. Headless Godot has no keyboard focus and never
## paints, so a run that stops there has not shown that pressing a key types a
## character or that a caret reaches the screen. The windowed half feeds real
## `InputEventKey`s through `Input.parse_input_event` -- the same path a player's
## keyboard takes, through `_input` and `preview/input_router.gd` -- and reads
## the framebuffer back over the field's own rectangle. Both halves failing
## differently is the point: a rule can be right while nothing reaches it.
##
## **Why this matters more than the corpus count suggests.** Exactly one member
## in Piposh 2 carries the authored editable flag, and it is `save1` in
## `SAVELOAD.dir` -- the box a save slot is named in. Zero of the corpus's
## 816,318 sprite records set the score's own editable bit (nor any of Piposh 1's
## 1,886,362, nor Rating's 847,431), so **every editable field in all three
## titles is editable because its member says so**, which is the half this port
## did not decode until now. The five `member("saveN").editable = <n>` writes in
## `SAVELOAD` choose which of the eight slots is typeable, and
## `BehaviorScript 22` then does `put field("save" & x, 1) into item x of
## SaveNames`. Without any of this, a save can never be more than a load.
##
## Title-agnostic. It finds its own subject: the first frame carrying a field
## sprite whose member is editable, and failing that it *arms* one through the
## same `member(...).editable = 1` a script would use. Arming rather than
## skipping is deliberate and follows `tools/mouse_events.gd`'s reasoning about
## `moveableSprite` -- the property is Director's own way of making a field
## typeable, so a corpus with no authored one still exercises the whole path.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Text := preload("res://director/director_text.gd")
const TextFocus := preload("res://scenes/preview/text_focus.gd")


## Stage point -> the window pixel a real event would carry. The same three-
## transform composition `tools/touch_input.gd` and `tools/sprite_drag.gd` use;
## getting it wrong puts the event somewhere else and reads as "typing does not
## work".
func _to_window(preview: Node, stage: Vector2) -> Vector2:
	var to_screen: Transform2D = (
		preview.get_viewport().get_screen_transform()
		* preview.get_global_transform_with_canvas()
	)
	return to_screen * stage


## One real keystroke, queued the way the OS queues one.
func _press(key: Key, unicode: int = 0, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.unicode = unicode
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)


func _drawn(preview: Node, channel: int) -> Dictionary:
	return (preview.get("_text_drawn") as Dictionary).get(channel, {})


## Every field sprite on a frame, with its member, keyed by channel.
func _fields(preview: Node, index: int) -> Dictionary:
	var score = preview.get("_score")
	var table = preview.get("_table")
	var out := {}
	for raw in score.frame(index).get("sprites", []):
		var sprite: Dictionary = raw
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		if not member.is_empty() and int(member.get("type", 0)) == Ink.TYPE_FIELD:
			out[int(sprite["channel"])] = {"sprite": sprite, "member": member}
	return out


## The frame this movie is going to be tested on, and how it was chosen.
##
## First preference is a frame carrying a member with the **authored** editable
## bit, because that is the real thing and it exists in this corpus. Second is
## the frame with the most field sprites, which is then armed by script.
func _subject(preview: Node) -> Dictionary:
	var score = preview.get("_score")
	var best_count := 0
	var best := -1
	for i in score.frame_count:
		var fields := _fields(preview, i)
		if fields.is_empty():
			continue
		for channel in fields:
			if bool((fields[channel]["member"] as Dictionary).get("editable", false)):
				return {"frame": i, "fields": fields, "authored": true}
		if fields.size() > best_count:
			best_count = fields.size()
			best = i
	if best < 0:
		return {}
	return {"frame": best, "fields": _fields(preview, best), "authored": false}


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		await process_frame
	# Paused throughout. The playhead is set directly because this asserts the
	# widget, and a room that holds on `go to the frame` would never step to the
	# frame the editable field is on -- the same reason
	# `tools/text_and_shapes.gd` pauses.
	preview.set("_paused", true)

	var score = preview.get("_score")
	var host = preview.get("_host")
	if score == null:
		print("no score loaded")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))

	var subject := _subject(preview)
	if subject.is_empty():
		print("%s has no field sprite anywhere; nothing to type into" % movie)
		quit(h.finish("editable text in %s" % movie))
		return
	var frame := int(subject["frame"])
	var fields: Dictionary = subject["fields"]
	preview.set("_index", frame)
	preview.get("_overrides").clear()
	print("%s: frame %d, %d field sprite(s), authored editable member: %s" % [
		movie, frame, fields.size(), str(subject["authored"])])

	var channels: Array = fields.keys()
	channels.sort()
	for channel in channels:
		var member: Dictionary = fields[channel]["member"]
		print("   ch%-4d %-14s %s%s" % [int(channel), str(member.get("name", "")),
			"EDITABLE " if bool(member.get("editable", false)) else "",
			"noWrap " if not bool(member.get("word_wrap", true)) else ""])

	# ------------------------------------------------- effective editability
	# §7.7: `sprite editable OR member editable`. Both directions, because a rule
	# that answered yes to everything would satisfy the first check and be
	# useless -- and because in this corpus the sprite half is *never* set, so
	# only the synthetic case can prove that half is read at all.
	h.begin("§7.7 effective editability is the sprite's flag OR the member's")
	var plain_channel := int(channels[0])
	var plain: Dictionary = (fields[plain_channel]["sprite"] as Dictionary).duplicate()
	var plain_member: Dictionary = (fields[plain_channel]["member"] as Dictionary).duplicate()
	plain_member["editable"] = false
	plain["editable"] = false
	h.check("neither flag set: not editable",
		not TextFocus.editable(preview, plain, plain_member))
	var by_sprite: Dictionary = plain.duplicate()
	by_sprite["editable"] = true
	h.check("the score's own bit alone makes it editable",
		TextFocus.editable(preview, by_sprite, plain_member))
	var by_member: Dictionary = plain_member.duplicate()
	by_member["editable"] = true
	h.check("the member's own bit alone makes it editable",
		TextFocus.editable(preview, plain, by_member))
	# The negative that keeps the rule from spreading: editability is a property
	# of text, and a bitmap sprite carrying the score bit is not a text widget.
	var not_text: Dictionary = plain_member.duplicate()
	not_text["type"] = Ink.TYPE_BITMAP
	h.check("a non-field member is never editable, whatever the sprite says",
		not TextFocus.editable(preview, by_sprite, not_text))
	h.complete("§7.7 effective editability is the sprite's flag OR the member's")

	# ------------------------------------------------------- the write lands
	# `member("x").editable = 1` went through `set_member_prop`, which was a bare
	# `pass` -- accepted and discarded. That is the write `SAVELOAD` uses five
	# times to choose the typeable slot, so it is checked through the *host*, the
	# way the interpreter reaches it, and not through the node.
	h.begin("`member(x).editable` is written and read back through the host")
	var subject_channel := int(channels[0])
	for channel in channels:
		if bool((fields[channel]["member"] as Dictionary).get("editable", false)):
			subject_channel = int(channel)
			break
	var subject_member: Dictionary = fields[subject_channel]["member"]
	var member_name := str(subject_member.get("name", ""))
	var member_ref: Variant = member_name if member_name != "" \
		else int(subject_member.get("cast_id", 0))
	host.call("set_member_prop", member_ref, "", "editable", 0)
	h.check("turning it off reads back off",
		int(host.call("get_member_prop", member_ref, "", "editable")) == 0,
		"%s -> %s" % [str(member_ref),
			str(host.call("get_member_prop", member_ref, "", "editable"))])
	host.call("set_member_prop", member_ref, "", "editable", 1)
	h.check("turning it on reads back on",
		int(host.call("get_member_prop", member_ref, "", "editable")) == 1)
	h.check("and the frame now has an editable sprite on it",
		TextFocus.editable_sprites(preview).size() > 0,
		"%d" % TextFocus.editable_sprites(preview).size())
	# The other half of the same `pass`. `set the text of member` is a different
	# *spelling* of a path that already worked -- `put x into field` goes through
	# `set_field` -- so it was an unreported no-op that no room could notice: 0
	# sites in this corpus use it. It has to land on the same store the renderer
	# reads, or the two spellings disagree about what a field holds.
	var sentinel := "8265130497"
	host.call("set_member_prop", member_ref, "", "text", sentinel)
	h.check("`set the text of member` reaches the same store the renderer reads",
		str(host.call("get_member_prop", member_ref, "", "text")) == sentinel,
		str(host.call("get_member_prop", member_ref, "", "text")))
	h.check("and `field(name)` sees it too, so the two spellings agree",
		member_name == ""
		or str(host.call("get_field", member_name, "")) == sentinel,
		str(host.call("get_field", member_name, "")))
	h.complete("`member(x).editable` is written and read back through the host")

	# ------------------------------------------------------ focus arbitration
	# §7.7 / §8.4: the *first* editable sprite in channel order claims the widget,
	# and keeps it while its channel still shows the same cast member.
	h.begin("§8.4 the first editable sprite claims focus and then keeps it")
	# Every field armed, so "first" has something to choose between. Where the
	# movie authored only one this is the only way to exercise the ordering at
	# all, and it is the same write a script would make.
	for channel in channels:
		host.call("set_member_prop",
			str((fields[channel]["member"] as Dictionary).get("name", "")) \
				if str((fields[channel]["member"] as Dictionary).get("name", "")) != "" \
				else int((fields[channel]["member"] as Dictionary).get("cast_id", 0)),
			"", "editable", 1)
	preview.set("_focus_channel", 0)
	preview.set("_focus_member", 0)
	var first := int(preview.call("lingo_focus_channel"))
	h.check("focus went to the lowest editable channel, not the highest",
		first == int(channels[0]), "focus ch%d, lowest ch%d" % [first, int(channels[0])])
	# Arbitrating again must not move it. Without the "unless one already holds
	# it" clause every paint would drag focus back to the lowest channel and the
	# player could never type into the second box.
	h.check("a second arbitration leaves it where it is",
		int(preview.call("lingo_focus_channel")) == first)
	# And a script that turns the holder off hands focus on, which is exactly what
	# `SAVELOAD`'s slot buttons do inside one `mouseUp`.
	var moved := first
	if channels.size() > 1:
		var holder: Dictionary = fields[first]["member"]
		host.call("set_member_prop",
			str(holder.get("name", "")) if str(holder.get("name", "")) != "" \
				else int(holder.get("cast_id", 0)), "", "editable", 0)
		moved = int(preview.call("lingo_focus_channel"))
		h.check("turning the holder off moves focus to the next editable field",
			moved == int(channels[1]),
			"focus ch%d, wanted ch%d" % [moved, int(channels[1])])
		host.call("set_member_prop",
			str(holder.get("name", "")) if str(holder.get("name", "")) != "" \
				else int(holder.get("cast_id", 0)), "", "editable", 1)
		# Back on, and focus stays where it moved to: the clause is "claims it
		# only if no editable widget already holds it", not "the lowest wins".
		h.check("and putting it back does not steal focus back",
			int(preview.call("lingo_focus_channel")) == moved)
	# Nothing editable anywhere means nobody has focus, and §8.3 then routes a
	# keypress to the frame with channel 0.
	for channel in channels:
		var m: Dictionary = fields[channel]["member"]
		host.call("set_member_prop",
			str(m.get("name", "")) if str(m.get("name", "")) != "" \
				else int(m.get("cast_id", 0)), "", "editable", 0)
	h.check("with nothing editable, no sprite owns the widget",
		int(preview.call("lingo_focus_channel")) == 0,
		"focus ch%d" % int(preview.call("lingo_focus_channel")))
	h.complete("§8.4 the first editable sprite claims focus and then keeps it")

	# ---------------------------------------------------- typing and the caret
	var typed_member: Dictionary = fields[subject_channel]["member"]
	var typed_ref: Variant = str(typed_member.get("name", "")) \
		if str(typed_member.get("name", "")) != "" else int(typed_member.get("cast_id", 0))
	host.call("set_member_prop", typed_ref, "", "editable", 1)
	preview.set("_focus_channel", 0)
	preview.set("_focus_member", 0)
	preview.call("lingo_focus_channel")

	h.begin("§8.4 typing, deleting and the selection round-trip")
	var start_text := str(preview.call("lingo_field", str(typed_member.get("name", "")), ""))
	# A caret at the end of what is already there, not at 0: every field arrives
	# holding a value, and a caret at the start would put the first character
	# typed in front of it.
	h.check("the caret starts at the end of the existing text",
		int(host.call("get_system_prop", "selstart")) == start_text.length(),
		"selStart %s, text %d chars" % [
			str(host.call("get_system_prop", "selstart")), start_text.length()])
	# Cleared through the same call a script would use, so the typing below starts
	# from a known string rather than from whatever the movie authored.
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "")
	preview.call("lingo_set_sel", "selstart", 0)
	preview.call("lingo_set_sel", "selend", 0)
	for c in "Piposh".to_utf8_buffer():
		TextFocus.key(preview, _made_key(KEY_A, int(c)))
	var after_typing := str(preview.call("lingo_field", str(typed_member.get("name", "")), ""))
	h.check("six keystrokes put six characters in the field",
		after_typing == "Piposh", "'%s'" % after_typing)
	h.check("and the caret is behind the last of them",
		int(host.call("get_system_prop", "selstart")) == 6,
		"selStart %s" % str(host.call("get_system_prop", "selstart")))
	# The whole point of the exercise: what the player typed is what
	# `field("save1")` answers, because a save button reads the field back.
	h.check("`field(name)` reads back what was typed, not the authored text",
		str(host.call("get_field", str(typed_member.get("name", "")), "")) == "Piposh")

	TextFocus.key(preview, _made_key(KEY_BACKSPACE))
	h.check("backspace removes the character before the caret",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")) == "Pipos",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")))
	TextFocus.key(preview, _made_key(KEY_LEFT))
	TextFocus.key(preview, _made_key(KEY_LEFT))
	h.check("two left arrows move the caret two characters back",
		int(host.call("get_system_prop", "selstart")) == 3,
		"selStart %s" % str(host.call("get_system_prop", "selstart")))
	TextFocus.key(preview, _made_key(KEY_A, 88))
	h.check("a character is inserted at the caret, not appended",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")) == "PipXos",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")))
	# A range, deleted as a range. `the selStart`/`selEnd` are movie properties
	# (§8.4) and this is the round-trip: set them from Lingo, then let the widget
	# act on what they say.
	host.call("set_system_prop", "selstart", 0)
	host.call("set_system_prop", "selend", 3)
	h.check("the selection reads back the range that was set",
		int(host.call("get_system_prop", "selstart")) == 0
		and int(host.call("get_system_prop", "selend")) == 3,
		"%s..%s" % [str(host.call("get_system_prop", "selstart")),
			str(host.call("get_system_prop", "selend"))])
	TextFocus.key(preview, _made_key(KEY_BACKSPACE))
	h.check("backspace over a selection deletes the whole range",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")) == "Xos",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")))
	# Out of range on purpose: a script may set a selection longer than the text,
	# and Director answers what it can honour rather than deleting what is not
	# there.
	host.call("set_system_prop", "selend", 9999)
	h.check("a selection past the end is clamped to the text",
		int(host.call("get_system_prop", "selend")) == 3,
		"selEnd %s" % str(host.call("get_system_prop", "selend")))
	h.complete("§8.4 typing, deleting and the selection round-trip")

	# ------------------------------------------------------- a click positions
	# §8.4's "what a click inside an editable field does to the caret". Driven
	# through `route_press`, the entry point a real button reaches, and asserted
	# against the *laid-out* text rather than against a character count -- the
	# whole question is whether the pixel the player pointed at maps to the right
	# character.
	h.begin("a click inside an editable field puts the caret where it landed")
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "abcdefgh")
	preview.call("queue_redraw")
	await process_frame
	var rect: Rect2 = preview.call("_stage_rect", fields[subject_channel]["sprite"])
	var style: Dictionary = Text.style_of(typed_member)
	# The exact x of the boundary before the 4th character, so the assertion is
	# about the mapping and not about a lucky rounding.
	var want := 4
	var boundary: Rect2 = Text.caret_rect(rect, "abcdefgh", style, want)
	preview.call("route_press", Vector2(boundary.position.x, rect.get_center().y))
	preview.call("route_release", Vector2(boundary.position.x, rect.get_center().y))
	h.check("the click claimed focus for the field it landed in",
		int(preview.get("_focus_channel")) == subject_channel,
		"focus ch%d, wanted ch%d" % [int(preview.get("_focus_channel")), subject_channel])
	h.check("the caret went to the character boundary that was clicked",
		int(host.call("get_system_prop", "selstart")) == want,
		"selStart %s, wanted %d" % [str(host.call("get_system_prop", "selstart")), want])
	# A click outside every editable field must not move the caret, or clicking
	# anything else on the screen would silently reposition the insertion point.
	preview.call("route_press", Vector2(2, 2))
	preview.call("route_release", Vector2(2, 2))
	h.check("a click outside them leaves the caret alone",
		int(host.call("get_system_prop", "selstart")) == want,
		"selStart %s" % str(host.call("get_system_prop", "selstart")))
	h.complete("a click inside an editable field puts the caret where it landed")

	# ------------------------------------------------------ dragging a selection
	# The other half of pointing at text, and the half that was missing: the
	# caret could be *placed* with the mouse and nothing could be *selected* with
	# it. Asserted against laid-out boundaries for the same reason the click is
	# -- the question is whether the pixels the player swept map to the right
	# range of characters.
	h.begin("dragging across an editable field selects a range")
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "abcdefgh")
	preview.call("queue_redraw")
	await process_frame
	var from := 2
	var to := 6
	var y: float = rect.get_center().y
	var from_x: float = Text.caret_rect(rect, "abcdefgh", style, from).position.x
	var to_x: float = Text.caret_rect(rect, "abcdefgh", style, to).position.x
	preview.call("route_press", Vector2(from_x, y))
	h.check("the press collapsed the selection at the character it landed on",
		int(host.call("get_system_prop", "selstart")) == from
		and int(host.call("get_system_prop", "selend")) == from,
		"%s..%s, wanted %d" % [str(host.call("get_system_prop", "selstart")),
			str(host.call("get_system_prop", "selend")), from])
	# Halfway first: a drag reports continuously, and a selection that only
	# appeared on the release would be a click that guessed.
	TextFocus.drag(preview, Vector2((from_x + to_x) * 0.5, y))
	var midway := int(host.call("get_system_prop", "selend"))
	h.check("the selection follows the pointer while the button is down",
		midway > from and midway < to, "selEnd %d, between %d and %d" % [midway, from, to])
	TextFocus.drag(preview, Vector2(to_x, y))
	h.check("and lands on the boundary the drag ended at",
		int(host.call("get_system_prop", "selstart")) == from
		and int(host.call("get_system_prop", "selend")) == to,
		"%s..%s, wanted %d..%d" % [str(host.call("get_system_prop", "selstart")),
			str(host.call("get_system_prop", "selend")), from, to])
	# The anchor stays put, so the range is what a subsequent shift-arrow extends
	# and what a backspace deletes.
	TextFocus.key(preview, _made_key(KEY_BACKSPACE))
	h.check("backspace deletes exactly the dragged range",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")) == "abgh",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")))
	# The button comes up and the selection stops following. Without this the
	# next mouse movement anywhere on the stage would keep re-selecting.
	preview.call("route_release", Vector2(to_x, y))
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "abcdefgh")
	preview.call("lingo_set_sel", "selstart", 1)
	preview.call("lingo_set_sel", "selend", 1)
	TextFocus.drag(preview, Vector2(to_x, y))
	h.check("after the release the pointer no longer moves the selection",
		int(host.call("get_system_prop", "selend")) == 1,
		"selEnd %s" % str(host.call("get_system_prop", "selend")))
	h.complete("dragging across an editable field selects a range")

	# --------------------------------------------------- what the paint records
	# Headless Godot builds the draw list and discards it, so `_text_drawn` is
	# the only place a caret can be observed without a framebuffer -- and a caret
	# is one pixel wide, which is not something to assert against a screenshot
	# even when there is one.
	h.begin("the paint records the caret and the selection it drew")
	preview.call("queue_redraw")
	await process_frame
	var record := _drawn(preview, subject_channel)
	h.check("the focused field reached the paint", not record.is_empty(),
		"ch%d" % subject_channel)
	h.check("it is marked editable and focused",
		bool(record.get("editable", false)) and bool(record.get("focused", false)),
		"editable=%s focused=%s" % [str(record.get("editable", null)),
			str(record.get("focused", null))])
	var caret: Rect2 = record.get("caret", Rect2())
	h.check("the caret is inside the field's own box",
		rect.has_point(caret.position + Vector2(0, 1)),
		"caret %s in box %s" % [str(caret), str(rect)])
	var unfocused := 0
	for channel in channels:
		if int(channel) == subject_channel:
			continue
		var other := _drawn(preview, int(channel))
		if not other.is_empty() and not bool(other.get("focused", true)):
			unfocused += 1
	h.check("no other field claims to be focused", unfocused == channels.size() - 1,
		"%d of %d" % [unfocused, channels.size() - 1])
	h.complete("the paint records the caret and the selection it drew")

	# ------------------------------------------------------------ real keyboard
	if DisplayServer.get_name() == "headless":
		print("")
		print("windowed stage skipped: run without --headless to drive a real keyboard")
		print("  a headless pass proves the rules and nothing about the wiring:")
		print("  no keyboard focus, and the draw list is discarded unpainted.")
		quit(h.finish("editable text, focus, caret and selection in %s" % movie))
		return

	h.begin("a real keypress reaches the widget through `_input`")
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "")
	preview.call("lingo_set_sel", "selstart", 0)
	preview.call("lingo_set_sel", "selend", 0)
	preview.call("queue_redraw")
	await process_frame
	# The pointer is parked off the field first: §8.3's whole claim is that a key
	# goes to the *focused* sprite and not to the one under the mouse, and a
	# cursor left over the field would make the two indistinguishable.
	Input.warp_mouse(_to_window(preview, Vector2(4, 4)))
	for i in 3:
		await process_frame
	for c in "Hi".to_utf8_buffer():
		_press(KEY_A, int(c))
		for i in 2:
			await process_frame
	var by_keyboard := str(preview.call("lingo_field", str(typed_member.get("name", "")), ""))
	h.check("two real keystrokes reached the field",
		by_keyboard == "Hi", "'%s'" % by_keyboard)
	h.check("with the pointer nowhere near it, so the route was focus and not hover",
		int(preview.get("_rollover_channel")) != subject_channel,
		"rollover ch%d" % int(preview.get("_rollover_channel")))
	_press(KEY_BACKSPACE)
	for i in 2:
		await process_frame
	h.check("and a real backspace deleted one of them",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")) == "H",
		str(preview.call("lingo_field", str(typed_member.get("name", "")), "")))
	h.complete("a real keypress reaches the widget through `_input`")

	# ------------------------------------------------- a real drag, through `_input`
	# The rules half above proves `TextFocus.drag` selects the right range. This
	# proves anything ever calls it: the motion has to survive `_input`,
	# `make_input_local` and the router, and it must not be eaten by §7.6's
	# sprite drag on the way. Same trap as the keyboard half -- a rule can be
	# right while nothing reaches it.
	h.begin("a real mouse drag reaches the widget through `_input`")
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "abcdefgh")
	preview.call("lingo_set_sel", "selstart", 0)
	preview.call("lingo_set_sel", "selend", 0)
	preview.call("queue_redraw")
	await process_frame
	var real_from: Vector2 = _to_window(preview,
		Vector2(Text.caret_rect(rect, "abcdefgh", style, 2).position.x, rect.get_center().y))
	var real_to: Vector2 = _to_window(preview,
		Vector2(Text.caret_rect(rect, "abcdefgh", style, 6).position.x, rect.get_center().y))
	Input.warp_mouse(real_from)
	for i in 2:
		await process_frame
	_mouse_button(real_from, true)
	for i in 2:
		await process_frame
	Input.warp_mouse(real_to)
	_mouse_motion(real_to)
	for i in 2:
		await process_frame
	var dragged_start := int(host.call("get_system_prop", "selstart"))
	var dragged_end := int(host.call("get_system_prop", "selend"))
	_mouse_button(real_to, false)
	for i in 2:
		await process_frame
	h.check("a real drag selected a range rather than only moving the caret",
		dragged_end != dragged_start,
		"%d..%d" % [dragged_start, dragged_end])
	h.check("and the range is the one the pointer swept",
		dragged_start == 2 and dragged_end == 6,
		"%d..%d, wanted 2..6" % [dragged_start, dragged_end])
	h.complete("a real mouse drag reaches the widget through `_input`")

	# ------------------------------------------------------------- real pixels
	# The other half of the same trap. Everything above can pass while nothing is
	# on screen: the text is drawn straight into the canvas, so there is no
	# texture to inspect and no cache to read back, and "the field says H" is not
	# "the player can see an H".
	h.begin("the typed text and the caret reach the framebuffer")
	preview.call("lingo_set_field", str(typed_member.get("name", "")), "", "")
	preview.call("queue_redraw")
	for i in 4:
		await process_frame
	var window_rect := Rect2i(
		Vector2i(_to_window(preview, rect.position)),
		Vector2i(_to_window(preview, rect.position + rect.size)
			- _to_window(preview, rect.position)))
	var blank := _sample(window_rect)
	h.check("the field's rectangle is on screen to sample",
		blank.size() > 0, str(window_rect))
	for c in "WXYZ".to_utf8_buffer():
		_press(KEY_A, int(c))
		for i in 2:
			await process_frame
	for i in 4:
		await process_frame
	var painted := _sample(window_rect)
	h.check("the pixels over the field changed once something was typed into it",
		painted.size() > 0 and painted != blank,
		"%d bytes, %s" % [painted.size(), "identical" if painted == blank else "changed"])
	h.complete("the typed text and the caret reach the framebuffer")

	print("")
	quit(h.finish("editable text, focus, caret and selection in %s" % movie))


## A real mouse button, queued the way the OS queues one. Window coordinates,
## because that is what an OS event carries and what `make_input_local` expects.
func _mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


## A real pointer movement with the left button held, which is what a drag is.
## The button mask matters: without it this is a hover, and a hover must not
## extend a selection.
func _mouse_motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)


## A key event for the direct-drive half. Not fed through `Input`: those checks
## are about the widget's rules, and going through the OS queue would make every
## one of them also a check of the routing -- which the windowed half asserts on
## its own and would then be asserting twice.
func _made_key(key: Key, unicode: int = 0, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.unicode = unicode
	event.shift_pressed = shift
	event.pressed = true
	return event


func _sample(rect: Rect2i) -> PackedByteArray:
	var image := root.get_texture().get_image()
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return PackedByteArray()
	return image.get_region(clipped).get_data()
