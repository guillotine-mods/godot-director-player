extends SceneTree
## One marker per `VWLB` entry, in frame order, in every container of every root.
##
##   godot --headless --path . --script tools/label_index.gd
##   godot --headless --path . --script tools/label_index.gd -- --root rating
##   godot --headless --path . --script tools/label_index.gd -- --all
##   godot --headless --path . --script tools/label_index.gd -- --file BATZEGOZ.dir --list
##
## `marker(n)` is **index** arithmetic over the marker array, so the array is the
## chunk's index space and not a convenience list. `lingo_marker` finds the entry
## covering the playhead and returns the frame `offset` entries away
## (`scenes/director_preview.gd:2774`), matching `Score::getNextLabelNumber`,
## which walks every `Label` the reference inserted -- one per entry, named or
## not. Filter the array anywhere and every `marker(n)` past the filtered entry
## answers with the wrong frame, in every script in the movie, with nothing
## printed.
##
## This exists because that failure has already happened and was already
## *diagnosed*, and still shipped. `bugs.md` 40 filed it against Rating's
## `BATZEGOZ.dir` -- `go(marker(1))` counting past an unnamed marker onto the next
## room, so the `play done` on that marker never ran and a dialogue answered every
## option with the same reply -- and printed the fix. Commit 641d1d47 landed that
## fix and was inert: it moved `markers.append` above the name check but left the
## range guard four lines higher, which had already `continue`d on a zero-length
## name. The comment claimed the entries were kept, the code still dropped them,
## and the only harness that would have noticed re-parsed the chunk and repaired
## the array before asserting anything (`tools/play_suspends.gd`, now an assertion
## instead).
##
## So the invariant is checked against the chunk header rather than against
## anything the reader believes: **`markers.size()` equals the count the chunk
## declares.** That is a number from outside the pipeline, which is the whole
## argument of `porting-fidelity-verification` -- a decode agreeing with itself
## proves nothing.
##
## Two things asserted per root:
##
##   * every `VWLB` the reader accepts yields one marker per declared entry;
##   * markers come out in non-decreasing frame order, because `lingo_marker`
##     `break`s at the first entry past the playhead and a shuffled array would
##     make it stop early.
##
## A chunk `parse` *rejects* (too short, or a count that runs past the end) is
## counted and printed rather than failed: refusing a malformed chunk is correct,
## and a root where every chunk was refused fails the "the sweep reached its
## containers" check instead, which is the honest way round.
##
## Title-agnostic: the expected count comes from each container, so no number in
## this file is a corpus measurement that can rot.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")

## Named rather than discovered, for the reason `parse_residue.gd` gives: a folder
## dropped in beside them must not silently join the sweep and move the numbers.
const ROOTS := ["piposh", "piposh2", "piposh-en", "piposh-ru", "piposh-dream", "rating"]


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var h := Harness.new()
	var single := Args.text(args, "file")
	if single != "":
		_one(h, paths.resolve(single), Args.flag(args, "list"))
		quit(h.finish("one marker per VWLB entry"))
		return

	var roots: Array = ROOTS if Args.flag(args, "all") else [paths.root]
	for root in roots:
		var dir := str(root)
		if not dir.begins_with("res://"):
			dir = "res://games/%s" % dir
		var case_name := dir.get_file()
		h.begin(case_name)

		var files := PackedStringArray()
		_collect(dir, files)
		var accepted := 0
		var refused := 0
		var entries := 0
		var unnamed := 0
		var miscounts: Array[String] = []
		var unsorted: Array[String] = []
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			for id in f.ids_of("VWLB"):
				var payload := f.read_chunk(id)
				if payload.size() < 2:
					refused += 1
					continue
				var declared := (payload[0] << 8) | payload[1]
				var labels := Labels.new()
				if not labels.parse(payload):
					refused += 1
					print("   refused  %-16s VWLB %d: %s" % [
						str(path).get_file(), id, labels.error])
					continue
				accepted += 1
				entries += declared
				for marker in labels.markers:
					if str(marker["name"]) == "":
						unnamed += 1
				if labels.markers.size() != declared:
					miscounts.append("%-16s VWLB %d: chunk declares %d, reader kept %d" % [
						str(path).get_file(), id, declared, labels.markers.size()])
				var previous := -(1 << 30)
				for marker in labels.markers:
					var at := int(marker["frame"])
					if at < previous:
						unsorted.append("%-16s VWLB %d: frame %d after %d" % [
							str(path).get_file(), id, at, previous])
						break
					previous = at

		for line in miscounts:
			print("   DROPPED  %s" % line)
		for line in unsorted:
			print("   UNSORTED %s" % line)
		h.check("%s: one marker per VWLB entry" % case_name, miscounts.is_empty(),
			"%d chunk(s) short of their own count, %d entries in %d chunk(s), %d unnamed" % [
				miscounts.size(), entries, accepted, unnamed])
		h.check("%s: markers are in frame order" % case_name, unsorted.is_empty(),
			"%d out of order" % unsorted.size())
		# A sweep that read nothing asserts nothing, and a root whose containers
		# all failed to open would otherwise read as the cleanest of the six.
		h.check("%s: the sweep reached its containers" % case_name, accepted > 0,
			"%d chunk(s) read, %d refused, %d container(s) on disc" % [
				accepted, refused, files.size()])
		h.complete(case_name)

	quit(h.finish("every VWLB entry survives into `marker(n)`'s index space"))


## One container, with `--list` printing the entries so a marker can be checked by
## eye against the movie. The unnamed ones are the point, so they are labelled
## rather than shown as a blank.
func _one(h: Harness, path: String, listing: bool) -> void:
	var case_name := str(path).get_file()
	h.begin(case_name)
	var f := ContainerFile.new()
	if not f.open(path):
		h.check("%s: opens" % case_name, false, f.error)
		h.complete(case_name)
		return
	var ids := f.ids_of("VWLB")
	if ids.is_empty():
		h.check("%s: has a VWLB" % case_name, false, "none")
		h.complete(case_name)
		return
	var accepted := 0
	for id in ids:
		var payload := f.read_chunk(id)
		var declared := ((payload[0] << 8) | payload[1]) if payload.size() >= 2 else -1
		var labels := Labels.new()
		if not labels.parse(payload):
			h.check("%s VWLB %d: parses" % [case_name, id], false, labels.error)
			continue
		accepted += 1
		if listing:
			for i in labels.markers.size():
				var marker: Dictionary = labels.markers[i]
				print("   %3d  frame %5d  %s" % [
					i, int(marker["frame"]),
					str(marker["name"]) if str(marker["name"]) != "" else "<unnamed>"])
		h.check("%s VWLB %d: one marker per entry" % [case_name, id],
			labels.markers.size() == declared,
			"chunk declares %d, reader kept %d" % [declared, labels.markers.size()])
	# Every chunk refused would otherwise close this case having asserted only that
	# each refusal happened -- `harness.gd`'s "a dead check fails" rule applied to a
	# loop that can run zero useful iterations.
	h.check("%s: at least one readable VWLB" % case_name, accepted > 0,
		"%d of %d chunk(s)" % [accepted, ids.size()])
	h.complete(case_name)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.get_extension().to_lower() in ["dir", "dxr", "cst", "cxt"]:
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
