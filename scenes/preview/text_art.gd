extends RefCounted
## Field members: what they hold, where a write to one lands, and how they paint.
##
## Fields are the half of the cast that has no artwork. `_texture_for` answers
## null for every member that is not a bitmap, so before any of this existed a
## field drew nothing at all -- 11,525 sprite records across this corpus, and
## with them the whole HUD, the score, the inventory, the process list -- while
## the Lingo that maintains them worked perfectly and had nowhere to show it.
##
## The subtle part is not the drawing, it is `key_for`. A field override is
## keyed by the cast's **file**, never by its library number, and the comment
## there explains why that distinction is not pedantry.
##
## `paint` also draws the caret and the selection for whichever field holds the
## active widget (§8.4). Which field that is, and where the caret sits, is
## `scenes/preview/text_focus.gd`'s decision -- this only draws it, and records
## it into the paint log so a headless harness can assert an insertion point that
## is one pixel wide.
##
## The cache and the cast table stay on the node and are passed in, for the same
## reason as `sprite_state.gd`: `tools/` reads `_text_drawn` by name.

const Ink := preload("res://director/director_ink.gd")
const Text := preload("res://director/director_text.gd")
const Paint := preload("res://director/director_paint.gd")


## What a field member currently holds: what a script last put there, or failing
## that the text authored into its `STXT`.
static func text_of(member: Dictionary, field_text: Dictionary, table) -> String:
	if member.is_empty():
		return ""
	var key := key_for(int(member.get("cast_lib", 1)), int(member.get("cast_id", 0)), table)
	if field_text.has(key):
		return str(field_text[key])
	return str(member.get("text", ""))


## Where a field override lives: the cast's file, then the member number in it.
##
## Not the library number. A library number is local to a movie -- `MASTER.CST`
## is library 2 in `SAVELOAD.dir` and need not be 2 in the room the save returns
## to -- and `SAVELOAD` writes `field "points" of castLib "master"` for the stage
## to read back out of the same file. Keyed by number, a window and the stage
## would be writing and reading two different entries whenever the two movies
## happened to number the shared cast differently, and agreeing whenever they
## happened to match: a bug that is invisible until the one movie that numbers
## it otherwise.
static func key_for(lib: int, number: int, table) -> String:
	var path := ""
	if table != null and table.cast_libs.has(lib):
		path = str((table.cast_libs[lib] as Dictionary).get("resolved_path", ""))
	if path == "":
		# No table, or a library it does not know: fall back to the number so the
		# entry is still addressable, and keep it distinguishable from a real path.
		path = "#%d" % lib
	return "%s:%d" % [path.to_lower(), number]


## `[cast library, member number]` for a field name, or `[]`.
##
## `first` is what the general member lookup answered, asked before this so that
## a `field` and a `member` reference to the same name never disagree. What that
## lookup cannot do is prefer a field: a name is unique within a cast and not
## across casts, so a *bitmap* called `points` in the movie's own library would
## win over the *field* called `points` in the shared one, and a write would land
## on a member that has no text. So its answer is accepted only when it really is
## a field, and otherwise the libraries are walked again looking only at fields.
##
## **`qualified` is `field "x" of castLib Y`, and it stops the walk.**
## `Movie::getCastMemberIDByNameAndType(name, castLib, type)` searches the named
## library *and nothing else* -- the `castLib == 0` arm is the only one that
## walks every cast, and a named library that does not hold the name answers -1
## with a warning rather than falling through (`movie.cpp:720-759`). The library
## a script names is part of the answer, exactly as it is for `member(...)`; a
## port that keeps searching after it has been told where to look answers with a
## member from a cast the script did not name, which is silence rather than an
## error. `first` already carries the named library's verdict, because
## `members.gd:resolve_ref` refuses to leave a library it was given -- so the
## whole of the rule here is *not walking*.
static func resolve(name: String, first: Array, table, qualified := false) -> Array:
	if table == null:
		return []
	if not first.is_empty() and int(first[1]) > 0 \
			and int(table.get_member(int(first[0]), int(first[1])).get("type", 0)) \
				== Ink.TYPE_FIELD:
		return first
	if qualified:
		return []
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for lib in libs:
		var cast = table.cast_for(int(lib))
		if cast == null:
			continue
		var number: int = cast.number_of(name)
		if number <= 0:
			continue
		if int(cast.member(number).get("type", 0)) == Ink.TYPE_FIELD:
			return [int(lib), number]
	return []


## Drop the field overrides that belong to one container's own cast.
##
## Called on `go to movie`, with the movie being left. See the call site for why
## the *linked* casts are deliberately not dropped.
static func forget(container_path: String, field_text: Dictionary) -> void:
	if container_path == "":
		return
	var prefix := container_path.to_lower() + ":"
	for key in field_text.keys():
		if str(key).begins_with(prefix):
			field_text.erase(key)


