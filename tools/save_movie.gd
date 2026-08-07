extends SceneTree
## Does `saveMovie` write a movie the engine can read back — in another process?
##
##   godot --headless --path . --script tools/save_movie.gd
##
## Three assertions, and the third is the only one that could have caught the bug
## this was written for.
##
## **The writer round-trips.** A copy of a container is rewritten with a longer
## and then a shorter field, reopened with the engine's own reader, and the text
## read back off it. Every chunk that was *not* replaced is compared byte for
## byte against the original, because a writer that relocates something it was
## not asked to touch produces a movie that still opens and is quietly wrong.
##
## **A save survives the process that made it.** A second Godot is launched, and
## it is the one that boots the player, types into a field and calls `saveMovie`.
## It then exits. This process — which has never had that file open for writing —
## reopens it and reads the field. A single-process test cannot tell "persisted"
## from "still in the override table", and *that distinction is the entire bug*:
## `saveMovie` was bound inert, so every save worked perfectly until the player
## restarted the game.
##
## **The container is put back.** The save writes a real game file in place, which
## is what the mechanism is for; leaving it written would dirty the corpus on
## every gate run, so the original bytes are restored at the end and the restore
## is itself checked.
##
## Title-agnostic in shape, not in data: it needs *a* container with *a* field
## member, and it takes the first field of the first container that has one
## unless `--file` and `--field` name others.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Writer := preload("res://director/director_writer.gd")

## Where the copy the writer is exercised on lives. Never a game file: the
## round-trip deliberately includes cases a real save would not produce.
const SCRATCH := "user://save_movie_round_trip.dir"


func _init() -> void:
	var args := Args.parse()
	if Args.text(args, "child", "") != "":
		await _child(args)
		return
	await _parent(args)


# ------------------------------------------------------------------ parent

func _parent(args: Dictionary) -> void:
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured (director_game.cfg)")
		quit(1)
		return

	var wanted := Args.text(args, "file", "")
	var target := ""
	var field_name := Args.text(args, "field", "")
	if wanted != "":
		target = paths.resolve(wanted)
	else:
		var found: Array = _smallest_field_container(paths)
		if found.is_empty():
			print("no container under %s has a field member" % paths.root)
			quit(1)
			return
		target = str(found[0])
		if field_name == "":
			field_name = str(found[1])
	if target == "":
		print("cannot find %s" % wanted)
		quit(1)
		return
	if field_name == "":
		field_name = _first_field_of(target)
	if field_name == "":
		print("%s has no named field member" % target)
		quit(1)
		return
	print("%s, field %s" % [target, field_name])
	print("")

	var original := FileAccess.get_file_as_bytes(target)
	if original.is_empty():
		print("cannot read %s" % target)
		quit(1)
		return

	_round_trip(h, target, field_name)
	await _two_process(h, args, target, field_name)
	_restore(h, target, original)

	quit(h.finish("saveMovie writes a container this engine reopens, "
		+ "and the save outlives the process that made it"))


## The writer, against a copy: a longer text and then a shorter one, each read
## back through the cast, with every untouched chunk compared byte for byte.
func _round_trip(h: Harness, source_path: String, field_name: String) -> void:
	h.begin("round trip")
	var copied := DirAccess.copy_absolute(source_path, SCRATCH)
	if not h.check("the container copies to a scratch path", copied == OK,
			error_string(copied)):
		h.complete("round trip")
		return

	# Long enough that the chunk cannot stay where it was, which is the case that
	# exercises the append path and the mmap repoint. The tail is a high byte
	# rather than a Latin letter on purpose: this corpus's fields are Hebrew in a
	# single-byte Mac codepage, and a writer that encoded as UTF-8 would pass
	# every ASCII test and corrupt every real save.
	var long_text := "saved ".repeat(40) + String.chr(0xE0) + String.chr(0xF9)
	if not _rewrite_and_read(h, SCRATCH, source_path, field_name, long_text, "grown"):
		h.complete("round trip")
		return
	# ...and then shorter than the original, which stays in place.
	_rewrite_and_read(h, SCRATCH, source_path, field_name, "x", "shrunk")
	DirAccess.remove_absolute(SCRATCH)
	h.complete("round trip")


