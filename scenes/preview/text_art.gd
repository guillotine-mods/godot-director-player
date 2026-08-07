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
## The cache and the cast table stay on the node and are passed in, for the same
## reason as `sprite_state.gd`: `tools/` reads `_text_drawn` by name.

const Ink := preload("res://director/director_ink.gd")
const Text := preload("res://director/director_text.gd")


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
static func resolve(name: String, first: Array, table) -> Array:
	if table == null:
		return []
	if not first.is_empty() and int(first[1]) > 0 \
			and int(table.get_member(int(first[0]), int(first[1])).get("type", 0)) \
				== Ink.TYPE_FIELD:
		return first
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


## Paint a field member's text into `rect` on `canvas`, and return the record of
## what was painted.
##
## The record exists because headless Godot builds the draw list and throws it
## away, so there is no painted surface to read back and a harness has no other
## way to tell "the text reached the screen" from "the sprite was skipped" --
## both look like a blank stage.
##
## What is drawn is legible text in roughly the right place at roughly the right
## size and in the member's own colour and alignment. It is not period-accurate
## glyph rendering and does not pretend to be; `director/director_text.gd` says
## exactly what is and is not reproduced.
static func paint(canvas: CanvasItem, sprite: Dictionary, member: Dictionary,
		rect: Rect2, text: String) -> Dictionary:
	var style: Dictionary = Text.style_of(member)
	var lines: int = Text.draw(canvas, rect, text, style, Ink.blend_alpha(sprite))
	return {
		"member": int(sprite["cast_id"]), "name": str(member.get("name", "")),
		"text": text, "lines": lines, "rect": rect,
		"font_size": int(style["font_size"]), "color": style["color"],
		"align": int(style["align"]),
	}
