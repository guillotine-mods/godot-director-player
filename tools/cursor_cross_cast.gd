extends SceneTree
## A cursor pair whose members live in a *linked* cast, end to end.
##
##   godot --headless --script tools/cursor_cross_cast.gd -- --root rating --boot mainmenu.dir
##   godot --headless --script tools/cursor_cross_cast.gd -- --file BLAEGOZ.dir
##
## Separate from `tools/cursor_preview.gd` for one reason: that harness runs on
## the gate's pinned corpus, every cursor pair in Piposh 2 names a member of the
## movie's own cast, and **a rule about libraries cannot be measured by a title
## that only ever uses one**. Its "data and mask share one library" check passes
## on `piposh2` no matter what the resolver does, so the defect this file exists
## for could be reintroduced without a single gate row moving.
##
## A second tool rather than a second `cursor_preview` entry carrying `--root`,
## because `gate.sh` resolves a name given on the command line to whichever ALL
## entry comes first and two entries sharing a name is the trap its own comments
## warn about.
##
## What broke (docs/bugs-closed.md 65): `the number of member "cutcursor" of
## castLib "panel.cst"` answered a bare `166`, dropping the library it had just
## looked the name up in. 166 is `leftcursor2` in the movie's own cast and 167 is
## `aa` in Hotel.cst, so one authored pair resolved into two unrelated casts and
## the composed cursor was a silhouette from one file masked by a bitmap from
## another. Every cheap check passed while it did: both members named, both
## bitmaps, image 16x16, something visible in it.
##
## **The subject is found, not named.** Any pair whose data member resolves to a
## library other than 1 is a cross-cast pair, so this asserts against whichever
## movie of the corpus in hand has one, and reports honestly when the corpus has
## none rather than passing over an empty set.

