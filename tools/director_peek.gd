extends SceneTree
## Look inside one Director container: what it holds, and what a chunk contains.
##
##   godot --headless --script tools/director_peek.gd -- --file strtgame.dir
##   godot --headless --script tools/director_peek.gd -- --file strtgame.dir --tag CASt
##   godot --headless --script tools/director_peek.gd -- --file strtgame.dir --id 1164 --text
##   godot --headless --script tools/director_peek.gd -- --file MASTER.CST --tag CASt --text --limit 3
##   godot --headless --script tools/director_peek.gd -- --file strtgame.dir --id 1164 --out user://chunk.bin
##
## Diagnostic, not a parser. `--text` pulls printable runs out of a chunk without
## claiming to understand its layout, which is enough to answer "is the thing we
## expect actually in there" before the chunk has a reader of its own.
##
## It is how the Lingo was located: `Lscr` holds compiled bytecode and its string
## literals, `Lnam` the identifier table, and the *source* sits in the `CASt`
## member records — which is why parsing `CASt` unlocks both the cast and the
## scripts. Reach for this before writing a theory about a chunk.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Paths := preload("res://director/director_paths.gd")

## Runs shorter than this are noise: lengths, ids and coordinates that happen to
## land in the printable range.
const MIN_RUN := 6


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var wanted := Args.text(args, "file", paths.boot_movie)
	var path := paths.resolve(wanted)
	if path == "":
		print("no such container under %s: %s" % [paths.root, wanted])
		quit(1)
		return

	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		quit(1)
		return

	print("file       : %s" % path)
	print("byte order : %s" % ("RIFX (big-endian)" if f.big_endian else "XFIR (little-endian)"))
	print("codec      : %s" % f.codec)
	print("length     : %d bytes" % f.length())
	print("chunks     : %d" % f.chunks.size())

	var tag := Args.text(args, "tag")
	var id := Args.number(args, "id", -1)
	var want_text := Args.flag(args, "text")
	var limit := Args.number(args, "limit", 10)
	var out_path := Args.text(args, "out")

	if tag == "" and id < 0:
		_print_census(f)
		print("")
		print("pass --tag <fourCC> to list, --id <n> to inspect one, --text for readable runs")
		f.close()
		quit(0)
		return

	var ids: Array = []
	if id >= 0:
		ids = [id]
	else:
		ids = f.ids_of(tag)
		print("")
		print("%s: %d chunk(s)" % [tag, ids.size()])
		if ids.is_empty():
			f.close()
			quit(0)
			return
		# Biggest first: the largest of a kind shows the most structure.
		ids.sort_custom(func(a, b): return int(f.chunks[a]["size"]) > int(f.chunks[b]["size"]))
		ids = ids.slice(0, limit)

	for chunk_id in ids:
		var entry: Dictionary = f.chunks[chunk_id]
		var data := f.read_chunk(chunk_id)
		print("")
		print("--- id %d  %s  %d bytes%s" % [
			chunk_id, entry["tag"], entry["size"],
			"" if f.error == "" else "  (%s)" % f.error,
		])
		if data.is_empty():
			continue
		if out_path != "":
			var target := out_path if ids.size() == 1 else "%s.%d" % [out_path, chunk_id]
			var w := FileAccess.open(target, FileAccess.WRITE)
			if w == null:
				print("    cannot write %s" % target)
			else:
				w.store_buffer(data)
				w.close()
				print("    wrote %s" % target)
		if want_text:
			var runs := _printable_runs(data)
			if runs.is_empty():
				print("    (no printable runs of %d+ characters)" % MIN_RUN)
			for run in runs.slice(0, 40):
				print("    %s" % run)
		else:
			print("    %s" % _hex_preview(data))

	f.close()
	quit(0)


func _print_census(f) -> void:
	print("")
	var census: Dictionary = f.census()
	var tags := census.keys()
	tags.sort_custom(func(a, b): return int(census[a]) > int(census[b]))
	for tag in tags:
		print("  %8d  %s" % [int(census[tag]), tag])


## Printable ASCII runs, which is all that can be claimed about a chunk whose
## layout is not yet known.
func _printable_runs(data: PackedByteArray) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	for byte in data:
		if byte >= 0x20 and byte <= 0x7e:
			current += char(byte)
		else:
			if current.length() >= MIN_RUN:
				out.append(current)
			current = ""
	if current.length() >= MIN_RUN:
		out.append(current)
	return out


func _hex_preview(data: PackedByteArray, count: int = 48) -> String:
	var shown := data.slice(0, min(count, data.size()))
	var hex := ""
	for byte in shown:
		hex += "%02x " % byte
	if data.size() > shown.size():
		hex += "..."
	return hex.strip_edges()
