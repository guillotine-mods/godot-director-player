extends SceneTree
## Bitmap cast members decoded from the containers, with a PNG to look at.
##
##   godot --headless --script tools/director_bitmaps.gd
##   godot --headless --script tools/director_bitmaps.gd -- --file MASTER.CST --member 54 --out user://piphead1.png
##   godot --headless --script tools/director_bitmaps.gd -- --file MASTER.CST --name shell --out user://shell.png
##
## The sweep asserts that every bitmap in the game decodes and consumes its whole
## chunk. A decode that stops early used to be recorded as authentic, so the
## check is "filled the buffer exactly", never "produced something".
##
## The depth census is a tripwire, not decoration. Reading the pitch's high bit
## as "8bpp" rather than "not 1-bit" mis-decodes the 16- and 32-bit members into
## plausible-looking noise, and a cursor of noise installs perfectly happily.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const Bitmap := preload("res://director/director_bitmap.gd")

## Both ink passes treat "every channel at or above this" as paper.
const PAPER_MIN_BYTE := 241


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var table: PackedByteArray = Palette.system_mac()
	print("args       : %s" % JSON.stringify(args))

	if Args.text(args, "file") != "":
		_dump(paths, args, table)
		quit(0)
		return

	# The corpus sweep is opt-in. It decodes 11,520 bitmaps and takes minutes,
	# and having it be what happens when an argument fails to parse means a typo
	# looks exactly like a hang.
	if not Args.flag(args, "all"):
		print("")
		print("nothing to do. --file <container> [--member N | --name X] [--out path]")
		print("               --all   decode every bitmap in the game (slow)")
		quit(0)
		return

	# --- the palette both ink passes depend on -------------------------------
	h.begin("the palette keys exactly one index as paper")
	h.check("index 0 is white", Palette.index_of_white(table) == 0,
		"white at %d" % Palette.index_of_white(table))
	h.check("index 255 is black", Palette.index_of_black(table) == 255,
		"black at %d" % Palette.index_of_black(table))
	var papery: Array[int] = Palette.indices_at_least(table, PAPER_MIN_BYTE)
	h.check("only index 0 reads as paper", papery.size() == 1 and papery[0] == 0, str(papery))
	h.complete("the palette keys exactly one index as paper")

	# --- every bitmap in the game -------------------------------------------
	var decoded := 0
	var raw := 0
	var zero_area := 0
	var no_chunk := 0
	var depths := {}
	var failures: Array[String] = []
	var started := Time.get_ticks_usec()

	h.begin("every bitmap member decodes")
	for path in _find(paths.root):
		var f := ContainerFile.new()
		if not f.open(path):
			failures.append("%s: %s" % [path.get_file(), f.error])
			continue
		var c := Cast.new()
		if not c.open(f):
			f.close()
			continue
		for number in c.member_numbers():
			var m: Dictionary = c.member(number)
			if int(m.get("type", 0)) != 1:
				continue
			var depth := int(m.get("bits_per_pixel", 0))
			depths[depth] = int(depths.get(depth, 0)) + 1
			if int(m.get("width", 0)) <= 0 or int(m.get("height", 0)) <= 0:
				zero_area += 1
				continue
			var chunk_id := int(m.get("data_chunk_id", -1))
			if chunk_id < 0:
				no_chunk += 1
				continue
			var chunk: PackedByteArray = f.read_chunk(chunk_id)
			var needed := int(m.get("row_stride", 0)) * int(m.get("height", 0))
			if chunk.size() == needed:
				raw += 1
			var error: Array = []
			var image: Image = Bitmap.decode(m, chunk, table, error)
			if image == null:
				failures.append("%s %d (%s): %s" % [
					path.get_file(), number, m.get("name", ""), "; ".join(error),
				])
			else:
				decoded += 1
		f.close()
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0

	h.check(
		"every bitmap decoded",
		failures.is_empty(),
		"%d decoded, %d failed" % [decoded, failures.size()],
	)
	for line in failures.slice(0, 12):
		print("     %s" % line)
	if failures.size() > 12:
		print("     ... and %d more" % (failures.size() - 12))
	# A depth census that collapses to one value means the depth field is being
	# ignored, which is exactly the misread this reader exists to avoid.
	h.check("more than one depth is present", depths.size() > 1, str(depths))
	h.complete("every bitmap member decodes")

	print("")
	print("decoded    : %d  (%d stored raw, %d zero-area, %d without a BITD)" % [
		decoded, raw, zero_area, no_chunk,
	])
	print("elapsed    : %.0f ms" % elapsed)
	print("by depth   :")
	var keys := depths.keys()
	keys.sort()
	for key in keys:
		print("  %8d  %d bpp" % [int(depths[key]), int(key)])

	quit(h.finish("every bitmap in the game decodes from its own container"))


func _dump(paths, args: Dictionary, table: PackedByteArray) -> void:
	var path = paths.resolve(Args.text(args, "file"))
	if path == "":
		print("no such container: %s" % Args.text(args, "file"))
		return
	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		return
	var c := Cast.new()
	if not c.open(f):
		print("%s: %s" % [path, c.error])
		f.close()
		return

	var number := Args.number(args, "member", 0)
	var wanted := Args.text(args, "name")
	if wanted != "":
		number = c.number_of(wanted)
		if number == 0:
			print("no member named %s in %s" % [wanted, path])
			f.close()
			return
	var m: Dictionary = c.member(number)
	if m.is_empty() or int(m.get("type", 0)) != 1:
		print("member %d is %s, not a bitmap" % [number, m.get("type_name", "absent")])
		f.close()
		return

	var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
	var error: Array = []
	var image: Image = Bitmap.decode(m, chunk, table, error)
	if image == null:
		print("member %d (%s) did not decode: %s" % [number, m.get("name", ""), "; ".join(error)])
		f.close()
		return

	var out := Args.text(args, "out", "user://member_%d.png" % number)
	var err := image.save_png(out)
	print("%s member %d '%s'  %dx%d  %d bpp  reg(%d,%d)  chunk %d bytes" % [
		path.get_file(), number, m.get("name", ""), m["width"], m["height"],
		m.get("bits_per_pixel", 0), m["reg_offset_x"], m["reg_offset_y"], chunk.size(),
	])
	if err == OK:
		print("wrote %s  ->  %s" % [out, ProjectSettings.globalize_path(out)])
	else:
		print("could not write %s (%s)" % [out, error_string(err)])
	f.close()


func _find(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, out)
	out.sort()
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
