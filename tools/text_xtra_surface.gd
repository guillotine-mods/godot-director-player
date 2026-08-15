extends SceneTree
## `the text of member` for a promoted `text` Xtra, and the collision it must not
## re-open, asserted through the player's own path rather than off the cast record.
##
##   godot --headless --path . --script tools/text_xtra_surface.gd -- \
##       --root piposh --file PIPDATA/SLOTMACH.dir
##   godot --headless --path . --script tools/text_xtra_surface.gd -- \
##       --file PIP2DATA/MAP.dir
##   godot --headless --path . --script tools/text_xtra_surface.gd      # sweeps for one
##
## `bugs.md` 82's remainder, from the other end. `tools/text_xtra_members.gd`
## proves that the `XMED` chunk decodes and that the member record carries the
## text; it never boots a player, so it cannot say whether a *script* asking for
## the text gets it. That is a real gap between the two and not a formality: the
## member dictionary is read through `preview/members.gd:read_prop`, which is
## reached through `_member_prop_at`, which is reached through the interpreter,
## and any one of those three could answer VOID with the decode working perfectly.
##
## ## What it asserts
##
## **The read.** `the text of member <ref>` is the decoded `XMED` text. The check
## is against the cast record rather than against a quoted string so that this
## file stays title-agnostic -- it names no movie and no member, and finds its
## subject by symbol.
##
## **The type.** `the type of member <ref>` is the symbol **`#text`**, not
## `#xtra`. That is the reference's own answer and it is the one place a promoted
## member's two readings of "type" differ: `TextXtraCastMember` sets
## `_type = kCastXtra` and its `getField(kTheCastType)` arm answers
## `Common::String("text")` as a symbol
## (`lingo/xtras-cast/textxtra.cpp`, ScummVM 805f259a).
##
## **The write.** `set the text of member <ref>` then reading it back -- the
## reference's `setField(kTheText)`, which sets `_text` and marks the member
## modified. A read with no write behind it is a property this port would let a
## script assign to and silently drop.
##
## **The collision, from inside a running movie.** This is the assertion the
## entry asked for and the reason promotion "is not free". `SLOTMACH.dir` holds
## two members named `credit`: #83, this Xtra, and #97, the *field* the slot
## machine's own score draws and its handles read with
## `value(the text of field "credit")`. Before `02844f93` the untyped lookup
## handed `field "credit"` the Xtra, the type test failed, and the machine told
## the player they had not inserted a coin. Promotion is the one change that
## could put that back -- a port that turned these into type-3 members would --
## so the check is not "the field still resolves" but the stronger thing:
##
##   * `the number of member "credit"` answers the **Xtra** (83), because untyped
##     lookup is lowest-number-wins and it is the lower;
##   * `the text of field "credit"` answers the **field**;
##   * and after writing a string into the Xtra's text that the field could not
##     possibly hold, `the text of field "credit"` is **unchanged**.
##
## The third is the one that cannot be satisfied by accident. Two members whose
## text came from one store would agree there; these must disagree.
##
## Where the loaded movie's Xtra has no field of the same name the last three are
## skipped **and say so** rather than passing vacuously, which is the shape
## `gate.sh` records for `sprite_lifetime`'s fourth case.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Members := preload("res://scenes/preview/members.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")

const XTRA := 15
const FIELD := 3
## A string no 1997 cast could be holding already, so "the field did not change"
## and "the field never held this" are the same statement.
const PROBE := "xtra-probe-8547"


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var paths := Paths.new()
	paths.load_config()
	# `--file` only, deliberately not falling back to `--boot`. `gate.sh` passes
	# `--boot <the corpus's boot movie>` to every entry, and that movie holds no
	# `text` Xtra in either root that has one -- so a `--boot` fallback would turn
	# a bare entry into a run that found no subject and asserted nothing, which is
	# the EMPTY the gate exists to catch. With no `--file` this sweeps instead.
	var wanted := Args.text(args, "file", "")
	if wanted == "":
		wanted = _find_container(str(paths.root))
		if wanted == "":
			# Nothing to assert against, said out loud. A root with no `text`
			# Xtra is the normal case -- two of the six shipped titles have none.
			print("no container under %s holds a `text` Xtra; nothing to drive"
				% str(paths.root))
			quit(h.finish("`the text of member` for a promoted `text` Xtra"))
			return
		print("swept %s and picked %s" % [str(paths.root), wanted])

	preview.call("lingo_go_movie", wanted, null)
	await process_frame
	# Paused, because none of this is about the playhead and a room that holds on
	# `go to the frame` would keep the harness waiting for a frame it does not
	# need. Same reason `tools/editable_text.gd` pauses.
	preview.set("_paused", true)

	var table = preview.get("_table")
	if table == null:
		print("%s loaded no cast table" % wanted)
		quit(1)
		return

	var subjects := _subjects(table)
	print("%s: %d `text` Xtra member(s)" % [wanted, subjects.size()])
	if subjects.is_empty():
		print("  none in this movie; pass --file <container> to name one")
		quit(h.finish("`the text of member` for a promoted `text` Xtra"))
		return

	for subject in subjects:
		await _assert_member(h, preview, table, subject)

	quit(h.finish("`the text of member` for a promoted `text` Xtra"))


