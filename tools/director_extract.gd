extends SceneTree
## Extract everything readable from one Director container to a folder.
##
##   godot --headless --script tools/director_extract.gd -- --file MASTER.CST --out C:/tmp/master
##   godot --headless --script tools/director_extract.gd -- --file DAY1.DIR --out C:/tmp/day1 --limit 50
##
## Writes, under `--out`:
##
##   bitmaps/<number>_<name>.png    every bitmap member, decoded
##   fields/<number>_<name>.txt     every text member's text
##   scripts/<number>_<name>.ls     every member's Lingo source
##   members.txt                    one line per member: number, type, name, size
##
## A viewing and diffing aid, not part of the runtime. It exists because looking
## at an asset settles in seconds what a theory about coordinates argues about
## for an hour, and because the script source coming out of the cast is the
## claim most worth checking by eye against `reference/lingo/`.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const Bitmap := preload("res://director/director_bitmap.gd")

## What the runtime's ink passes treat as paper: every channel at or above this.
const PAPER_MIN_BYTE := 241


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var wanted := Args.text(args, "file")
	var out_root := Args.text(args, "out")
	if wanted == "" or out_root == "":
		print("usage: --file <container> --out <folder> [--limit N]")
		quit(1)
		return

	var path = paths.resolve(wanted)
	if path == "":
		print("no such container under %s: %s" % [paths.root, wanted])
		quit(1)
		return

	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		quit(1)
		return
	var cast := Cast.new()
	if not cast.open(f):
		print("%s: %s" % [path, cast.error])
		f.close()
		quit(1)
		return

	for sub in ["bitmaps", "fields", "scripts"]:
		DirAccess.make_dir_recursive_absolute(out_root.path_join(sub))

	var limit := Args.number(args, "limit", 0)
	## Viewing aid only. A member has no transparency of its own — the ink on the
	## sprite in the score decides that, so the same bitmap draws opaque in one
	## room and keyed in another. Baking alpha here would be wrong for the
	## runtime and is exactly right for looking at the art.
	var key_paper := Args.flag(args, "key")
	## Decode everything, write nothing. Isolates the cost the runtime actually
	## pays from PNG encoding and disk I/O, which it never does.
	var no_write := Args.flag(args, "no-write")
	var table: PackedByteArray = Palette.system_mac()
	var decode_us := 0
	var write_us := 0
	var pixels_out := 0
	var manifest := PackedStringArray()
	var counts := {"bitmap": 0, "field": 0, "script": 0, "failed": 0, "skipped": 0}
	var started := Time.get_ticks_usec()
	var seen := 0

	print("%s  %s  %d slot(s)" % [
		path, "XFIR" if not f.big_endian else "RIFX", cast.member_count,
	])

	for number in cast.member_numbers():
		if limit > 0 and seen >= limit:
			break
		seen += 1
		var m: Dictionary = cast.member(number)
		if m.is_empty():
			continue
		var name := str(m.get("name", ""))
		var stem := "%04d_%s" % [number, _safe(name if name != "" else "unnamed")]
		manifest.append("%4d  %-10s %-20s %s" % [
			number, m.get("type_name", "?"), name,
			("%dx%d %dbpp" % [m.get("width", 0), m.get("height", 0), m.get("bits_per_pixel", 0)])
				if int(m.get("type", 0)) == 1 else "",
		])

		# Lingo source, which lives in the member record rather than in Lscr.
		var source := str(m.get("source", ""))
		if source.strip_edges() != "":
			if _write_text(out_root.path_join("scripts/%s.ls" % stem), source):
				counts["script"] += 1

		match int(m.get("type", 0)):
			1:
				var chunk_id := int(m.get("data_chunk_id", -1))
				if chunk_id < 0 or int(m.get("width", 0)) <= 0:
					counts["skipped"] += 1
					continue
				var t0 := Time.get_ticks_usec()
				var chunk: PackedByteArray = f.read_chunk(chunk_id)
				var error: Array = []
				var image: Image = Bitmap.decode(m, chunk, table, error)
				if key_paper and image != null:
					_key_paper(image)
				var t1 := Time.get_ticks_usec()
				decode_us += t1 - t0
				if image == null:
					counts["failed"] += 1
					print("  member %d (%s): %s" % [number, name, "; ".join(error)])
					continue
				pixels_out += image.get_width() * image.get_height()
				# `--no-write` is the measurement the runtime cares about: it
				# decodes exactly as normal and skips the PNG encode and the file
				# write, neither of which the game ever does.
				if no_write:
					counts["bitmap"] += 1
				elif image.save_png(out_root.path_join("bitmaps/%s.png" % stem)) == OK:
					counts["bitmap"] += 1
				else:
					counts["failed"] += 1
				write_us += Time.get_ticks_usec() - t1
			3:
				if _write_text(out_root.path_join("fields/%s.txt" % stem), str(m.get("text", ""))):
					counts["field"] += 1

	if not no_write:
		_write_text(out_root.path_join("members.txt"), "\n".join(manifest) + "\n")
	f.close()

	print("")
	print("bitmaps  : %d png" % counts["bitmap"])
	print("fields   : %d txt" % counts["field"])
	print("scripts  : %d ls" % counts["script"])
	if int(counts["failed"]) > 0:
		print("failed   : %d" % counts["failed"])
	if int(counts["skipped"]) > 0:
		print("skipped  : %d (no pixels)" % counts["skipped"])
	var bitmaps := int(counts["bitmap"])
	print("")
	print("decode   : %7.0f ms   %.2f ms/member   (what the runtime pays)" % [
		decode_us / 1000.0, (decode_us / 1000.0) / max(bitmaps, 1),
	])
	print("write    : %7.0f ms   %.2f ms/member   (PNG encode + disk; runtime pays none)" % [
		write_us / 1000.0, (write_us / 1000.0) / max(bitmaps, 1),
	])
	print("pixels   : %d decoded" % pixels_out)
	print("total    : %7.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	if not no_write:
		print("out      : %s" % out_root)
	quit(0)


## Key out paper so the extracted PNG can be viewed against any background.
## The whole-image sweep, matching Background Transparent rather than Matte:
## Matte keys only the paper reachable from the edge, which is the right
## behaviour on the stage and the wrong one for inspecting a sprite in isolation.
func _key_paper(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r8 >= PAPER_MIN_BYTE and c.g8 >= PAPER_MIN_BYTE and c.b8 >= PAPER_MIN_BYTE:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))


func _write_text(target: String, text: String) -> bool:
	var w := FileAccess.open(target, FileAccess.WRITE)
	if w == null:
		return false
	w.store_string(text)
	w.close()
	return true


## Member names carry spaces and punctuation ("jokes funk"), which is fine in
## Director and not fine in a filename.
func _safe(name: String) -> String:
	var out := ""
	for i in name.length():
		var c := name[i]
		out += c if c.is_valid_identifier() or c in "._-" else "_"
	return out.substr(0, 48)
