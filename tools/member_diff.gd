extends SceneTree
## Member geometry from the container, against the exported members.json.
##
##   godot --headless --script tools/member_diff.gd -- --file PIP2DATA/EXODUS.DIR
##
## Every placement calculation in the renderer is `loc - reg_offset`, so a wrong
## registration point puts correct data through a correct formula and lands the
## art in the wrong place. The score reader is already proven exact by
## `tools/score_diff.gd`; this is the other half of the same question, and the
## only input to placement with no harness behind it.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")

const FIELDS := ["width", "height", "reg_offset_x", "reg_offset_y"]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var wanted := Args.text(args, "file", paths.boot_movie)
	var path: String = paths.resolve(wanted)
	if path == "":
		print("no such container: %s" % wanted)
		quit(1)
		return
	var movie := path.get_file().get_basename().to_upper()
	var export_path := "res://assets/render_model/%s/members.json" % movie
	if not FileAccess.file_exists(export_path):
		print("no export to compare against: %s" % export_path)
		quit(1)
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("%s is not a member table" % export_path)
		quit(1)
		return
	# The table sits under `members`; the file's top level is movie / cast_libs /
	# members. Reading the top level compares nothing and passes every check
	# except the one asserting that something was compared — which is exactly why
	# that check exists.
	var exported: Dictionary = parsed.get("members", {})

	var movie_file := ContainerFile.new()
	if not movie_file.open(path):
		print("%s: %s" % [path, movie_file.error])
		quit(1)
		return
	var table := CastTable.new()
	table.open(movie_file, paths)

	var compared := 0
	var missing := 0
	var mismatched: Array[String] = []
	var by_field: Dictionary = {}

	h.begin("member geometry matches the export")
	for key in exported.keys():
		var text := str(key)
		# The export double-keys members as "lib:id" and bare "id"; the scoped
		# form is the unambiguous one, so the bare aliases are skipped rather
		# than compared twice.
		if not text.contains(":"):
			continue
		var parts := text.split(":")
		if parts.size() != 2:
			continue
		var lib := int(parts[0])
		var id := int(parts[1])
		var want: Variant = exported[key]
		if typeof(want) != TYPE_DICTIONARY:
			continue
		# Only members with real geometry: a script or a shape has none to check.
		if float((want as Dictionary).get("width", 0)) <= 0.0:
			continue
		var got: Dictionary = table.get_member(lib, id)
		if got.is_empty():
			missing += 1
			if mismatched.size() < 20:
				mismatched.append("%s: not found in the container" % text)
			continue
		compared += 1
		for field in FIELDS:
			var expected := int(float((want as Dictionary).get(field, 0)))
			var actual := int(got.get(field, 0))
			if expected != actual:
				by_field[field] = int(by_field.get(field, 0)) + 1
				if mismatched.size() < 20:
					mismatched.append("%s %s: expected %d, got %d" % [
						text, field, expected, actual,
					])

	h.check("members were actually compared", compared > 0, "%d member(s)" % compared)
	h.check("every member resolves in the container", missing == 0, "%d missing" % missing)
	h.check("geometry matches", by_field.is_empty(), JSON.stringify(by_field))
	h.complete("member geometry matches the export")

	for line in mismatched:
		print("     %s" % line)
	print("")
	print("%s: compared %d, missing %d" % [movie, compared, missing])
	print("by field : %s" % JSON.stringify(by_field))
	table.close()
	movie_file.close()
	quit(h.finish("container member geometry agrees with the export"))
