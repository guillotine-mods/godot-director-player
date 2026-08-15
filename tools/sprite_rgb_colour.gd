extends SceneTree
## How many sprite records store a colour as a true RGB rather than as a palette
## index, what those colours are, and what the port draws instead.
##
##   godot --headless --path . --audio-driver Dummy --script tools/sprite_rgb_colour.gd
##   godot --headless --path . --audio-driver Dummy --script tools/sprite_rgb_colour.gd -- --root piposh2
##   godot --headless --path . --audio-driver Dummy --script tools/sprite_rgb_colour.gd -- --list
##
## `bugs.md` 30. Bits `0x10` and `0x20` of a D7 sprite record's colour-code byte
## (offset 20) say that the fore or the back colour is a **true colour** and not
## an index: the red component stays in bytes 2 and 3, and bytes 24-27 carry the
## greens and blues (`frame.cpp:readSpriteDataD7`, ScummVM 805f259a). The port
## reads bytes 2 and 3 as indices unconditionally
## (`director_score.gd:622-623`), so those sprites take whatever the palette holds
## at that index, and `FORE_COLOR_RGB_FLAG`/`BACK_COLOR_RGB_FLAG` are declared at
## `director_score.gd:96-97` and referenced nowhere.
##
## ## What this counts, and why it is not the record count
##
## The entry's own number is records, and a record count is the wrong size for
## this: 800 frames of one motionless sprite is 800 records and one picture. So
## this counts three things and prints all of them, because they answer different
## questions:
##
##   **records**      how often the score states it, which is what a decoder sees;
##   **(movie, channel, colour)**  how many distinct sprites carry one, which is
##                    closer to how many pictures are wrong;
##   **members**      which cast members are ever drawn with one, which is the
##                    number a person could go and look at.
##
## And it splits the back-colour half by ink, because the back colour is not only
## a tint: Background Transparent keys every pixel equal to it (§2.1,
## `director_ink.gd:key_paper`), so a record whose paper is an RGB the port
## resolves as some palette entry keys out the wrong pixels entirely. A back-RGB
## record on a Copy-ink bitmap costs nothing at all; one on `bgTrans` costs the
## silhouette.
##
## ## Reading the record here rather than through `_snapshot`
##
## `director_score.gd` does not decode bytes 24-27 -- that absence *is* the bug --
## so the bytes are read off `channel_buffer` directly, with the same occupancy
## test `_snapshot` and `tools/sprite_record_bytes.gd` use so that all three agree
## on which records exist. Nothing here is a second decoder: it reads four bytes
## the first one does not.
##
## Title-agnostic: it names no game and discovers its roots by listing them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Ink := preload("res://director/director_ink.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]

## Bytes 24-27, in the reference's own order: fore green, back green, fore blue,
## back blue. The red component of each is the byte the port reads as an index.
const FORE_G_AT := 24
const BACK_G_AT := 25
const FORE_B_AT := 26
const BACK_B_AT := 27

