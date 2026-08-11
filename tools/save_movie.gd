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
##
## ---------------------------------------------------------------------------
##
## **Writing into the corpus is the dangerous part of this file, and the danger
## is not the write.** It is that the restore is a statement in a script, and a
## statement only runs if the process lives to reach it.
##
## Two independent holes, both closed here, and they want different mechanisms
## because they are different shapes of failure.
##
## *The run dies between the save and the restore.* `gate.sh` wraps every entry
## in `gate_run_capped ${GATE_TIMEOUT:-900}` and already treats exit 124 as a
## reachable state; a kill landing in that window leaves a real game container
## rewritten with a `gate-<usec>` marker in one of its fields, and nothing on the
## next run would have noticed. So the original bytes go to a **sidecar under
## `user://` before the child is launched**, and the next run of this harness
## restores from it. That makes the restore survive process death, which is the
## one thing an `await`-less statement cannot do by itself.
##
## The sidecar has to be safe to find, which is a stronger requirement than
## being able to write bytes back:
##
##   idempotent      a second run finds the file already equal to the backup and
##                   writes nothing.
##   evidence-led    it restores only when the container still reads back the
##                   *marker that sidecar recorded*, or has stopped parsing
##                   altogether. A container that opens cleanly and holds
##                   somebody else's text is a legitimately-changed file, and the
##                   sidecar is discarded with a line saying so rather than
##                   fighting it. Rolling a real edit back to a stale copy of a
##                   game file is a worse failure than the one being fixed.
##
## *The permission is process-wide and the backup is one file.* `--allow-writes`
## lifts `movie_save.gd:writes_allowed` for the child's whole process, so a
## `savemovie` fired by the *movie's own* Lingo at a different container is
## written and is not in any backup. That is not hypothetical: `piposh-dream`'s
## frame 3 is `on exitFrame / dosave / end`, and it is what destroyed that title's
## `Saves.dir`. The playhead is held before frame scripts run (`_child` below),
## which is the reason it does not happen; "the reason it does not happen" is not
## the same as a check, so every container under the root is fingerprinted by
## size and mtime around the child and **anything but the target changing is a
## failure naming the file**. Detection and not repair, said plainly: this
## harness cannot back up 553 MB of corpus to make a one-file assertion, so what
## it buys is that the next incident is reported by the run that caused it
## instead of by a `git status` weeks later.
##
## `--crash-after-save` kills this process between the child's save and the
## restore, which is the only honest way to exercise the paragraph above. It is
## for demonstrating the self-heal by hand and no gate entry passes it.
##
## *One write into `games/` this harness does not make and cannot fix from here.*
## `games/piposh-dream/FX/DRILL.WAV.import` is Godot's own import sidecar, written
## under a read-only submodule the first time the project is scanned. It is the
## only one, and the reason is a one-off: that is the single `.wav` in six titles
## — every other sound in the corpus is `.AIF`, which Godot's importer does not
## claim — so one file gets a sidecar and 3,000 do not. It is untracked rather
## than a modification, so no `git status --porcelain` line above is about it, and
## it is recorded here because a write into `games/` should be written down
## somewhere even when it is harmless.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Writer := preload("res://director/director_writer.gd")

## Where the copy the writer is exercised on lives. Never a game file: the
## round-trip deliberately includes cases a real save would not produce.
const SCRATCH := "user://save_movie_round_trip.dir"