func _rewrite_and_read(h: Harness, scratch: String, pristine: String,
		field_name: String, text: String, label: String) -> bool:
	var file := ContainerFile.new()
	if not file.open(scratch):
		h.check("%s: the scratch copy opens" % label, false, file.error)
		return false
	var cast := Cast.new()
	cast.open(file)
	var number := cast.number_of(field_name)
	var member: Dictionary = cast.member(number)
	var chunk_id := int(member.get("data_chunk_id", -1))
	if chunk_id < 0:
		h.check("%s: the field owns an STXT" % label, false, "member %d" % number)
		file.close()
		return false
	var payload: PackedByteArray = Writer.stxt_with_text(file.read_chunk(chunk_id), text)
	file.close()
	if not h.check("%s: an STXT payload is built" % label, not payload.is_empty()):
		return false

	# Reopened and then *closed* before the rewrite, which is the shape every
	# real in-place save has: the writer replaces the target rather than
	# truncating it, and a platform that locks open files refuses to replace one.
	# The map it needs survives the close.
	var source := ContainerFile.new()
	source.open(scratch)
	source.close()
	var failed: String = Writer.rewrite(source, scratch, {chunk_id: payload})
	if not h.check("%s: the rewrite is accepted" % label, failed == "", failed):
		return false

	var back := ContainerFile.new()
	if not h.check("%s: the rewritten container opens" % label, back.open(scratch),
			back.error):
		return false
	var back_cast := Cast.new()
	var parsed: bool = back_cast.open(back)
	var got := str(back_cast.member(back_cast.number_of(field_name)).get("text", ""))
	h.check("%s: the cast still parses" % label, parsed)
	h.check("%s: the field reads back what was written" % label, got == text,
		"%d chars, wanted %d" % [got.length(), text.length()])
	h.check("%s: no chunk falls outside the file" % label,
		back.out_of_bounds().is_empty())

	# Nothing but the named chunk moved. Compared against the *pristine* file
	# rather than against the previous rewrite, so a chunk corrupted by the first
	# pass cannot be blessed by the second.
	var clean := ContainerFile.new()
	clean.open(pristine)
	var differing := 0
	var checked := 0
	for entry in clean.chunks:
		var id := int(entry["id"])
		# The memory map is the one chunk that is *supposed* to differ -- it is
		# where the replaced chunk's new size and offset are recorded. `imap` is
		# excluded with it because it addresses the map, not because it changes:
		# a rewrite that moved the map would show up as the `imap` differing, and
		# this writer never moves it, so it is checked by the reopen instead.
		if id == chunk_id or entry["tag"] in ["mmap", "imap"] \
				or entry["tag"] in ContainerFile.NON_PAYLOAD_TAGS:
			continue
		checked += 1
		if clean.read_chunk(id) != back.read_chunk(id):
			differing += 1
	clean.close()
	back.close()
	h.check("%s: every other chunk is byte-identical" % label, differing == 0,
		"%d of %d differ" % [differing, checked])
	return differing == 0


## The assertion a single process cannot make: another Godot saves, exits, and
## the file is read here.
func _two_process(h: Harness, args: Dictionary, target: String, field_name: String) -> void:
	h.begin("two processes")
	var marker := "gate-%d" % Time.get_ticks_usec()
	var project := ProjectSettings.globalize_path("res://")
	var child := [
		"--headless", "--path", project,
		"--script", "res://tools/save_movie.gd", "--",
		"--child", "true", "--marker", marker,
		"--field", field_name, "--file", target.get_file(),
	]
	if Args.text(args, "aspect", "") != "":
		child.append_array(["--aspect", Args.text(args, "aspect", "")])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), child, out, true)
	for line in out:
		for row in str(line).split("\n"):
			if str(row).strip_edges() != "":
				print("    | %s" % str(row).strip_edges())
	if not h.check("the saving process exits cleanly", code == 0, "exit %d" % code):
		h.complete("two processes")
		return

	var file := ContainerFile.new()
	if not h.check("the saved container reopens here", file.open(target), file.error):
		h.complete("two processes")
		return
	var cast := Cast.new()
	var parsed: bool = cast.open(file)
	var got := str(cast.member(cast.number_of(field_name)).get("text", ""))
	file.close()
	h.check("the saved container's cast parses", parsed)
	h.check("the field holds what the other process saved", got == marker,
		"%s, wanted %s" % [JSON.stringify(got), JSON.stringify(marker)])
	h.complete("two processes")