## How many distinct colours to name before summarising.
const LIST_LIMIT := 16


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var case := "true-RGB sprite colours across the corpus"
	h.begin(case)

	var roots: Array[String] = []
	var one := Args.text(args, "root", "")
	if one != "":
		roots.append(one if one.begins_with("res://") else "res://games".path_join(one))
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	roots.sort()

	var total_records := 0
	var total_movies := 0
	var fore_records := 0
	var back_records := 0
	var fore_colours: Dictionary = {}
	var back_colours: Dictionary = {}
	var sprites: Dictionary = {}
	var members: Dictionary = {}
	var back_by_ink: Dictionary = {}
	var per_root: Dictionary = {}
	var listed: Array[String] = []

	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		var root_fore := 0
		var root_back := 0
		var root_records := 0
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var vwsc: Array = f.ids_of("VWSC")
			if vwsc.is_empty():
				f.close()
				continue
			var score := Score.new()
			if not score.parse(f.read_chunk(int(vwsc[0]))):
				f.close()
				continue
			total_movies += 1
			for i in score.frame_count:
				var buffer := score.channel_buffer(i)
				for channel in range(1, score.channels_displayed + 1):
					var at: int = Score.SPRITE_RECORD_SIZE * (channel + Score.CHANNEL_BIAS)
					if at + Score.SPRITE_RECORD_SIZE > buffer.size():
						break
					var cast_id := (buffer[at + 6] << 8) | buffer[at + 7]
					var height := (buffer[at + 16] << 8) | buffer[at + 17]
					var width := (buffer[at + 18] << 8) | buffer[at + 19]
					if cast_id <= 0 or width <= 0 or height <= 0 \
							or width >= 32768 or height >= 32768:
						continue
					total_records += 1
					root_records += 1
					var code := buffer[at + Score.COLOR_CODE_AT]
					var has_fore := (code & Score.FORE_COLOR_RGB_FLAG) != 0
					var has_back := (code & Score.BACK_COLOR_RGB_FLAG) != 0
					if not has_fore and not has_back:
						continue
					var cast_lib := (buffer[at + 4] << 8) | buffer[at + 5]
					var ink := buffer[at + 1] & Ink.INK_MASK
					var member_key := "%s %d:%d" % [path.get_file(), cast_lib, cast_id]
					members[member_key] = true
					if has_fore:
						fore_records += 1
						root_fore += 1
						var c := "(%d,%d,%d)" % [buffer[at + 2],
							buffer[at + FORE_G_AT], buffer[at + FORE_B_AT]]
						fore_colours[c] = int(fore_colours.get(c, 0)) + 1
						sprites["F %s ch%d %s" % [path.get_file(), channel, c]] = true
					if has_back:
						back_records += 1
						root_back += 1
						var c := "(%d,%d,%d)" % [buffer[at + 3],
							buffer[at + BACK_G_AT], buffer[at + BACK_B_AT]]
						back_colours[c] = int(back_colours.get(c, 0)) + 1
						sprites["B %s ch%d %s" % [path.get_file(), channel, c]] = true
						var ink_name := "ink %d%s" % [ink,
							" (bgTrans, keys against this colour)"
								if ink == Ink.BACKGND_TRANS else ""]
						back_by_ink[ink_name] = int(back_by_ink.get(ink_name, 0)) + 1
					if Args.flag(args, "list") and listed.size() < 200:
						listed.append(
							"%-14s %-16s ch%-3d %d:%-4d ink %-3d code 0x%02x  fore idx %-3d rgb (%d,%d,%d)  back idx %-3d rgb (%d,%d,%d)" % [
							root.get_file(), path.get_file(), channel, cast_lib,
							cast_id, ink, code,
							buffer[at + 2], buffer[at + 2], buffer[at + FORE_G_AT],
							buffer[at + FORE_B_AT],
							buffer[at + 3], buffer[at + 3], buffer[at + BACK_G_AT],
							buffer[at + BACK_B_AT]])
			f.close()
		per_root[root.get_file()] = [root_records, root_fore, root_back]

	# ------------------------------------------------------------------ report
	print("%d movie(s) over %d root(s), %d occupied sprite records" % [
		total_movies, roots.size(), total_records])
	print("")
	print("%-18s %12s %10s %10s" % ["root", "records", "fore RGB", "back RGB"])
	var names: Array = per_root.keys()
	names.sort()
	for n in names:
		var row: Array = per_root[n]
		print("%-18s %12d %10d %10d" % [n, int(row[0]), int(row[1]), int(row[2])])
	print("")
	print("distinct sprites (movie, channel, colour) carrying one : %d" % sprites.size())
	print("distinct cast members ever drawn with one              : %d" % members.size())
	print("")
	_name("fore colours", fore_colours)
	_name("back colours", back_colours)
	print("")
	print("the back-colour half by ink -- Background Transparent is the one that")
	print("keys against this colour, so it is the one where a wrong answer costs")
	print("the silhouette rather than a tint:")
	var inks: Array = back_by_ink.keys()
	inks.sort()
	for k in inks:
		print("  %-42s %d" % [k, int(back_by_ink[k])])
	for line in listed:
		print("  %s" % line)

	# ------------------------------------------------------------- assertions
	h.check("the sweep read a corpus at all",
		total_movies > 0 and total_records > 0,
		"%d movie(s), %d record(s)" % [total_movies, total_records])
	# The flags are only meaningful if they are not set on everything: a byte
	# misread would light up uniformly, and a population that is a small,
	# specific minority is what says the two bits mean what the reference says.
	h.check("the RGB bits are a minority of records, not a misread byte",
		fore_records + back_records < total_records / 2,
		"%d fore + %d back of %d" % [fore_records, back_records, total_records])
	h.complete(case)
	quit(h.finish("how much true-RGB sprite colour this corpus carries"))


func _name(label: String, counts: Dictionary) -> void:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var parts: Array[String] = []
	for k in keys.slice(0, LIST_LIMIT):
		parts.append("%s x%d" % [str(k), int(counts[k])])
	print("%-14s %d distinct: %s" % [label, keys.size(), ", ".join(parts)])


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