## The crash-safe backup, in two files because they are read at different times:
## the manifest is small and parsed first, the bytes are only touched once the
## manifest says a restore is warranted. `user://` rather than beside the target,
## because a sidecar written *into* the corpus is another write into `games/` and
## would be the bug it exists to prevent.
##
## One slot, not one per root, and `gate.sh`'s `.gate.lock` is what makes that
## safe: two of these running at once would already be two processes saving and
## restoring the same container, which is a race the sidecar cannot fix and the
## lock exists to prevent. Measured the hard way -- running this harness directly
## while another agent's gate held the lock had one run's restore land between the
## other's save and its read-back, and the field came back `"untitled"`.
const PENDING_MANIFEST := "user://save_movie_pending.json"
const PENDING_BYTES := "user://save_movie_pending.bin"


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

	# First, before anything reads a container: a sidecar from a run that died
	# mid-save means the file this harness is about to measure is the *saved* one,
	# and every assertion below would then be made against the damage.
	_heal(h)

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

	# The marker is minted here rather than inside `_two_process`, because the
	# sidecar has to record what the child is *about* to write before the child
	# can write it. That string is the whole of the evidence the self-heal runs
	# on: a container still holding this exact marker is a container this harness
	# wrote and did not put back.
	var marker := "gate-%d" % Time.get_ticks_usec()
	_arm(h, target, field_name, marker, original)
	var before_files := _fingerprint(paths)

	await _two_process(h, args, target, field_name, marker)

	if Args.flag(args, "crash-after-save"):
		print("")
		print("--crash-after-save: killing this process before the restore.")
		print("  %s is left saved; the sidecar is %s" % [target.get_file(), PENDING_MANIFEST])
		print("  run this harness again to watch it heal.")
		OS.kill(OS.get_process_id())
		return

	_collateral(h, paths, target, before_files)
	if _restore(h, target, original):
		_disarm()
	else:
		print("the restore did not take; the sidecar is left armed at %s" % PENDING_MANIFEST)

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
func _two_process(h: Harness, args: Dictionary, target: String, field_name: String,
		marker: String) -> void:
	h.begin("two processes")
	var project := ProjectSettings.globalize_path("res://")
	var child := [
		"--headless", "--path", project,
		"--script", "res://tools/save_movie.gd", "--",
		"--child", "true", "--marker", marker,
		"--field", field_name, "--file", target.get_file(),
	]
	if Args.text(args, "aspect", "") != "":
		child.append_array(["--aspect", Args.text(args, "aspect", "")])
	# The child reads `director_game.cfg` for itself, so a parent pinned to one
	# corpus and a child told nothing are two different games -- and the check
	# below then compares a save from one against a movie from the other.
	# `gate.sh` pins with `--root` rather than by rewriting the config, which is
	# what makes this line load-bearing rather than tidy.
	if Args.text(args, "root", "") != "":
		child.append_array(["--root", Args.text(args, "root", "")])
	# And the boot movie with it: a pinned root plus the config's own boot movie
	# is a container that does not exist under that root, so the child opens
	# nothing and the comparison below runs against an empty session.
	if Args.text(args, "boot", "") != "":
		child.append_array(["--boot", Args.text(args, "boot", "")])
	# The child is the process that actually calls `saveMovie`, and container
	# writes are refused in a headless process that has not asked for them
	# (`movie_save.gd:writes_allowed`). A command-line opt-in is not inherited the
	# way an environment variable would be, so this harness -- the one whose
	# subject *is* the save -- has to hand it on explicitly.
	child.append("--allow-writes")
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
##
## Returns whether the file is now the bytes it was found with, which is what
## decides whether the crash-safe sidecar may be thrown away. A restore that
## could not open the file for writing is the one moment the sidecar is *most*
## needed, so it has to outlive a failed restore rather than be cleared beside it.
func _restore(h: Harness, target: String, original: PackedByteArray) -> bool:
	h.begin("restored")
	var out := FileAccess.open(target, FileAccess.WRITE)
	if not h.check("the original container can be written back", out != null,
			error_string(FileAccess.get_open_error())):
		h.complete("restored")
		return false
	out.store_buffer(original)
	out.close()
	var back: bool = h.check("the container is byte-identical to how it was found",
		FileAccess.get_file_as_bytes(target) == original)
	h.complete("restored")
	return back


# --------------------------------------------------------------- crash safety