## How a selected run is marked. Director's widget inverts the destination; this
## draws a translucent bar behind the glyphs instead, for the same reason the
## text is drawn straight rather than inverted through a matte -- there is no
## destination surface to read here (§13, dirty rects).
const SELECTION_TINT := Color(0.25, 0.45, 0.95, 0.45)


## Paint a field member's text into `rect` on `canvas`, and return the record of
## what was painted.
##
## The record exists because headless Godot builds the draw list and throws it
## away, so there is no painted surface to read back and a harness has no other
## way to tell "the text reached the screen" from "the sprite was skipped" --
## both look like a blank stage. `caret` and `selection` are in it for exactly
## that reason and are the only way a headless harness can assert where the
## insertion point went: the caret is a one-pixel bar and reading it back off a
## framebuffer would be asserting the font.
##
## What is drawn is legible text in roughly the right place at roughly the right
## size and in the member's own colour and alignment. It is not period-accurate
## glyph rendering and does not pretend to be; `director/director_text.gd` says
## exactly what is and is not reproduced.
##
## `focus` is `{}` for every field that does not hold the active widget, which is
## all of them in most movies -- so the editable path costs one dictionary test
## on the 11,525 field sprite records that are not being typed into.
## The style a field is drawn in: the member's authored run, with whatever Lingo
## has written over it.
##
## **A member property write had nowhere to land until this existed.** `set the
## textSize of member "x" to 24` is three sites in this corpus -- all three
## writes, none of them a read -- and the member record is parsed from the
## container and cannot be written back. So the node keeps an override per
## member, exactly as it already does for a field's *text* and its editability,
## and this is the one place the two are combined. `preview/members.gd:read_prop`
## reads through the same table, so a write reads back as itself rather than as
## the authored value, which is the round-trip that makes the property real.
##
## Only what `director_text.gd:style_of` produces is overridable, which is the
## honest boundary: a name this cannot merge is a name nothing draws from, and
## `director_preview.gd:lingo_set_member_prop` reports one rather than storing it.
static func style_for(host, sprite: Dictionary, member: Dictionary) -> Dictionary:
	var style: Dictionary = Text.style_of(member)
	if host == null or not (host.get("_member_style") is Dictionary):
		return style
	var over: Dictionary = host._member_style.get(
		key_for(int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)), host._table), {})
	for name in over:
		style[name] = over[name]
	# The line height follows the point size unless a script set one of its own.
	# Director re-derives it on a `textSize` write, and leaving the authored
	# height behind a doubled point size overlaps every line with the next.
	if over.has("font_size") and not over.has("line_height"):
		style["line_height"] = int(round(int(style["font_size"]) * Text.LINE_HEIGHT_RATIO))
		style["ascent"] = int(round(int(style["line_height"]) * 0.75))
	return style


static func paint(canvas: CanvasItem, sprite: Dictionary, member: Dictionary,
		rect: Rect2, text: String, editable: bool = false,
		focus: Dictionary = {}) -> Dictionary:
	var style: Dictionary = style_for(canvas, sprite, member)
	var caret := Rect2()
	if not focus.is_empty():
		var start := int(focus.get("sel_start", 0))
		var end := int(focus.get("sel_end", 0))
		# The selection is drawn *under* the glyphs, so the text stays readable.
		if end > start:
			_mark_selection(canvas, rect, text, style, start, end)
		caret = Text.caret_rect(rect, text, style, end)
	var lines: int = Text.draw(canvas, rect, text, style, Ink.blend_alpha(sprite))
	if not focus.is_empty() and bool(focus.get("caret_on", false)) and caret.size.y > 0.0:
		Paint.rect(canvas, caret, style["color"], true)
	return {
		"member": int(sprite["cast_id"]), "name": str(member.get("name", "")),
		"text": text, "lines": lines, "rect": rect,
		"font_size": int(style["font_size"]), "color": style["color"],
		"align": int(style["align"]),
		# The editing state, for a harness that cannot read pixels.
		"editable": editable, "focused": not focus.is_empty(),
		"caret": caret,
		"selection": [int(focus.get("sel_start", 0)), int(focus.get("sel_end", 0))],
	}


## Bars behind the selected characters, one per laid-out line the range touches.
##
## Per line rather than one rectangle, because a selection that spans a wrap is
## two disjoint runs on screen and a single box would highlight the whole gap
## between them.
static func _mark_selection(canvas: CanvasItem, rect: Rect2, text: String,
		style: Dictionary, start: int, end: int) -> void:
	for line_value in Text.layout(rect, text, style):
		var line: Dictionary = line_value
		var from: int = int(line["start"])
		var to: int = from + str(line["text"]).length()
		var lo: int = maxi(start, from)
		var hi: int = mini(end, to)
		if hi <= lo:
			continue
		var left: Rect2 = Text.caret_rect(rect, text, style, lo)
		var right: Rect2 = Text.caret_rect(rect, text, style, hi)
		Paint.rect(canvas, Rect2(left.position,
			Vector2(maxf(1.0, right.position.x - left.position.x), left.size.y)),
			SELECTION_TINT, true)
