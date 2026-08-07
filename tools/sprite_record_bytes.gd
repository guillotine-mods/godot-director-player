extends SceneTree
## What each of the 48 bytes of a sprite record actually holds.
##
##   godot --headless --script tools/sprite_record_bytes.gd -- --all
##   godot --headless --script tools/sprite_record_bytes.gd -- --file PIPDATA/OPENING.dir
##
## Why this exists. `director_score.gd` decoded the flip, blend and tweened flags
## out of byte 4 and the blend amount out of byte 19, on the reading that byte 4
## is D4's "thickness byte". Both offsets are already claimed by fields the same
## decoder reads: byte 4 is the high half of the `castLib` at +4, and byte 19 is
## the low half of the `width` at +18. Two decodes cannot both be right about one
## byte, and the flag counts were the tell — flip, blend and tweened came out
## **0** across 816,318 Piposh 2 records and **0** across 1,886,362 Piposh 1
## records, which is what reading a structurally-zero byte looks like.
##
## The way to settle it without guessing is to stop asking "is my field here" and
## ask the bytes what they are: for every offset, how many distinct values it
## ever takes and what they are. An offset that is constant across two million
## records holds nothing; an offset that ranges over 0-100 is a percentage; an
## offset whose values are all multiples of a bit is a flag field.
##
## Reads occupied records only — the same member-and-size test `_snapshot` uses —
## because an empty channel is 48 zero bytes and would drown every column.
##
## Title-agnostic: it names no movie and knows nothing about either game.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")

## How many distinct values to print in full before summarising as a range.
const LIST_LIMIT := 12


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	if Args.flag(args, "all"):
		_walk(paths.root, targets)
		targets.sort()
	else:
		var one: String = paths.resolve(Args.text(args, "file", paths.boot_movie))
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	# One dictionary per byte offset: value -> count.
	var columns: Array[Dictionary] = []
	for i in Score.SPRITE_RECORD_SIZE:
		columns.append({})
	var records := 0
	var movies := 0

	for path in targets:
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
		movies += 1
		for i in score.frame_count:
			var buffer := score.channel_buffer(i)
			for channel in range(1, score.channels_displayed + 1):
				var at: int = Score.SPRITE_RECORD_SIZE * (channel + Score.CHANNEL_BIAS)
				if at + Score.SPRITE_RECORD_SIZE > buffer.size():
					break
				# The occupancy test `_snapshot` uses, so the two agree on which
				# records exist. Anything else counts empty channels as data.
				var cast_id := (buffer[at + 6] << 8) | buffer[at + 7]
				var height := (buffer[at + 16] << 8) | buffer[at + 17]
				var width := (buffer[at + 18] << 8) | buffer[at + 19]
				if cast_id <= 0 or width <= 0 or height <= 0 or width >= 32768 or height >= 32768:
					continue
				records += 1
				for k in Score.SPRITE_RECORD_SIZE:
					var byte := buffer[at + k]
					var column: Dictionary = columns[k]
					column[byte] = int(column.get(byte, 0)) + 1
		f.close()

	print("%d movie(s), %d occupied sprite records" % [movies, records])
	print("")
	print("offset  distinct  values (count)")
	for k in Score.SPRITE_RECORD_SIZE:
		var column: Dictionary = columns[k]
		var keys: Array = column.keys()
		keys.sort()
		var text := ""
		if keys.size() <= LIST_LIMIT:
			for v in keys:
				text += "0x%02x:%d  " % [int(v), int(column[v])]
		else:
			text = "0x%02x..0x%02x" % [int(keys[0]), int(keys[keys.size() - 1])]
		print("  %2d      %4d    %s" % [k, keys.size(), text])

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.check("found occupied records", records > 0, "%d records" % records)
	h.complete("the survey ran")

	# The layout, asserted rather than printed. These are the invariants that
	# would have caught the original mistake, so they are the ones worth keeping.
	h.begin("the record layout holds")
	# No field the decoder reads may sit inside another one. This is the whole of
	# what went wrong before -- the flags byte was read from the cast lib's high
	# half and the blend amount from the width's low half -- and it is a static
	# property of the constants, so it costs nothing to keep asserting.
	var claimed: Dictionary = {}
	var overlap := ""
	for span in [[0, 1, "sprite type"], [1, 1, "ink"], [2, 1, "fore colour"],
			[3, 1, "back colour"], [4, 2, "cast lib"], [6, 2, "member"],
			[Score.SPRITE_LIST_IDX_AT, 4, "sprite list index"],
			[12, 2, "loc v"], [14, 2, "loc h"], [16, 2, "height"], [18, 2, "width"],
			[Score.COLOR_CODE_AT, 1, "colour code"],
			[Score.BLEND_AMOUNT_AT, 1, "blend amount"],
			[Score.THICKNESS_AT, 1, "thickness"],
			[Score.SPRITE_FLAGS_AT, 1, "flags"]]:
		for k in int(span[1]):
			var byte: int = int(span[0]) + k
			if claimed.has(byte):
				overlap += "%d: %s and %s  " % [byte, str(claimed[byte]), str(span[2])]
			claimed[byte] = span[2]
	h.check("no two decoded fields claim the same byte", overlap == "", overlap)
	# Every occupied record names a cast-member sprite. If the layout were
	# shifted by even one byte this column would be whatever the ink or the
	# colours happen to hold.
	var types: Dictionary = columns[0]
	h.check("byte 0 is only ever a sprite type", types.size() <= 4,
		"%d distinct value(s)" % types.size())
	# D7's twelve alignment bytes. The reference hexdumps them when they are not
	# zero and neither corpus has ever made it do so; a reader that had the
	# record size or the channel bias wrong would find data here.
	var tail_used := ""
	for k in range(36, Score.SPRITE_RECORD_SIZE):
		if (columns[k] as Dictionary).size() > 1 or not (columns[k] as Dictionary).has(0):
			tail_used += "%d " % k
	h.check("bytes 36-47 are the alignment the reference says they are",
		tail_used == "", tail_used)
	h.complete("the record layout holds")
	quit(h.finish("sprite record byte occupancy"))