const Harness := preload("res://tools/lib/harness.gd")
const ContainerName := preload("res://director/director_container.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const Members := preload("res://scenes/preview/members.gd")

## Far enough for a room to have entered and run its exitFrame at least once.
const SETTLE_STEPS := 250

## How many containers to open before giving up. A whole corpus is 60-odd movies
## and each costs a compile plus a settle.
const SEARCH_LIMIT := 16


func _settle(preview: Node) -> void:
	for i in SETTLE_STEPS:
		preview.call("_advance")


func _loaded(preview: Node) -> String:
	var movie = preview.get("_movie")
	return "" if movie == null else str(movie.path).get_file()


## The pairs on this movie's channels whose data member is not in library 1.
func _cross(preview: Node) -> Array:
	var table = preview.get("_table")
	var out: Array = []
	var cursors: Dictionary = preview.get("_channel_cursors")
	for channel in cursors.keys():
		var value: Variant = cursors[channel]
		if typeof(value) != TYPE_ARRAY:
			continue
		var pair: Array = value
		if pair.is_empty() or int(pair[0]) == 0:
			continue
		if int(Cursor.where(int(pair[0]), table)[0]) > 1:
			out.append([channel, pair])
	return out


func _movies(dir_path: String, prefix: String = "") -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for entry in files:
		if ContainerName.MOVIE.has(entry.get_extension().to_lower()):
			out.append(prefix + entry)
	var subs := dir.get_directories()
	subs.sort()
	for sub in subs:
		out.append_array(_movies(dir_path.path_join(sub), prefix + sub + "/"))
	return out


func _init() -> void:
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	if scene == null:
		print("no preview scene")
		quit(1)
		return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	_settle(preview)

	var found: Array = _cross(preview)
	if found.is_empty():
		var booted := _loaded(preview)
		print("%s has no cross-cast cursor pair; searching" % booted)
		var paths = preview.get("_paths")
		var tried := 0
		for candidate in _movies(str(paths.root)):
			if tried >= SEARCH_LIMIT:
				break
			if str(candidate).get_file().to_lower() == booted.to_lower():
				continue
			tried += 1
			preview.call("lingo_go_movie", candidate, null)
			if _loaded(preview).to_lower() != str(candidate).get_file().to_lower():
				continue
			_settle(preview)
			found = _cross(preview)
			if not found.is_empty():
				break
		print("searched %d container(s)" % tried)

	var table = preview.get("_table")
	print("measuring %s" % _loaded(preview))

	# A corpus with no cross-cast pair is a real answer and not a pass. Reported
	# as its own failed check rather than as silence, because silence here reads
	# exactly like coverage.
	h.begin("the corpus has a cursor pair that crosses casts")
	h.check("a cross-cast pair was found", not found.is_empty(),
		"%d pair(s) %s" % [found.size(), str(found)])
	h.complete("the corpus has a cursor pair that crosses casts")
	if found.is_empty():
		quit(h.finish("a cursor pair whose members live in a linked cast"))
		return

	h.begin("the library the script named is the library the art comes from")
	var split: Array = []
	var unnamed: Array = []
	var papered: Array = []
	for entry in found:
		var channel = entry[0]
		var pair: Array = entry[1]
		var mask_id: int = int(pair[1]) if pair.size() > 1 else 0
		var at: Array = Cursor.where(int(pair[0]), table)
		var data: Dictionary = table.get_member(int(at[0]), int(at[1]))
		# The name is the check that a *number* landed on the member the script
		# asked for. It is not sufficient on its own -- the wrong resolution
		# landed on `leftcursor2`, which is named -- which is why the library
		# agreement below is the one that fails when this breaks.
		if str(data.get("name", "")) == "":
			unnamed.append("ch%s data %s:%s" % [str(channel), str(at[0]), str(at[1])])
		if mask_id > 0:
			var mask_at: Array = Cursor.where(mask_id, table)
			var mask: Dictionary = table.get_member(int(mask_at[0]), int(mask_at[1]))
			if int(mask_at[0]) != int(at[0]):
				split.append("ch%s data lib %s (%s), mask lib %s (%s)" % [
					str(channel), str(at[0]), str(data.get("name", "<unnamed>")),
					str(mask_at[0]), str(mask.get("name", "<unnamed>"))])
			if str(mask.get("name", "")) == "":
				unnamed.append("ch%s mask %s:%s" % [
					str(channel), str(mask_at[0]), str(mask_at[1])])
		var composed = preview.call("_cursor_image", int(pair[0]), mask_id)
		if composed == null:
			papered.append("ch%s composes to nothing" % str(channel))
			continue
		print("   ch%s %s -> %s of lib %s, mask lib %s" % [str(channel), str(pair),
			str(data.get("name", "<unnamed>")), str(at[0]),
			str(Cursor.where(mask_id, table)[0]) if mask_id > 0 else "none"])
	h.check("every member of a cross-cast pair is named", unnamed.is_empty(),
		", ".join(PackedStringArray(unnamed)))
	h.check("data and mask come from one library", split.is_empty(),
		", ".join(PackedStringArray(split)))
	h.check("every cross-cast pair still composes", papered.is_empty(),
		", ".join(PackedStringArray(papered)))
	h.complete("the library the script named is the library the art comes from")

	# The mechanism under all of it, asserted where it is cheap to say plainly: a
	# packed reference must survive the round trip that carries it. Library 1 is
	# the identity case and is included on purpose -- it is the one every other
	# title takes, and a pack that stopped being identity there would move every
	# member number in the corpus.
	h.begin("a packed member reference round-trips")
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	var broken: Array = []
	for lib in libs:
		for slot in [1, 166, 4096]:
			var packed := Members.pack_ref(int(lib), int(slot))
			var back: Array = Cursor.where(packed, table)
			if int(lib) > 1 and (int(back[0]) != int(lib) or int(back[1]) != int(slot)):
				broken.append("lib %s slot %d packed to %d, read back %s" % [
					str(lib), slot, packed, str(back)])
	h.check("library 1 packs to the bare number", Members.pack_ref(1, 166) == 166,
		str(Members.pack_ref(1, 166)))
	h.check("every other library round-trips", broken.is_empty(),
		", ".join(PackedStringArray(broken)))
	h.complete("a packed member reference round-trips")

	quit(h.finish("a cursor pair whose members live in a linked cast"))