func _assert_member(h, preview: Node, table, subject: Dictionary) -> void:
	var lib := int(subject["lib"])
	var number := int(subject["number"])
	var member: Dictionary = subject["member"]
	var name := str(member.get("name", ""))
	var ref: int = Members.pack_ref(lib, number)
	var title := "lib %d #%d %s" % [
		lib, number, ("'" + name + "'") if name != "" else "(unnamed)"]
	h.begin(title)

	# --- the read ---------------------------------------------------------
	var authored := str(member.get("text", ""))
	var through_lingo := str(preview.call("lingo_member_prop", ref, "", "text"))
	print("  the text of member = %d char(s): %s" % [
		through_lingo.length(), _one_line(through_lingo)])
	h.check("the member decoded some text out of its XMED",
		authored != "", "%d chars" % authored.length())
	h.check("`the text of member` answers it",
		through_lingo == authored and through_lingo != "",
		"lingo %d chars, cast %d" % [through_lingo.length(), authored.length()])

	# --- the type ---------------------------------------------------------
	var kind: Variant = preview.call("lingo_member_prop", ref, "", "type")
	h.check("`the type of member` is the Xtra's own word, #text",
		str(kind) == "text", str(kind))

	# --- the write --------------------------------------------------------
	preview.call("lingo_set_member_prop", ref, "", "text", PROBE)
	h.check("`set the text of member` reads back",
		str(preview.call("lingo_member_prop", ref, "", "text")) == PROBE,
		str(preview.call("lingo_member_prop", ref, "", "text")))

	# --- the collision ----------------------------------------------------
	var twin := _field_twin(table, lib, number, name)
	if twin <= 0:
		print("  no field of this name in library %d; the collision half is skipped"
			% lib)
		# Restored anyway: a later subject in the same cast could be reading it.
		preview.call("lingo_set_member_prop", ref, "", "text", authored)
		h.complete(title)
		return

	var field_member: Dictionary = table.get_member(lib, twin)
	var field_text := str(preview.call("lingo_field", name, ""))
	var untyped = preview.call("lingo_member_prop", name, "", "number")
	print("  field twin #%d, its text %s; the number of member '%s' = %s" % [
		twin, _one_line(field_text), name, str(untyped)])
	h.check("`the number of member` answers the lower-numbered member, the Xtra",
		int(untyped) == Members.pack_ref(lib, mini(number, twin)),
		"%s" % str(untyped))
	h.check("`the text of field` answers the field and not the Xtra",
		field_text == str(field_member.get("text", "")) and field_text != PROBE,
		_one_line(field_text))
	# The one that cannot pass by accident: the Xtra is holding PROBE right now.
	h.check("writing the Xtra's text leaves the field's alone",
		str(preview.call("lingo_field", name, "")) == field_text
			and field_text != PROBE,
		_one_line(str(preview.call("lingo_field", name, ""))))
	# And the other direction, because a shared store would also survive one
	# write in one direction if the field happened to be read first.
	preview.call("lingo_set_field", name, "", PROBE + "-field")
	h.check("and writing the field's leaves the Xtra's alone",
		str(preview.call("lingo_member_prop", ref, "", "text")) == PROBE,
		str(preview.call("lingo_member_prop", ref, "", "text")))

	preview.call("lingo_set_member_prop", ref, "", "text", authored)
	preview.call("lingo_set_field", name, "", field_text)
	h.complete(title)


## Every `text` Xtra in the loaded movie's casts, ascending.
func _subjects(table) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for lib in libs:
		var cast = table.cast_for(int(lib))
		if cast == null:
			continue
		for number in cast.member_numbers():
			var m: Dictionary = cast.member(number)
			if int(m.get("type", 0)) != XTRA:
				continue
			if str(m.get("xtra_symbol", "")).to_lower() != "text":
				continue
			out.append({"lib": int(lib), "number": number, "member": m})
	return out


## The lowest-numbered *field* of the same name in the same library, or 0.
func _field_twin(table, lib: int, number: int, name: String) -> int:
	if name == "":
		return 0
	var cast = table.cast_for(lib)
	if cast == null:
		return 0
	var best := 0
	for other in cast.member_numbers():
		if other == number:
			continue
		var om: Dictionary = cast.member(other)
		if int(om.get("type", 0)) == FIELD \
				and str(om.get("name", "")).to_lower() == name.to_lower():
			if best == 0 or other < best:
				best = other
	return best


## The first container under `root` holding a `text` Xtra, as a path relative to
## the root -- which is what `lingo_go_movie` takes.
##
## The fallback for a run with no `--file`. Gate entries name their fixture
## instead, because a sweep opens every container of the corpus to find one.
func _find_container(root: String) -> String:
	var files: Array[String] = []
	_walk(root, files)
	files.sort()
	var member_paths := Paths.new()
	member_paths.root = root
	for path in files:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var table := CastTable.new()
		var hit := ""
		if table.open(f, member_paths):
			for lib in table.cast_libs.keys():
				var cast = table.cast_for(int(lib))
				if cast == null:
					continue
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if int(m.get("type", 0)) == XTRA \
							and str(m.get("xtra_symbol", "")).to_lower() == "text":
						hit = path
						break
				if hit != "":
					break
		table.close()
		f.close()
		if hit != "":
			return hit.trim_prefix(root).trim_prefix("/")
	return ""


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	var subs := dir.get_directories()
	subs.sort()
	for sub in subs:
		_walk(dir_path.path_join(sub), out)


func _one_line(text: String) -> String:
	var flat := text.replace("\n", "\\n").replace("\t", "\\t")
	if flat.length() <= 72:
		return "'%s'" % flat
	return "'%s' ... (+%d)" % [flat.substr(0, 72), flat.length() - 72]