## Put the corpus back. Checked rather than assumed: a gate that quietly leaves a
## game file rewritten is a gate that reports a different container every run.
func _restore(h: Harness, target: String, original: PackedByteArray) -> void:
	h.begin("restored")
	var out := FileAccess.open(target, FileAccess.WRITE)
	if not h.check("the original container can be written back", out != null,
			error_string(FileAccess.get_open_error())):
		h.complete("restored")
		return
	out.store_buffer(original)
	out.close()
	h.check("the container is byte-identical to how it was found",
		FileAccess.get_file_as_bytes(target) == original)
	h.complete("restored")


# ------------------------------------------------------------------ child

## Boot the real player on the container, type into the field the way a script
## does, and call `saveMovie`. Everything here goes through the engine's own
## Lingo-facing methods, so what is proved is the path the movie takes.
func _child(args: Dictionary) -> void:
	var field_name := Args.text(args, "field", "")
	var marker := Args.text(args, "marker", "")
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	# Held before the first frame is awaited. The movie's own frame scripts run
	# on that frame and a save movie's first act is frequently to send the
	# playhead somewhere else, which would leave a different container open than
	# the one the parent is about to check -- and the mismatch would read as "the
	# save did not persist".
	preview.call("lingo_hold")
	await process_frame

	if preview.get("_movie") == null:
		print("child: no movie opened")
		quit(1)
		return
	# `go to movie` rather than trusting the boot, because a movie's own first
	# frame script can send the playhead elsewhere before this line is reached --
	# the save movie in this corpus does exactly that. It is also the path the
	# game itself takes to the save screen, so the pair being exercised is the
	# real one: arrive by `go to movie`, write fields, `saveMovie`.
	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		preview.call("lingo_hold")
		await process_frame
	var open_name := str(preview.get("_movie").path).get_file()
	if wanted != "" and open_name.to_lower() != wanted.to_lower():
		print("child: %s is open, not %s" % [open_name, wanted])
		quit(1)
		return
	preview.call("lingo_set_field", field_name, "", marker)
	var report: Dictionary = preview.call("lingo_save_movie",
		str(preview.get("_movie").path).get_file())
	print("child: saved %s, %d fields%s" % [
		str(report["path"]), int(report["written"]),
		("  ERROR " + str(report["error"])) if str(report["error"]) != "" else ""])
	quit(0 if str(report["error"]) == "" and int(report["written"]) > 0 else 1)


# ------------------------------------------------------------------ picking

## The *smallest* container under the root with a named field member, so the
## harness has something to exercise in a title nobody has told it about.
##
## Smallest rather than first, and both words matter. Deterministic, because a
## gate that picks a different file per run is not a gate. Smallest, because this
## rewrites a real game container and restores it afterwards: the least bytes at
## risk is the right default when the tool has not been told which file to use.
func _smallest_field_container(paths: Paths) -> Array:
	var best: Array = []
	var smallest := 1 << 62
	for relative in paths.containers():
		var resolved := paths.resolve(str(relative))
		if resolved == "":
			continue
		var size := FileAccess.get_file_as_bytes(resolved).size()
		if size <= 0 or size >= smallest:
			continue
		var name := _first_field_of(resolved)
		if name == "":
			continue
		smallest = size
		best = [resolved, name]
	return best


func _first_field_of(container_path: String) -> String:
	var file := ContainerFile.new()
	if not file.open(container_path):
		return ""
	var cast := Cast.new()
	if not cast.open(file):
		file.close()
		return ""
	var best := ""
	for number in cast.member_numbers():
		var member: Dictionary = cast.member(int(number))
		if str(member.get("name", "")) == "" or int(member.get("data_chunk_id", -1)) < 0:
			continue
		if int(member.get("type", 0)) != 3:
			continue
		best = str(member["name"])
		break
	file.close()
	return best