## Write the crash-safe backup, before the child that does the damage exists.
##
## Bytes first and the manifest second, and that order is the commit: a kill
## between the two leaves a stray `.bin` with no manifest, which the next run
## never looks at. A manifest with no bytes, the other order, would be a run that
## believes it has a backup it does not have.
func _arm(h: Harness, target: String, field_name: String, marker: String,
		original: PackedByteArray) -> void:
	h.begin("armed")
	var bytes := FileAccess.open(PENDING_BYTES, FileAccess.WRITE)
	if not h.check("the crash-safe backup opens for writing", bytes != null,
			error_string(FileAccess.get_open_error())):
		h.complete("armed")
		return
	bytes.store_buffer(original)
	bytes.close()
	var manifest := FileAccess.open(PENDING_MANIFEST, FileAccess.WRITE)
	if not h.check("and its manifest does", manifest != null,
			error_string(FileAccess.get_open_error())):
		h.complete("armed")
		return
	manifest.store_string(JSON.stringify({
		"target": target,
		"field": field_name,
		"marker": marker,
		"size": original.size(),
	}))
	manifest.close()
	# Read back rather than assumed, for the same reason `_restore` checks itself:
	# an unwritable `user://` would otherwise turn every later run into an
	# unprotected one, silently.
	h.check("the backup is on disc before the child is launched",
		FileAccess.get_file_as_bytes(PENDING_BYTES).size() == original.size(),
		"%d bytes at %s" % [original.size(), PENDING_BYTES])
	h.complete("armed")


func _disarm() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_MANIFEST))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_BYTES))


## Put back what a run that never reached `_restore` left written.
##
## Silent and free when there is no sidecar, which is every ordinary run. When
## there is one it is resolved one of four ways, and three of them write nothing:
## the file already matches the backup (a restore that did happen, or a second
## heal); the backup is short, so the sidecar itself was interrupted and is not
## trustworthy; or the container opens and holds text that is not the marker this
## sidecar recorded, which makes it somebody's real change and not ours to undo.
## Only a container still carrying the marker — or one that has stopped parsing,
## which is the shape of a kill landing inside the writer — is written back.
func _heal(h: Harness) -> void:
	if not FileAccess.file_exists(PENDING_MANIFEST):
		return
	h.begin("self-heal")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PENDING_MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		h.check("the sidecar manifest parses", false, PENDING_MANIFEST)
		_disarm()
		h.complete("self-heal")
		return
	var manifest: Dictionary = parsed
	var target := str(manifest.get("target", ""))
	var field_name := str(manifest.get("field", ""))
	var marker := str(manifest.get("marker", ""))
	var backup := FileAccess.get_file_as_bytes(PENDING_BYTES)
	print("")
	print("a previous run of this harness did not restore %s" % target)
	print("  sidecar: %s, marker %s" % [PENDING_MANIFEST, marker])

	if not h.check("the backed-up bytes are all there",
			not backup.is_empty() and backup.size() == int(manifest.get("size", -1)),
			"%d bytes, manifest says %d" % [backup.size(), int(manifest.get("size", -1))]):
		_disarm()
		h.complete("self-heal")
		return

	var exists := FileAccess.file_exists(target)
	if exists and FileAccess.get_file_as_bytes(target) == backup:
		h.check("the container already holds the bytes the sidecar backed up", true,
			"nothing written; the restore is idempotent")
		_disarm()
		h.complete("self-heal")
		return

	# The evidence test. `_field_text` returning false is a container that no
	# longer opens or whose cast no longer parses, which nothing but an
	# interrupted writer produces on a file that was fine when the sidecar was
	# written -- so that counts as ours.
	var read: Array = _field_text(target, field_name)
	var readable := bool(read[0])
	var ours := (not exists) or (not readable) or str(read[1]) == marker
	if not ours:
		h.check("a container this harness did not write is left alone", true,
			"field %s holds %s, not the marker -- sidecar discarded unused"
			% [field_name, JSON.stringify(str(read[1]))])
		_disarm()
		h.complete("self-heal")
		return

	var why := "still carries the marker"
	if not exists:
		why = "is missing"
	elif not readable:
		why = "no longer parses"
	print("  %s %s: restoring %d bytes" % [target.get_file(), why, backup.size()])
	var out := FileAccess.open(target, FileAccess.WRITE)
	if not h.check("the backed-up container can be written back", out != null,
			error_string(FileAccess.get_open_error())):
		h.complete("self-heal")
		return
	out.store_buffer(backup)
	out.close()
	h.check("and the container is byte-identical to the backup again",
		FileAccess.get_file_as_bytes(target) == backup, "%s" % target.get_file())
	_disarm()
	h.complete("self-heal")


## The field's text, and whether the container could be read at all. Separate
## from `_two_process`'s copy of the same three lines because the self-heal has
## to tell "wrong text" from "will not open", and those are different verdicts.
func _field_text(container_path: String, field_name: String) -> Array:
	if not FileAccess.file_exists(container_path):
		return [false, ""]
	var file := ContainerFile.new()
	if not file.open(container_path):
		return [false, ""]
	var cast := Cast.new()
	if not cast.open(file):
		file.close()
		return [false, ""]
	var text := str(cast.member(cast.number_of(field_name)).get("text", ""))
	file.close()
	return [true, text]


## Every container under the root by size and mtime, which is what a write moves.
##
## Size and mtime rather than a hash, deliberately: this runs twice per gate entry
## over the whole root — 86 containers under `piposh2`, 172 opens — and hashing
## 553 MB to catch a write that already moves a timestamp buys nothing.
##
## **The mtime is the half doing the work, and that was measured rather than
## assumed.** A `saveMovie` of one field is not reliably a size change: the marker
## this harness writes is `gate-<usec>`, and a run where the field it replaced was
## the same length left `HEZSAVE.DIR` at 137,655 bytes before and after. Size
## alone would have reported silence for a write that had just happened, which is
## exactly the failure this sweep exists to rule out. What the pair still cannot
## see is a foreign write inside the same *second* as the "before" reading that
## also restores the byte count; the child runs for about ten seconds, so that
## window is not one a real `savemovie` from a frame script lands in.
func _fingerprint(paths: Paths) -> Dictionary:
	var out: Dictionary = {}
	for relative in paths.containers():
		var resolved := paths.resolve(str(relative))
		if resolved == "":
			continue
		var f := FileAccess.open(resolved, FileAccess.READ)
		if f == null:
			continue
		var size := f.get_length()
		f.close()
		out[resolved] = "%d:%d" % [size, FileAccess.get_modified_time(resolved)]
	return out


## What the child touched besides the file it was told to.
##
## `--allow-writes` is process-wide, the backup is one file, and the only thing
## standing between those two facts and a destroyed container is that `_child`
## holds the playhead before any frame script runs. This is the check that says so
## out loud. The second assertion is the one that keeps the first honest: a sweep
## that cannot see the write it *knows* happened is a sweep that would report
## silence for a write it does not know about.
func _collateral(h: Harness, paths: Paths, target: String, before: Dictionary) -> void:
	h.begin("blast radius")
	var after := _fingerprint(paths)
	var moved: Array[String] = []
	for path in after:
		if str(path) == target:
			continue
		if not before.has(path):
			moved.append("%s (appeared)" % str(path).get_file())
		elif str(before[path]) != str(after[path]):
			moved.append(str(path).get_file())
	for path in before:
		if str(path) != target and not after.has(path):
			moved.append("%s (vanished)" % str(path).get_file())
	h.check("the child wrote nothing but the container it was told to",
		moved.is_empty(), "%d of %d container(s) moved%s" % [
			moved.size(), before.size(),
			(": " + ", ".join(moved)) if not moved.is_empty() else ""])
	h.check("and the sweep can see the write it knows about",
		str(before.get(target, "before")) != str(after.get(target, "after")),
		"%s: %s -> %s" % [target.get_file(),
			str(before.get(target, "-")), str(after.get(target, "-"))])
	h.complete("blast radius")


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
